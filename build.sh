#!/usr/bin/env bash
set -Eeuo pipefail

# NeoFreeBird builder with required flags.
# Usage: build.sh [--sideloaded | --rootless | --trollstore | --rootfull]

is_tty=0
if [[ -t 1 ]]; then is_tty=1; fi
bold='' green='' reset=''
if [[ "$is_tty" -eq 1 ]]; then
  if command -v tput >/dev/null 2>&1; then
    bold="$(tput bold || true)"
    green="$(tput setaf 2 || true)"
    reset="$(tput sgr0 || true)"
  else
    bold='\033[1m'; green='\033[32m'; reset='\033[0m'
  fi
fi

inject_appex() {
    local ipa
    ipa="$(realpath "$1")"

    local appex="$SCRIPT_DIR/deps/OpenTwitterSafariExtension/OpenTwitterSafariExtension.appex"

    local tmp
    tmp=$(mktemp -d)

    unzip -q "$ipa" -d "$tmp"

    mkdir -p "$tmp/Payload/Twitter.app/PlugIns"
    cp -R "$appex" "$tmp/Payload/Twitter.app/PlugIns/"

    rm -f "$ipa"

    (
        cd "$tmp"
        zip -qry "$ipa" Payload
    )

    rm -rf "$tmp"
}

say() { if [[ -n "${bold}${green}${reset}" ]]; then printf "%b%s%b\n" "${bold}${green}" "$1" "${reset}"; else printf "%s\n" "$1"; fi; }
err() { printf "Error: %s\n" "$1" >&2; }
die() { err "$1"; exit 1; }

usage() {
  cat <<EOF
Usage: $(basename "$0") [--sideloaded | --rootless | --trollstore | --rootfull]
TL;DR: You need to select one flag to build NeoFreeBird.

Flags (required):
  --sideloaded   Compile NeoFreeBird as a .ipa so you can sideload it with AltStore, Sideloadly or similar.
  --rootless     Compile NeoFreeBird as a .deb file that does not require a jailbreak.
  --trollstore   Compile NeoFreeBird as a .tipa so you can install it using TrollStore.
  --rootfull     Compile NeoFreeBird as a .deb file that requires a jailbreak.

Options:
  -h, --help     Show this help

Branding (name/icons) is applied separately with rebrand.sh on a built IPA.
EOF
}

require_cmd() { command -v "$1" >/dev/null 2>&1 || die "'$1' is required but not found in PATH"; }

require_cmd bash
require_cmd make

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MODE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sideloaded|--sideloaded=*)
      [[ -n "$MODE" ]] && die "Multiple flags provided. Choose one."
      MODE="sideloaded"; shift
      ;;
    --rootless|--rootless=*)
      [[ -n "$MODE" ]] && die "Multiple flags provided. Choose one."
      MODE="rootless"; shift
      ;;
    --trollstore)
      [[ -n "$MODE" ]] && die "Multiple flags provided. Choose one."
      MODE="trollstore"; shift
      ;;
    --rootfull)
      [[ -n "$MODE" ]] && die "Multiple flags provided. Choose one."
      MODE="rootfull"; shift
      ;;
    -h|--help)
      usage; exit 0
      ;;
    --)
      shift; break
      ;;
    -*)
      die "Unknown option: $1"
      ;;
    *)
      # no positional args expected
      die "Unexpected argument: $1"
      ;;
  esac
done

if [[ -z "$MODE" ]]; then
  usage
  exit 2
fi

clean_tree() {
  if [[ -d .theos ]]; then rm -rf .theos; fi
  if [[ -f Makefile ]]; then make clean || true; fi
}

# The ffmpeg stack is built from source, not tracked.
if [[ ! -f "$SCRIPT_DIR/deps/ffmpeg-kit-next/build/lib/libffmpegkit.a" ]]; then
  say "ffmpeg libraries not found; building them from source (this takes a while)."
  git -C "$SCRIPT_DIR" submodule update --init deps/ffmpeg-kit-next/upstream
  "$SCRIPT_DIR/deps/ffmpeg-kit-next/build-ffmpeg.sh"
fi

case "$MODE" in
  sideloaded)
    say "Preparing to compile NeoFreeBird. Argument added: --sideloaded."
    clean_tree
    make SIDELOADED=1
    if [[ $? -ne 0 ]]; then
      die "An error occurred when building."
    fi
    if [[ -e ./packages/com.atebits.Tweetie2.ipa ]]; then
      say "Building the IPA."
      if command -v cyan >/dev/null 2>&1; then
        cyan -i packages/com.atebits.Tweetie2.ipa -o packages/NeoFreeBird-sideloaded --ignore-encrypted \
          -uwf .theos/obj/debug/zxPluginsInject.dylib .theos/obj/debug/libbhFLEX.dylib \
          .theos/obj/debug/BHTwitter.dylib layout/Library/Application\ Support/BHT/BHTwitter.bundle \
          .theos/obj/debug/CallessKit.dylib
        say "Injecting OpenTwitterSafariExtension.appex into the IPA."  
        inject_appex packages/NeoFreeBird-sideloaded.ipa
      else
        say "Skipping cyan step because it is not installed."
      fi
      say "NeoFreeBird has been successfully built. Enjoy!"
    else
      err "packages/com.atebits.Tweetie2.ipa not found."
    fi
    ;;
  rootless)
    say "Preparing to compile NeoFreeBird. Argument added: --rootless."
    clean_tree
    export THEOS_PACKAGE_SCHEME="rootless"
    make package
    say "NeoFreeBird has been successfully built. Enjoy!"
    ;;
  trollstore)
    say "Preparing to compile NeoFreeBird. Argument added: --trollstore."
    clean_tree
    make
    if [[ $? -ne 0 ]]; then
      die "An error occurred when building."
    fi
    if [[ -e ./packages/com.atebits.Tweetie2.ipa ]]; then
      say "Merging NeoFreeBird to provided Twitter IPA."
      if command -v cyan >/dev/null 2>&1; then
        cyan -i packages/com.atebits.Tweetie2.ipa -o packages/NeoFreeBird-trollstore.tipa --ignore-encrypted \
          -uwf .theos/obj/debug/BHTwitter.dylib .theos/obj/debug/libbhFLEX.dylib layout/Library/Application\ Support/BHT/BHTwitter.bundle \
          .theos/obj/debug/CallessKit.dylib
        say "Injecting OpenTwitterSafariExtension.appex into the IPA."  
        inject_appex packages/NeoFreeBird-trollstore.tipa
      else
        say "Skipping cyan step because it is not installed."
      fi
      say "NeoFreeBird has been successfully built. Enjoy!"
    else
      err "packages/com.atebits.Tweetie2.ipa not found."
    fi
    ;;
  rootfull)
    say "Preparing to compile NeoFreeBird. Argument added: --rootfull."
    clean_tree
    unset THEOS_PACKAGE_SCHEME || true
    make package
    say "NeoFreeBird has been successfully built. Enjoy!"
    ;;
  *)
    die "Unknown mode: $MODE"
    ;;
esac
