<div align="center">
    <img src="resources/icon_rounded.png" alt="Twitter Bird Icon" width="130" height="130">


  # NeoFreeBird
  <i>The ultimate way to tweak your Twitter/X experience.</i>
  Open the NeoFreeBird settings by holding the Twitter/X icon at the top of the main feed. See [Opening the settings](#opening-the-settings).

  ## Twitter Branding

  <div>
    <a href="https://intradeus.github.io/http-protocol-redirector?r=altstore://source?url=https://raw.githubusercontent.com/NeoFreeBird/app/refs/heads/v7/resources/AltSource.json"><img src="resources/badges/add_to_altstore.png" alt="Add to AltStore" height="40"></a>
    &nbsp;
    <a href="https://intradeus.github.io/http-protocol-redirector?r=sidestore://source?url=https://raw.githubusercontent.com/NeoFreeBird/app/refs/heads/v7/resources/AltSource.json"><img src="resources/badges/add_to_sidestore.png" alt="Add to SideStore" height="40"></a>
    &nbsp;
    <a href="https://intradeus.github.io/http-protocol-redirector?r=feather://source/https://raw.githubusercontent.com/NeoFreeBird/app/refs/heads/v7/resources/AltSource.json"><img src="resources/badges/add_to_feather.png" alt="Add to Feather" height="40"></a>
    &nbsp;
    <a href="https://github.com/NeoFreeBird/app/releases"><img src="resources/badges/download_from_github.png" alt="Download from GitHub" height="40"></a>
    &nbsp;
  </div>

  ## X Branding

  <div>
    <a href="https://intradeus.github.io/http-protocol-redirector?r=altstore://source?url=https://raw.githubusercontent.com/NeoFreeBird/app/refs/heads/v7/resources/AltSource-X.json"><img src="resources/badges/add_to_altstore.png" alt="Add to AltStore" height="40"></a>
    &nbsp;
    <a href="https://intradeus.github.io/http-protocol-redirector?r=sidestore://source?url=https://raw.githubusercontent.com/NeoFreeBird/app/refs/heads/v7/resources/AltSource-X.json"><img src="resources/badges/add_to_sidestore.png" alt="Add to SideStore" height="40"></a>
    &nbsp;
    <a href="https://intradeus.github.io/http-protocol-redirector?r=feather://source/https://raw.githubusercontent.com/NeoFreeBird/app/refs/heads/v7/resources/AltSource-X.json"><img src="resources/badges/add_to_feather.png" alt="Add to Feather" height="40"></a>
    &nbsp;
    <a href="https://github.com/NeoFreeBird/app/releases"><img src="resources/badges/download_from_github.png" alt="Download from GitHub" height="40"></a>
    &nbsp;
  </div>
</div>
<br>

# Opening the settings

Hold down the Twitter/X icon at the top of the main feed (the home timeline). The NeoFreeBird settings page opens.

There is no NeoFreeBird entry in Twitter's own Settings and privacy menu, in Privacy and safety, or in the iOS Settings app. If you cannot find the settings, you are most likely looking in the wrong place.

# Which build do I need?

| Build | Tweak | Branding and icons | For |
|---|---|---|---|
| `.ipa` (sideloaded) | yes | yes | AltStore, SideStore, Feather, Sideloadly |
| `.tipa` (TrollStore) | yes | yes | TrollStore |
| `.deb` | yes | no (intended) | Jailbroken devices |

DEB packages contain only the tweak, not the app, so they cannot change the app icon or name. This is intended behaviour for now. Use an IPA or TIPA build if you want the full NeoFreeBird branding.

Which DEB to install:
- `iphoneos-arm64`: rootless jailbreaks (palera1n default, Dopamine, and similar).
- `iphoneos-arm`: rootful jailbreaks (for example palera1n started with `-f`).

Installing the wrong one fails with an architecture error in Sileo.

# Troubleshooting

**I cannot find the NeoFreeBird settings.**
Hold down the Twitter/X icon at the top of the main feed. See [Opening the settings](#opening-the-settings).

**I installed the DEB and the app is unchanged.**
Check that you installed the package matching your jailbreak type (see above), respring, and fully close and reopen Twitter. Then open the settings by holding the icon in the feed. Note that the DEB does not include branding or icons.

**The tweak is `bhtwitter.dylib` in the package.**
That is expected. NeoFreeBird is built on BHTwitter and some internal file names keep the old name.

| | | | |
|:-------------------------:|:-------------------------:|:-------------------------:|:-------------------------:|
|<img width="1604" alt="Screenshot 1" src="resources/main/1.png">|<img width="1604" alt="Screenshot 2" src="resources/main/2.png">|<img width="1604" alt="Screenshot 3" src="resources/main/3.png">|<img width="1604" alt="Screenshot 4" src="resources/main/4.png">|

# Preview

| | | |
|:-------------------------:|:-------------------------:|:-------------------------:|
|<img width="1604" alt="Screenshot 1" src="resources/timeline/timeline1.png">|<img width="1604" alt="Screenshot 2" src="resources/timeline/timeline2.png">|<img width="1604" alt="Screenshot 3" src="resources/timeline/timeline3.png">|
|<img width="1604" alt="Screenshot 4" src="resources/timeline/timeline4.png">|<img width="1604" alt="Screenshot 5" src="resources/timeline/timeline5.png">|<img width="1604" alt="Screenshot 6" src="resources/timeline/timeline6.png">|

# Features
| | | |
|:-------------------------:|:-------------------------:|:-------------------------:|
|<img width="1604" alt="Screenshot 1" src="resources/settings/settings1.png">|<img width="1604" alt="Screenshot 2" src="resources/settings/settings2.png">|<img width="1604" alt="Screenshot 3" src="resources/settings/settings3.png">|
|<img width="1604" alt="Screenshot 4" src="resources/settings/settings4.png">|<img width="1604" alt="Screenshot 5" src="resources/settings/settings5.png">|<img width="1604" alt="Screenshot 6" src="resources/settings/settings6.png">|
|<img width="1604" alt="Screenshot 4" src="resources/settings/settings7.png">|<img width="1604" alt="Screenshot 5" src="resources/settings/settings8.png">|<img width="1604" alt="Screenshot 6" src="resources/settings/settings9.png">|
|<img width="1604" alt="Screenshot 4" src="resources/settings/settings10.png">|<img width="1604" alt="Screenshot 5" src="resources/settings/settings11.png">|<img width="1604" alt="Screenshot 6" src="resources/settings/settings12.png">|
|<img width="1604" alt="Screenshot 4" src="resources/settings/settings13.png">|<img width="1604" alt="Screenshot 5" src="resources/settings/settings14.png">|<img width="1604" alt="Screenshot 6" src="resources/settings/settings15.png">|

# Downloading
Go to the [Releases](https://github.com/NeoFreeBird/app/releases) page to download the latest version of NeoFreeBird. You can also build it yourself by following the instructions below.

# Supporting the Project

I welcome all help on NeoFreeBird! Translations, bug fixes, and new features are all welcome. If you do see any issues with the app, feel free to open an issue and follow the templates provided. I also have a Ko-Fi linked in the repo if you wish to support me directly, but by no means is it required! NeoFreeBird will always be open-source and free to use.

# Compiling NeoFreeBird

## Using your computer

1. Install [Theos](https://github.com/theos/theos).

> Note for Linux users: the current toolchain that ships with Theos is too outdated to build successfully ("Undefined symbols for architecture arm64"). Download the latest toolchain for your distro from [here](https://github.com/L1ghtmann/swift-toolchain-linux/releases/latest) and replace `$THEOS/toolchain/linux` with its contents.

2. Install [cyan](https://github.com/asdfzxcvbn/pyzule-rw) if you want sideload or TrollStore builds.
3. Clone the NeoFreeBird repository:

```bash
git clone --recursive https://github.com/NeoFreeBird/app
cd app
```

4. Make the build script executable:

```bash
chmod +x ./build.sh
```

5. Run the script with your preferred option:

```bash
./build.sh [OPTIONS]
```

Available options:
```
--sideloaded: for sideloading.
--trollstore: for TrollStore users.
--rootless: for rootless jailbreaks.
--rootfull: for rootful jailbreaks.
--help: for help
```

## Using GitHub Actions

1. Fork this repository.
2. Open the "Actions" tab and enable workflows.
3. Choose "Release".
4. Click "Run workflow" and provide:
   - A decrypted IPA URL for sideloaded/TrollStore builds.
   - Any value for rootful/rootless builds.
5. Check the "Releases" tab once the build completes.

# Examples

## Build for Sideloading

1. Get a decrypted IPA for Twitter/X.
2. Rename it to `com.atebits.Tweetie2.ipa` and move it to the `packages` folder.

```bash
./build.sh --sideloaded
```

Result: `NeoFreeBird-sideloaded.ipa` inside `packages`.

## Build for TrollStore

Follow the same steps as sideloading, then run:

```bash
./build.sh --trollstore
```

Result: `NeoFreeBird-trollstore.tipa` inside `packages`.

## Build for Rootless Jailbreaks

Just run:

```bash
./build.sh --rootless
```

Result: a rootless `.deb` (`iphoneos-arm64`) inside `packages`.

## Build for Rootful Jailbreaks

Just run:

```bash
./build.sh --rootfull
```

Result: a rootful `.deb` (`iphoneos-arm`) inside `packages`.

# Rebranding

`rebrand.sh` applies name and icon branding to an IPA. This can be done before or after patching with the tweak.

Resource packs work on both macOS and Linux via [scar](https://github.com/theacrat/scar), which rebuilds the app's asset catalogs, and [resvg](https://github.com/linebender/resvg), which rasterizes a pack's `svgs/` glyphs into them. Both are downloaded automatically if they aren't in `PATH` (or set `NFB_SCAR` / `NFB_RESVG` to a binary). The Pillow package they need is installed automatically into a cached venv on first use. There is a GitHub Actions workflow if you'd rather not run it locally.


```bash
./rebrand.sh [-t | --twitter-branding] [--resource-pack ZIP] [-o OUTPUT] IPA
```

At least one branding option is required:
```
-t, --twitter-branding: sets the app's display name to Twitter.
--resource-pack ZIP: applies a theme pack ZIP.
```

By default the IPA is rebranded in place. Pass `-o`/`--output` to write a rebranded copy instead:

```bash
./rebrand.sh -t --resource-pack theme.zip -o packages/Twitter-rebranded.ipa packages/NeoFreeBird-sideloaded.ipa
```
