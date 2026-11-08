# waydlp for Android — architecture

## Choosing the extraction engine

Options that were evaluated:

| Option | Verdict |
|---|---|
| Run the desktop `yt-dlp_linux` binary | **No.** It's built for glibc Linux, not Android's Bionic libc, and Android forbids executing files from writable app storage on API 29+ unless they ship as native libraries. |
| Re-implement extractors in Dart | **No.** It would be a huge, permanently outdated copy of yt-dlp. |
| A remote download server | **No.** It costs money, collects user data, invites abuse, and the spec requires local downloads. |
| Chaquopy (Python in Gradle) | Viable, but it needs a commercial licence for some uses, and we'd have to package FFmpeg ourselves. |
| **youtubedl-android** (JunkFood02 fork, used by Seal and others) | **Chosen.** It's maintained and ships a Python runtime, yt-dlp, FFmpeg and QuickJS as native libraries. It can update yt-dlp in place and is GPL-3.0, which is compatible with waydlp's license. |

The library runs `python yt-dlp …` as a child process. Its native libraries must be extracted to disk, so the app sets `extractNativeLibs=true` / `useLegacyPackaging`.

## Layers

```
Flutter (Dart)                                   Android (Kotlin)
──────────────────────────────────────────────   ───────────────────────────────────────────
screens/      Home, Analyze, Queue, History,      MainActivity   method + event channels,
              Settings (+About)                                  share intents, SAF picker,
services/args.dart     yt-dlp argv (same rules                   open/share/delete, permissions
                       as the desktop core)       DownloadEngine job queue (concurrency limit),
services/progress.dart parse [waydlp:*] lines                    runs yt-dlp, forwards lines
services/errors.dart   readable failures         DownloadService foreground service + notifications
services/downloads.dart queue state, retries,     Saver          MediaStore Download/waydlp,
                        history recording                        SAF folder, legacy Download
services/history_store.dart  sqflite
services/settings_store.dart shared_preferences
```

### A download, step by step

1. Dart builds the argument list. This is a port of `waydlp-core::args`, with the same progress templates. The list ends with `--`, and the URL is appended natively.
2. `enqueue` hands the job to `DownloadEngine`. The engine starts `DownloadService` in the foreground (type `dataSync`) and runs jobs up to the concurrency limit.
3. Every yt-dlp stdout line is sent to Dart over the event channel. Dart parses real progress (bytes, speed, ETA, post-processing stage) from it. The notification shows a percentage parsed from the same lines.
4. When yt-dlp finishes, the files it reported via `--print after_move:` are copied:
   * to **Download/waydlp** through MediaStore (Android 10+),
   * or into the folder the user picked (Storage Access Framework),
   * or into the public Download folder on Android 7–9.
   The private copy is then deleted. Dart records the `content://` URIs in history.
5. **Pause** stops the process tree but keeps the job's temp folder, so yt-dlp resumes its `.part` files. **Cancel** deletes the folder.
6. If the UI has gone away (activity destroyed), results are stored in SharedPreferences. They are applied to history on the next start, before rows still marked "in progress" are marked interrupted.

## Permissions

| Permission | Why |
|---|---|
| `INTERNET`, `ACCESS_NETWORK_STATE` | Downloading; the Wi-Fi-only setting |
| `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_DATA_SYNC` | Keep downloads running in the background with a visible notification |
| `POST_NOTIFICATIONS` (Android 13+) | Progress and completion notifications. Asked for when needed, and optional. |
| `WRITE_EXTERNAL_STORAGE` (max API 28) | Android 7–9 only: save into the public Download folder |

No storage permission is needed on Android 10+. MediaStore and SAF handle it.

## Known limitations

* **Not yet run on a device:** the APK builds and its manifest/libraries were checked, but it hasn't been run on a device or emulator yet.
* **Android 15+ time limit:** Android 15+ limits `dataSync` foreground services to about 6 hours per day. Longer sessions stop gracefully and can be resumed.
* **First start:** the embedded runtime (~100 MB) is unpacked on first start, which takes a few seconds.
* **Deleting old files:** files created by a previous installation can't be deleted by waydlp (Android ownership rules). The app says so.
* **Desktop-only options:** custom executable paths and extra yt-dlp arguments are desktop-only.
