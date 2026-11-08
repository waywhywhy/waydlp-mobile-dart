# Project status (0.1.0)

## Verified

| Area | How |
|---|---|
| Dart logic: URL handling, yt-dlp argument builder, progress parsing, error classification and redaction, metadata parsing (real yt-dlp fixtures), settings and options serialisation | 23 unit tests (`flutter test`) |
| Widgets: theme, failure view, honest progress bar, empty state, logo | 4 widget tests |
| Static analysis | `flutter analyze`: no issues (Flutter 3.47.9 / Dart 3.13.7) |
| Android build | `flutter build apk --debug` with Flutter 3.47.9, AGP 9.1, JDK 17, SDK 36, NDK 28.2: Kotlin compiles and the APK is produced |
| APK contents | `aapt2 dump`: app ID `io.github.waywhywhy.waydlp`, min/target SDK 24/36, the expected permissions only, the `ACTION_SEND text/plain` share filter, the `DownloadService` (`dataSync`), the FileProvider, `extractNativeLibs=true`, and libpython/libffmpeg/libqjs for arm64-v8a, armeabi-v7a and x86_64 |
| Android 15 emulator (API 35, x86_64), 2026-11-08 | `flutter test integration_test/download_test.dart -d emulator-5554`: passed in 19 seconds. Real embedded runtime startup, probing, original WAV download, FFmpeg MP3 conversion, foreground service execution, MediaStore save/existence/delete, SQLite history and Home/Queue/History/Settings navigation |
| Release signing setup | Persistent RSA-4096 key generated; four repository signing secrets configured. The release workflow verifies APK signatures before publication |

## Not yet verified

* Physical phones, other Android versions and ARM ABIs have not been exercised end to end.
* Notifications, long background sessions, SAF folder selection, incoming share intents and opening/sharing downloaded files still need separate device checks.

The emulator smoke test is a required release check. Physical-device coverage remains a limitation of this first release.

## Known limitations

* The Android 15+ daily time limit for `dataSync` foreground services applies to very long download sessions.
* Files created by a previous installation can't be deleted from the app (Android ownership rules).
* There are no per-download custom yt-dlp arguments or custom executable paths (desktop-only features).
* Queued jobs survive while the app process is alive. If Android kills the process, queued (not running) jobs are dropped; their history entries are marked interrupted.
* Signed 0.1.0 APKs and an App Bundle are published on GitHub Releases. Required CI, including the real Android emulator smoke test, passed. The published x64 APK's checksum and signing certificate were independently verified after download.
