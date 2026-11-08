# Contributing to waydlp for Android

General guidelines are in the [organisation contributing guide](https://github.com/waywhywhy/.github/blob/main/CONTRIBUTING.md).

* Set up Flutter (stable), the Android SDK and JDK 17. Run `flutter pub get`.
* Before a pull request, run `dart format --line-length 120 lib test`, `flutter analyze` and `flutter test`, and test on a real device or emulator.
* Keep yt-dlp argument logic in `lib/services/args.dart` consistent with the desktop crate `waydlp-core`.
* Never pass user input through a shell. Validate everything user-controlled.
* Ask only for permissions that are strictly needed, and explain them in `docs/ARCHITECTURE.md`.
* Don't commit signing keys or passwords.

## Windows build note

If the Flutter SDK and this project are on different drives, Kotlin's incremental compiler fails with "Could not close incremental caches". Add `kotlin.incremental=false` to `%USERPROFILE%\.gradle\gradle.properties`, or keep both on the same drive.

`androidx.core` is pinned to 1.18.0 because 1.19+ needs compile SDK 37, which the current Flutter/AGP doesn't support yet.
