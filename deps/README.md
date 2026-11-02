# Dependencies

Each dependency lives in a folder named after it, with the upstream repo as a
submodule at `upstream/` and any wrapper files in the folder root.

## flex

https://github.com/FLEXTool/FLEX, wrapped as the `libbhFLEX` subproject
(Makefile and injection filter plist in the folder root).

## zxPluginsInject

https://github.com/asdfzxcvbn/zxPluginsInject (v1.0.1), only built for
sideloaded packages. Built directly from `upstream/`.

## ffmpeg-kit-next

https://github.com/arthenica/ffmpeg-kit-next (v8.1.0), source of the
libffmpegkit wrapper and the pin for the FFmpeg version below. Only needed
when regenerating the prebuilt libraries.

`build/` (headers at the top, libraries in `lib/`) holds the built stack:
ffmpeg-kit-next 8.1.0 (FFmpeg n8.1.2), arm64 iOS, static only. Not tracked
in git: `build.sh` runs `build-ffmpeg.sh` automatically when the libraries
are missing, compiling with Xcode on macOS or cross-compiling with the
Theos toolchain on Linux (cached under /tmp afterwards). FFmpeg is trimmed
to the components the media download flows use (HLS/HTTPS demux,
H.264/HEVC/AAC decode, scale, VideoToolbox H.264 encode, palette-based
GIF encode, mp4/gif mux), with TLS provided by OpenSSL.
The FFmpeg tag must stay in lockstep with the submodule (its vendored
fftools sources compile against FFmpeg internals).

## OpenTwitterSafariExtension
https://github.com/BandarHL/OpenTwitterSafariExtension
Adds a Safari extension to the app, allowing users to open Twitter links in the app instead of Safari. The extension is built as part of the main app target. This is because universal app links do not work in sideloaded apps.

## Machine prerequisites

- **Theos** at `$THEOS`.
- **Cephei / CepheiPrefs / CepheiUI** in `$THEOS/lib` (linked via `EXTRA_FRAMEWORKS`).
- **cyan** (pyzule-rw) for the IPA merge steps in `build.sh`.
- **macOS only:** the full [Xcode](https://developer.apple.com/xcode/) application,
  with its developer directory selected (`sudo xcode-select --switch
  /Applications/Xcode.app/Contents/Developer`). Command Line Tools alone do
  not provide the iPhoneOS SDK required to rebuild ffmpeg.
