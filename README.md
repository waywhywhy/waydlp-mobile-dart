<h1 align="center">waydlp — Android</h1>

<p align="center"><b>Your media, your format, your way.</b><br>
A free, open-source media downloader for Android, powered by yt-dlp and FFmpeg running on your phone.</p>

---

* **A real downloader, not a web wrapper.** yt-dlp and FFmpeg run on the device through an embedded runtime, so no waydlp server is involved.
* Paste a link or use **Share → waydlp** from any app.
* The app shows the real title, thumbnail and qualities.
* Video comes as MP4/MKV/WebM or the original file. Audio comes as MP3, M4A, Opus, FLAC, WAV or OGG, with optional loudness normalisation.
* Playlists can be previewed and filtered item by item.
* The download queue shows real progress, with pause, resume, cancel and automatic retries.
* Downloads continue in the background, with a notification.
* Files are saved to **Download/waydlp** (MediaStore) or any folder you pick.
* History lets you search, open, share, download again or delete.
* AMOLED-black and purple design, the same as the desktop app. You can change the accent colour and reduce motion.
* No ads, no accounts, no tracking. **Android only, with no iOS version.**

> Only download media you have the right to access. waydlp does not circumvent DRM.

## Install

Download the signed **0.1.0** APKs from the [Releases page](https://github.com/waywhywhy/waydlp-mobile-dart/releases/tag/v0.1.0). Each release includes `SHA256SUMS.txt` for verification.

| File | For |
|---|---|
| `waydlp-<ver>-android-arm64.apk` | Almost all phones from recent years |
| `waydlp-<ver>-android-armv7.apk` | Older 32-bit phones |
| `waydlp-<ver>-android-x64.apk` | Emulators and x86 Chromebooks |
| `waydlp-<ver>-android-universal.apk` | Any device (larger) |

Android 7.0 (API 24) or newer is required.

### Obtainium

[Add waydlp to Obtainium](https://apps.obtainium.imranr.dev/redirect?r=obtainium://app/%7B%22id%22%3A%22io.github.waywhywhy.waydlp%22%2C%22url%22%3A%22https%3A%2F%2Fgithub.com%2Fwaywhywhy%2Fwaydlp-mobile-dart%22%2C%22author%22%3A%22waywhywhy%22%2C%22name%22%3A%22waydlp%22%2C%22additionalSettings%22%3A%22%7B%5C%22apkFilterRegEx%5C%22%3A%5C%22%5Ewaydlp-.%2A-android-universal%5B.%5Dapk%24%5C%22%2C%5C%22includePrereleases%5C%22%3Afalse%2C%5C%22autoApkFilterByArch%5C%22%3Afalse%2C%5C%22verifyLatestTag%5C%22%3Atrue%7D%22%7D) to install and track updates directly
from GitHub Releases. The configuration selects the universal APK for ARM64,
ARMv7 and x64 and follows stable releases. See the [Obtainium guide](docs/OBTAINIUM.md)
for manual setup or import [obtainium.json](obtainium.json) from Obtainium's Import/Export page.

## How it works

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). In short:

* **Dart/Flutter** handles the UI, the yt-dlp options (the same logic as the desktop app), progress parsing, error classification, settings and the SQLite history.
* **Kotlin** handles the rest:
  * running yt-dlp with [youtubedl-android](https://github.com/JunkFood02/youtubedl-android), an embedded Python, yt-dlp and FFmpeg;
  * a foreground download service;
  * saving to MediaStore or the Storage Access Framework;
  * share intents, notifications and opening/sharing files.

## Build

You need Flutter (stable), the Android SDK and JDK 17.

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --debug                       # installable debug build
flutter build apk --release --split-per-abi     # needs a release key, see docs/SIGNING.md
```

## License

GPL-3.0-or-later (required by youtubedl-android, which is GPL-3.0). See [LICENSE](LICENSE).
