# Obtainium

[Add waydlp to Obtainium](https://apps.obtainium.imranr.dev/redirect?r=obtainium://app/%7B%22id%22%3A%22io.github.waywhywhy.waydlp%22%2C%22url%22%3A%22https%3A%2F%2Fgithub.com%2Fwaywhywhy%2Fwaydlp-mobile-dart%22%2C%22author%22%3A%22waywhywhy%22%2C%22name%22%3A%22waydlp%22%2C%22additionalSettings%22%3A%22%7B%5C%22apkFilterRegEx%5C%22%3A%5C%22%5Ewaydlp-.%2A-android-universal%5B.%5Dapk%24%5C%22%2C%5C%22includePrereleases%5C%22%3Afalse%2C%5C%22autoApkFilterByArch%5C%22%3Afalse%2C%5C%22verifyLatestTag%5C%22%3Atrue%7D%22%7D).

Install [Obtainium](https://obtainium.imranr.dev/) on your Android device, open the
link above, confirm the configuration import, then check for updates and install
waydlp. Allow Obtainium to install apps when Android requests it.

The configuration follows the latest stable release from the official Android
repository and selects only `waydlp-<version>-android-universal.apk`. The universal
APK supports ARM64, ARMv7 and x64; it is larger than an architecture-specific APK.
Pre-releases are excluded. Existing GitHub release installations use the same app
ID and signing key, so Obtainium can manage their updates without reinstalling.

## Manual setup

In Obtainium, add this source:

```text
https://github.com/waywhywhy/waydlp-mobile-dart
```

Set **Filter APKs by Regular Expression** to:

```regex
^waydlp-.*-android-universal[.]apk$
```

Leave **Include pre-releases** off and enable **Verify latest tag**. Alternatively,
download [obtainium.json](../obtainium.json) and use Obtainium's Import/Export page
to import the file. It contains only waydlp's configuration and no global settings.

Update checks, notifications and background installation follow your Obtainium
settings and Android permissions. This is independent of updating yt-dlp inside
waydlp's settings.

## Maintaining releases

- Keep the Android application ID and release signing key unchanged.
- Increase both the version and the `+build` number in `pubspec.yaml` for each release.
  Android requires an increasing version code to accept updates.
- Keep publishing one signed `waydlp-<version>-android-universal.apk` per release.
  CI validates the selector before publication and checks the version code against
  the previous published release.
- After editing `obtainium.json`, run `python tool/check_obtainium.py --print-link`
  and update the import links in the README, this guide, website and organization
  profile. The website's `src/lib/obtainium.json` mirrors this configuration.

Configuration format: [official Obtainium deep-link documentation](https://wiki.obtainium.imranr.dev/deep_links/).
