# Project status (0.1.0, development)

## Verified

| Area | How |
|---|---|
| Dart logic: URL handling, yt-dlp argument builder, progress parsing, error classification and redaction, metadata parsing (real yt-dlp fixtures), settings and options serialisation | 23 unit tests (`flutter test`) |
| Widgets: theme, failure view, honest progress bar, empty state, logo | 4 widget tests |
| Static analysis | `flutter analyze`: no issues (Flutter 3.47.9 / Dart 3.13.7) |
| Android build | `flutter build apk --debug` with Flutter 3.47.9, AGP 9.1, JDK 17, SDK 36, NDK 28.2: Kotlin compiles and the APK is produced |
| APK contents | `aapt2 dump`: app ID `io.github.waywhywhy.waydlp`, min/target SDK 24/36, the expected permissions only, the `ACTION_SEND text/plain` share filter, the `DownloadService` (`dataSync`), the FileProvider, `extractNativeLibs=true`, and libpython/libffmpeg/libqjs for arm64-v8a, armeabi-v7a and x86_64 |

## Not yet verified

* Running on a device or emulator. This machine can't run the Android emulator, so none of these have been exercised: unpacking the runtime on first start, probing, downloading, the foreground service and notifications, MediaStore/SAF saving, share intents, and open/share/delete.
* Release signing (it needs your key; see `SIGNING.md`).

Please install the CI or debug APK on a real phone before publishing.

## Known limitations

* The Android 15+ daily time limit for `dataSync` foreground services applies to very long download sessions.
* Files created by a previous installation can't be deleted from the app (Android ownership rules).
* There are no per-download custom yt-dlp arguments or custom executable paths (desktop-only features).
* Queued jobs survive while the app process is alive. If Android kills the process, queued (not running) jobs are dropped; their history entries are marked interrupted.
* No release has been published.
