/// yt-dlp argument generation (port of waydlp-core's args.rs).
///
/// The list is passed as argv to the embedded yt-dlp: no shell is involved.
/// The native side appends the URL after the trailing `--`, and adds
/// `--ffmpeg-location` for the embedded FFmpeg.
library;

import '../models/options.dart';
import 'progress.dart' as progress;

class ArgsError implements Exception {
  const ArgsError(this.message);
  final String message;
  @override
  String toString() => message;
}

const defaultTemplate = '%(title).150B [%(id)s].%(ext)s';

void validateTemplate(String t) {
  final s = t.trim();
  if (s.isEmpty) throw const ArgsError('The filename template is empty.');
  if (s.startsWith('/') || s.startsWith('\\') || s.startsWith('~')) {
    throw const ArgsError('The filename template must be relative to the download folder.');
  }
  if (s.split(RegExp(r'[/\\]')).any((c) => c.trim() == '..')) {
    throw const ArgsError('The filename template may not contain ".." folders.');
  }
  if (s.endsWith('/') || s.endsWith('\\')) {
    throw const ArgsError('The filename template must include a file name.');
  }
}

final _formatId = RegExp(r'^[A-Za-z0-9._-]{1,64}$');
final _items = RegExp(r'^[0-9,:\- ]+$');
final _lang = RegExp(r'^[A-Za-z0-9._*!-]{1,32}$');

/// Network options from settings.
class NetworkOptions {
  const NetworkOptions({this.retries = 10, this.rateLimit});
  final int retries;
  final String? rateLimit;
}

List<String> _base(NetworkOptions net) {
  final a = <String>['--ignore-config', '--color', 'never'];
  final r = net.rateLimit?.trim();
  if (r != null && r.isNotEmpty) {
    if (!RegExp(r'^\d+(\.\d+)?[KMGkmg]?$').hasMatch(r)) {
      throw ArgsError('Invalid speed limit "$r". Use e.g. 2M or 500K.');
    }
    a.addAll(['--limit-rate', r]);
  }
  a.addAll(['--retries', '${net.retries}', '--fragment-retries', '${net.retries}', '--socket-timeout', '30']);
  return a;
}

/// Arguments for `yt-dlp -J --flat-playlist`.
List<String> buildProbeArgs({required bool noPlaylist, NetworkOptions net = const NetworkOptions()}) {
  return [
    ..._base(net),
    '--dump-single-json',
    '--flat-playlist',
    '--no-warnings',
    if (noPlaylist) '--no-playlist',
    '--',
  ];
}

List<String> buildDownloadArgs({
  required DownloadOptions o,
  required String outputDir,
  required String tempDir,
  required bool isPlaylist,
  String template = defaultTemplate,
  NetworkOptions net = const NetworkOptions(),
}) {
  final a = <String>[
    ..._base(net),
    '--newline',
    '--progress',
    '--no-simulate',
    '--progress-template',
    progress.downloadTemplate,
    '--progress-template',
    progress.postprocessTemplate,
    '--print',
    progress.itemPrint,
    '--print',
    progress.filePrint,
    '--paths',
    'home:$outputDir',
    '--paths',
    'temp:$tempDir',
    // Android file systems (FAT/exFAT SD cards, MediaStore) dislike some characters.
    '--windows-filenames',
  ];

  validateTemplate(template);
  var t = template.trim();
  if (isPlaylist) {
    if (o.numberFiles) {
      final i = t.lastIndexOf('/');
      t = i >= 0 ? '${t.substring(0, i + 1)}%(playlist_index)03d - ${t.substring(i + 1)}' : '%(playlist_index)03d - $t';
    }
    if (o.playlistFolder) t = '%(playlist_title,playlist_id|Playlist)s/$t';
  }
  a.addAll(['--output', t]);

  if (isPlaylist) {
    a.add('--yes-playlist');
    final items = o.playlistItems?.trim();
    if (items != null && items.isNotEmpty) {
      if (!_items.hasMatch(items)) throw ArgsError('Invalid playlist selection "$items".');
      a.addAll(['--playlist-items', items.replaceAll(' ', '')]);
    }
  } else {
    a.add('--no-playlist');
  }
  a.add('--no-overwrites');

  final fid = o.formatId;
  if (fid != null && !_formatId.hasMatch(fid)) throw ArgsError('Invalid format id "$fid".');

  switch (o.mode) {
    case DownloadMode.original:
      a.addAll(['--format', fid ?? 'b/bv*+ba']);
    case DownloadMode.audioOnly:
      a.addAll(['--format', fid != null ? '$fid/ba/b' : 'ba/b']);
      final tok = o.audioFormat.preferredSource;
      if (tok != null) a.addAll(['--format-sort', tok]);
      a.add('--extract-audio');
      final name = o.audioFormat.ytDlpName;
      if (name != null) a.addAll(['--audio-format', name]);
      if (!o.audioFormat.isLossless) a.addAll(['--audio-quality', o.audioQuality.ytDlpValue]);
      if (o.normalize) {
        if (o.audioFormat == AudioFormat.original) {
          throw const ArgsError('Loudness normalisation needs an output format other than Original.');
        }
        a.addAll(['--postprocessor-args', 'ExtractAudio:-af loudnorm=I=-16:TP=-1.5:LRA=11']);
      }
    case DownloadMode.videoAndAudio:
    case DownloadMode.videoOnly:
      final withAudio = o.mode == DownloadMode.videoAndAudio;
      final h = o.maxHeight != null ? '[height<=${o.maxHeight}]' : '';
      final String f;
      if (fid != null) {
        f = withAudio && o.formatIsVideoOnly ? '$fid+ba/$fid' : fid;
      } else if (withAudio) {
        f = h.isEmpty ? 'bv*+ba/b' : 'bv*$h+ba/b$h/bv*+ba/b';
      } else {
        f = h.isEmpty ? 'bv/bv*' : 'bv$h/bv/bv*';
      }
      a.addAll(['--format', f]);
      final sort = <String>[
        if (o.maxHeight != null) 'res:${o.maxHeight}',
        if (o.codec.sortToken != null) o.codec.sortToken!,
        if (o.container == MediaContainer.mp4) 'ext:mp4:m4a',
        if (o.container == MediaContainer.webm) 'ext:webm:webm',
      ];
      if (sort.isNotEmpty) a.addAll(['--format-sort', sort.join(',')]);
      final ext = o.container.ext;
      if (ext != null) {
        if (withAudio) a.addAll(['--merge-output-format', ext]);
        a.addAll([o.allowRecode ? '--recode-video' : '--remux-video', ext]);
      }
  }

  if (o.mode != DownloadMode.original) {
    if (o.embedMetadata) a.add('--embed-metadata');
    final thumbOk = o.mode == DownloadMode.audioOnly
        ? o.audioFormat.supportsCoverArt
        : (o.container.supportsThumbnail || o.container == MediaContainer.original);
    if (o.embedThumbnail && thumbOk) a.add('--embed-thumbnail');
    if (o.embedChapters && o.mode != DownloadMode.audioOnly) a.add('--embed-chapters');
  }

  if (o.subtitles && o.mode != DownloadMode.audioOnly) {
    final langs = o.subtitleLanguages.map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    for (final l in langs) {
      if (!_lang.hasMatch(l)) throw ArgsError('Invalid subtitle language "$l".');
    }
    a.addAll(['--write-subs', '--sub-langs', langs.isEmpty ? 'en' : langs.join(',')]);
    if (o.embedSubtitles && o.container.supportsSubs) a.add('--embed-subs');
  }

  a.add('--');
  return a;
}

/// Compress sorted 1-based indices into a `--playlist-items` spec.
String itemsSpec(List<int> indices) {
  final out = <String>[];
  var i = 0;
  while (i < indices.length) {
    final start = indices[i];
    var end = start;
    while (i + 1 < indices.length && indices[i + 1] == end + 1) {
      i++;
      end = indices[i];
    }
    out.add(start == end ? '$start' : '$start-$end');
    i++;
  }
  return out.join(',');
}
