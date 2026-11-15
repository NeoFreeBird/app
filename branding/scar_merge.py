#!/usr/bin/env python3
"""Rebuild an app's Assets.car with selected images replaced, using scar.

Usage: scar_merge.py <app_Assets.car> <overlay_dir> <out.car> --workdir DIR [--scar BIN]

Cross-platform replacement for the old actool pipeline (build_merged_car.py +
car_extract.m). scar (https://github.com/theacrat/scar) decompiles the catalog
into editable PNGs plus a manifest and recompiles it, so no Xcode, CoreUI or
assetutil is needed, and every rendition that isn't themed round-trips
byte-identical instead of being rebuilt.

<overlay_dir> holds the pack's loose images (PNG/JPEG):
  - A file whose stem matches an asset name (case-insensitive) is a "master":
    it is pad-resized into every bitmap rendition of that asset — plain
    images, deepmap2/RLE previews, and the packed-atlas crops the primary app
    icon is built from (scar pastes edited crop previews back into the atlas).
    A "<name>-settings" picker thumbnail inherits its base icon's master.
  - A file named exactly after a rendition (e.g. Icon-App-60x60@2x.png)
    overrides just that rendition and beats the asset master.
  - A file matching no existing asset becomes a brand-new alternate icon,
    cloned via `scar clone-asset` (plus its settings-thumbnail asset). Cloned
    atlas links become independent bitmaps so each icon keeps its own art.
  - X-branded alternate icons (Custom-Icon-X-*) are dropped, along with their
    "-settings" thumbnails. Other stock alternates, including Twitter icons,
    remain available even when the pack does not replace them.

--workdir keeps the decompiled-and-edited catalog directory; after a
successful compile it holds the final art, which update_bundle_icons.py and
overwrite_loose_icons.py consume.
"""

import argparse
import json
import os
import re
import subprocess
import sys

from PIL import Image

# Settings-picker thumbnails (<Icon>-settings) reuse their base icon's image.
SETTINGS_SPECIAL = {"icon-production-settings": "ProductionAppIcon"}


def run_scar(scar, *args):
    res = subprocess.run([scar, *args], capture_output=True, text=True)
    if res.returncode != 0:
        sys.stderr.write("scar %s failed:\n%s\n%s\n" % (args[0], res.stdout, res.stderr))
        raise SystemExit(1)
    return res


_resize_cache = {}


def pad_resize(master, w, h):
    """Aspect-preserving resize of `master` to exactly w x h, centered on a
    transparent canvas (a square master is never stretched into a non-square
    slot). Cached per (master, w, h)."""
    key = (master, w, h)
    if key not in _resize_cache:
        try:
            im = Image.open(master).convert("RGBA")
        except OSError as exc:
            sys.stderr.write("unreadable image %s: %s (Apple-optimized CgBI PNGs "
                             "must be converted to standard PNG)\n" % (master, exc))
            raise SystemExit(1)
        scale = min(w / im.width, h / im.height)
        nw, nh = max(1, round(im.width * scale)), max(1, round(im.height * scale))
        canvas = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        canvas.paste(im.resize((nw, nh), Image.LANCZOS), ((w - nw) // 2, (h - nh) // 2))
        _resize_cache[key] = canvas
    return _resize_cache[key]


def install(catalog, rend, master):
    """Write `master` (pad-resized) as the edited pixels of one rendition.
    Returns False for renditions with no editable pixels (multisize stubs,
    data, undecodable codecs)."""
    c = rend["content"]
    if c["type"] == "image":
        target, w, h = c["file"], rend["width"], rend["height"]
    elif c["type"] == "raw-payload" and c.get("preview") and c.get("edit_hash"):
        target, w, h = c["preview"], rend["width"], rend["height"]
    elif c["type"] == "link" and c.get("preview") and c.get("edit_hash"):
        target, (w, h) = c["preview"], c["rect"][2:4]
    else:
        return False
    pad_resize(master, w, h).save(os.path.join(catalog, target))
    return True


def load_catalog(catalog):
    manifest = json.load(open(os.path.join(catalog, "manifest.json")))
    facets = {f["name"]: f["attributes"].get("identifier") for f in manifest["facets"]}
    by_ident = {}
    for r in manifest["renditions"]:
        by_ident.setdefault(r["key"].get("identifier"), []).append(r)
    return manifest, facets, by_ident


def settings_base(name):
    low = name.lower()
    if low in SETTINGS_SPECIAL:
        return SETTINGS_SPECIAL[low]
    if low.endswith("-settings"):
        return name[: -len("-settings")]
    return None


def is_x_icon(name):
    return name.lower().startswith("custom-icon-x-")


def install_clone(catalog, rendition, master, index):
    """Give a cloned rendition independent pixels instead of shared atlas art.

    Keep the template's sizes, scales, idioms and multisize indices intact;
    only replace its bitmap storage. Editing a cloned link's crop preview
    would otherwise repaint the source icon's atlas region as well.
    """
    content = rendition["content"]
    if content["type"] == "multisize":
        return
    if content["type"] == "link":
        width, height = content["rect"][2:4]
        rendition["layout"] = content["content_layout"]
    elif content["type"] in ("image", "raw-payload"):
        width, height = rendition["width"], rendition["height"]
    else:
        raise ValueError("unsupported cloned icon rendition: %s" % content["type"])
    if width <= 0 or height <= 0:
        raise ValueError("cloned icon rendition has no bitmap size")

    target = "renditions/%06d-pack-icon.png" % index
    pad_resize(master, width, height).save(os.path.join(catalog, target))
    rendition["width"], rendition["height"] = width, height
    rendition["pixel_format"] = "ARGB"
    rendition["color_space_id"] = 1  # Pack PNGs are ordinary sRGB images.
    rendition["content"] = {"type": "image", "file": target, "compression": "lzfse"}
    # These describe the old storage, not the new standalone RGBA bitmap.
    for tag in ("0x3f2", "0x3ef"):  # internal link / bytes per row
        rendition.get("extra_tlvs", {}).pop(tag, None)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("car")
    ap.add_argument("overlay_dir")
    ap.add_argument("out_car")
    ap.add_argument("--workdir", required=True)
    ap.add_argument("--scar", default=os.environ.get("NFB_SCAR", "scar"))
    args = ap.parse_args()

    catalog = os.path.join(args.workdir, "catalog")
    run_scar(args.scar, "decompile", args.car, "--out", catalog)
    manifest, facets, by_ident = load_catalog(catalog)

    # Overlay files by exact name (single-rendition overrides) and by stem
    # ("master" images resized into every rendition of the matching asset).
    overlays, masters = {}, {}
    for root, dirs, files in os.walk(args.overlay_dir):
        dirs[:] = [d for d in dirs if d != "__MACOSX"]
        for f in files:
            if f.startswith("._") or not f.lower().endswith((".png", ".jpg", ".jpeg")):
                continue
            if is_x_icon(os.path.splitext(f)[0]):
                print("skip X icon: %s" % f)
                continue
            overlays.setdefault(f, os.path.join(root, f))
            masters.setdefault(os.path.splitext(f)[0].lower(), os.path.join(root, f))
    used = set()

    # App-icon assets are the facets that own multisize (MSIS) stubs.
    icon_names = {n for n, i in facets.items()
                  if any(r["content"]["type"] == "multisize" for r in by_ident.get(i, []))}
    primary = None
    for n in sorted(icon_names):
        if primary is None or "production" in n.lower():
            primary = n

    def master_for(name):
        m = masters.get(name.lower())
        if m:
            return m
        base = settings_base(name)
        if base:
            m = masters.get(base.lower())
            if m:
                return m
            if base in icon_names and "appicon" in masters:
                return masters["appicon"]
        if name in icon_names and "appicon" in masters:
            return masters["appicon"]
        return None

    for name, ident in facets.items():
        m = master_for(name)
        count = 0
        for r in by_ident.get(ident, []):
            src = overlays.get(r["name"]) or m
            if src and install(catalog, r, src):
                used.add(src)
                count += 1
        if count:
            print("replace: %s (%d renditions)" % (name, count))


    def settings_asset_for(name):
        return next((n for n in facets if settings_base(n) == name), None)

    template = next((n for n in sorted(icon_names)
                     if n != primary and settings_asset_for(n)), None)
    if template is None and primary and settings_asset_for(primary):
        template = primary
    template_settings = settings_asset_for(template) if template else None
    new_icons = []
    for f, path in sorted(overlays.items()):
        stem = os.path.splitext(f)[0]
        if path in used or stem in facets:
            continue
        if "@" in stem or re.search(r"\d+x\d+", stem):  # a rendition file, not a master
            continue
        if not template or not template_settings:
            sys.stderr.write("cannot add icon %s: no icon/thumbnail template in the catalog\n" % f)
            return 1
        run_scar(args.scar, "clone-asset", catalog, "--from", template, "--to", stem)
        run_scar(args.scar, "clone-asset", catalog, "--from", template_settings,
                 "--to", "%s-settings" % stem)
        new_icons.append((stem, path))
        used.add(path)

    if new_icons:
        manifest, facets, by_ident = load_catalog(catalog)
        for stem, path in new_icons:
            identifiers = {facets[stem], facets["%s-settings" % stem]}
            for index, r in enumerate(manifest["renditions"]):
                if r["key"].get("identifier") in identifiers:
                    install_clone(catalog, r, path, index)
            print("new icon: %s" % stem)
        json.dump(manifest, open(os.path.join(catalog, "manifest.json"), "w"), indent=2)

    #    Remove X-branded alternates and their settings thumbnails. Keep
    #    unmatched stock icons (notably Twitter's legacy/seasonal icons) so
    #    they remain available in the app's icon picker.
    drop = {n for n in facets if is_x_icon(n)}
    drop |= {n for n in facets if settings_base(n) in drop}
    if drop:
        gone = {facets[n] for n in drop}
        manifest["facets"] = [f for f in manifest["facets"] if f["name"] not in drop]
        manifest["renditions"] = [r for r in manifest["renditions"]
                                  if r["key"].get("identifier") not in gone]
        json.dump(manifest, open(os.path.join(catalog, "manifest.json"), "w"), indent=2)
        print("dropped: %s" % ", ".join(sorted(drop)))

    run_scar(args.scar, "compile", catalog, "--out", args.out_car)

    for p in sorted(set(overlays.values()) - used):
        sys.stderr.write("overlay-unmatched: %s (no rendition or asset with that name)\n"
                         % os.path.basename(p))
    return 0


if __name__ == "__main__":
    sys.exit(main())
