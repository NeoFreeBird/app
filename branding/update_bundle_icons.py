#!/usr/bin/env python3
"""Rewrite an app's CFBundleIcons to match a compiled asset catalog.

Usage: update_bundle_icons.py <Info.plist> <catalog_dir>

Enumerates the app-icon assets in a scar-decompiled catalog directory (the
merged directory scar_merge.py leaves in its --workdir), groups the primary
icon's renditions by idiom, and rewrites CFBundleIcons / CFBundleIcons~ipad in
the given Info.plist so they reference the icons actually present.
"""

import json
import os
import plistlib
import re
import sys

IDIOM_PHONE, IDIOM_PAD, IDIOM_MARKETING = 1, 2, 6


def main() -> int:
    if len(sys.argv) != 3:
        sys.stderr.write("usage: update_bundle_icons.py <Info.plist> <catalog_dir>\n")
        return 2
    plist_path, catalog = sys.argv[1], sys.argv[2]

    try:
        with open(os.path.join(catalog, "manifest.json")) as fh:
            manifest = json.load(fh)
    except (ValueError, OSError) as exc:
        sys.stderr.write("could not read catalog manifest: %s\n" % exc)
        return 1

    facets = {f["name"]: f["attributes"].get("identifier") for f in manifest["facets"]}
    by_ident = {}
    for r in manifest["renditions"]:
        by_ident.setdefault(r["key"].get("identifier"), []).append(r)

    # App-icon assets are the facets that own multisize (MSIS) stubs; a catalog
    # may hold several sets (the primary plus alternate icons). We only rewrite
    # the PRIMARY set's file list and reconcile the alternates by name.
    icon_names = sorted(n for n, i in facets.items()
                        if any(r["content"]["type"] == "multisize" for r in by_ident.get(i, [])))
    if not icon_names:
        sys.stderr.write("no app-icon assets found in %s\n" % catalog)
        return 3

    with open(plist_path, "rb") as fh:
        info = plistlib.load(fh)

    def existing_primary_name(key):
        d = info.get(key)
        if isinstance(d, dict) and isinstance(d.get("CFBundlePrimaryIcon"), dict):
            return d["CFBundlePrimaryIcon"].get("CFBundleIconName")
        return None

    primary_name = existing_primary_name("CFBundleIcons") \
        or existing_primary_name("CFBundleIcons~ipad")
    if primary_name not in set(icon_names):
        # No usable hint from the plist: prefer a "production" set, else the one
        # with the most renditions (the real home-screen icon).
        prod = [n for n in icon_names if "production" in n.lower()]
        primary_name = prod[0] if prod else \
            max(icon_names, key=lambda n: len(by_ident.get(facets[n], [])))

    # idiom bucket -> [base, ...] (unique, ordered) for the primary set only.
    buckets = {"phone": [], "pad": []}

    def add(key, base):
        if base not in buckets[key]:
            buckets[key].append(base)

    for r in by_ident.get(facets[primary_name], []):
        c = r["content"]
        if c["type"] == "link":
            w, h = c["rect"][2:4]
        elif c["type"] in ("image", "raw-payload"):
            w, h = r["width"], r["height"]
        else:
            continue
        scale = r["key"].get("scale") or 1
        idiom = r["key"].get("idiom", 0)
        if idiom == IDIOM_MARKETING:
            continue
        # CFBundleIconFiles base name, e.g. "AppIcon" + "60x60" -> "AppIcon60x60".
        base = "%s%gx%g" % (primary_name, w / scale, h / scale)
        if idiom == IDIOM_PHONE:
            add("phone", base)
        elif idiom == IDIOM_PAD:
            add("pad", base)
        else:
            add("phone", base)
            add("pad", base)

    # Prefer the size list the app already shipped, renamed to the primary
    # (the catalog-derived list can include phantom sizes from oddly-keyed
    # renditions, e.g. 180px renditions tagged @2x). Sizes the catalog no
    # longer offers are dropped; a plist with no usable list keeps the
    # derived one.
    def preserved_sizes(key):
        d = info.get(key)
        prim = d.get("CFBundlePrimaryIcon") if isinstance(d, dict) else None
        files = prim.get("CFBundleIconFiles") if isinstance(prim, dict) else None
        if not isinstance(files, list):
            return None
        return [m.group(1) for f in files if isinstance(f, str)
                for m in [re.search(r"(\d+(?:\.\d+)?x\d+(?:\.\d+)?)$", f)] if m]

    # Sizes are checked against both idioms' renditions: the stock plist lists
    # 60x60 for iPad (iPhone-app compat) even though only phone renditions
    # carry that size.
    derived_sizes = {b[len(primary_name):] for bucket in buckets.values() for b in bucket}
    for key, bucket in (("CFBundleIcons", "phone"), ("CFBundleIcons~ipad", "pad")):
        kept = [primary_name + s for s in preserved_sizes(key) or [] if s in derived_sizes]
        if kept:
            buckets[bucket] = kept

    def make_primary(files):
        return {"CFBundleIconFiles": files, "CFBundleIconName": primary_name} if files else None

    phone_primary = make_primary(buckets["phone"])
    pad_primary = make_primary(buckets["pad"])

    present = set(icon_names)

    def set_primary(key, primary):
        # Keep existing alternate declarations and their metadata, removing
        # only X-branded custom icons. Add every compiled pack icon. An
        # alternate's plist key can differ from its CFBundleIconName.
        icons = info.get(key)
        if not isinstance(icons, dict):
            icons = {}
        icons["CFBundlePrimaryIcon"] = primary
        alts = icons.get("CFBundleAlternateIcons")
        if not isinstance(alts, dict):
            alts = {}
        def asset_name(name, entry):
            return entry.get("CFBundleIconName", name) if isinstance(entry, dict) else name

        def is_x(name):
            return isinstance(name, str) and name.lower().startswith("custom-icon-x-")

        for name in list(alts):
            if is_x(name) or is_x(asset_name(name, alts[name])):
                del alts[name]
        declared = {asset_name(name, entry) for name, entry in alts.items()}
        for name in sorted(present):
            if name != primary_name and name not in declared and not is_x(name):
                alts.setdefault(name, {"CFBundleIconName": name})
        if alts:
            icons["CFBundleAlternateIcons"] = alts
        elif "CFBundleAlternateIcons" in icons:
            del icons["CFBundleAlternateIcons"]
        info[key] = icons

    if phone_primary is None and pad_primary is None:
        sys.stderr.write("no app-icon renditions found in %s\n" % catalog)
        return 3

    if phone_primary is not None:
        set_primary("CFBundleIcons", phone_primary)
        # Modern asset-catalog apps also carry a top-level icon name.
        info["CFBundleIconName"] = primary_name
    if pad_primary is not None:
        set_primary("CFBundleIcons~ipad", pad_primary)

    with open(plist_path, "wb") as fh:
        plistlib.dump(info, fh, fmt=plistlib.FMT_BINARY)

    return 0


if __name__ == "__main__":
    sys.exit(main())
