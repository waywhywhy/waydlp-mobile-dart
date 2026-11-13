# Changelog

All notable changes to waydlp for Android. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow [SemVer](https://semver.org/).

## [Unreleased]

## [0.2.0] - 2026-11-13

### Added
- Automatic yt-dlp updates (Settings › yt-dlp, on by default): at most once a day, and once more when a download fails because yt-dlp is outdated, after which the download is retried. Respects Wi-Fi only.
- Home shows a warning with an Update button when yt-dlp is more than 90 days old.
- Queue menu: Pause all, Resume all and Retry failed.
- "Retry now" and "Cancel" for downloads waiting for an automatic retry.

### Fixed
- Downloads that finished after leaving the app with Back were recorded as "Cancelled – Interrupted" in history; they now show the real result, file and title.
- Links shared to waydlp after leaving it with Back were ignored.
- Reopening the app while a download was still running marked it "Interrupted".
- The yt-dlp version showed as "unknown" / "not ready" on fresh installs and didn't refresh after updating.
- HTTP 403 errors from an outdated yt-dlp are reported as "yt-dlp may be out of date" instead of a generic failure and are no longer retried pointlessly.
- Punctuation around shared links, such as `(https://youtu.be/…).`, is no longer part of the link.
- Partial files of paused, cancelled, removed or failed downloads are deleted instead of being kept forever.
- Possible crash when a download ended immediately (Android 12+ foreground-service timing).
- On Android 15's background time limit, running downloads are paused (resumable) with a notification instead of being left unprotected.
- A Cancel pressed just as a download started could be ignored.
- "Reset settings to defaults" now also resets the save folder; the file name template and speed limit fields save when you leave them, reject invalid values and show resets.
- Choosing a folder that can't be used for saving no longer crashes the app.
- Double taps no longer queue a download twice; History updates only after its database writes complete.

## [0.1.0] - 2026-11-05

First development version (not released).

### Added
- Flutter app with Home, Analyze, Queue, History and Settings/About; AMOLED-black and purple theme.
- On-device yt-dlp and FFmpeg via youtubedl-android; real metadata, playlist selection, video and audio options.
- Foreground download service with notifications, pause/resume/cancel, automatic retries.
- Saving to Download/waydlp (MediaStore) or a chosen folder (SAF); share intents; open/share/delete files.
- SQLite history, settings with schema versioning, yt-dlp updater.
