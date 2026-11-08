/// Machine-readable yt-dlp progress (same templates as the desktop app).
library;

const dlPrefix = '[waydlp:dl]';
const ppPrefix = '[waydlp:pp]';
const itemPrefix = '[waydlp:item]';
const filePrefix = '[waydlp:file]';

const downloadTemplate =
    'download:[waydlp:dl]%(progress.status)s|%(progress.downloaded_bytes)s|%(progress.total_bytes)s|%(progress.total_bytes_estimate)s|%(progress.speed)s|%(progress.eta)s|%(progress.fragment_index)s|%(progress.fragment_count)s|%(info.vcodec)s|%(info.acodec)s';
const postprocessTemplate = 'postprocess:[waydlp:pp]%(progress.status)s|%(progress.postprocessor)s';
const itemPrint = 'video:[waydlp:item]%(playlist_index|NA)s|%(n_entries|NA)s|%(id|NA)s|%(title|NA)s';
const filePrint = 'after_move:[waydlp:file]%(filepath)s';

String? _na(String? s) {
  final t = s?.trim();
  if (t == null || t.isEmpty || t == 'NA' || t == 'None') return null;
  return t;
}

int? _int(String? s) {
  final v = double.tryParse(_na(s) ?? '');
  return (v == null || v.isNaN || v < 0) ? null : v.toInt();
}

double? _dbl(String? s) {
  final v = double.tryParse(_na(s) ?? '');
  return (v == null || v.isNaN || v < 0) ? null : v;
}

enum StreamKind { video, audio, combined, unknown }

class DownloadProgress {
  const DownloadProgress({
    required this.status,
    this.downloaded,
    this.total,
    this.totalIsEstimate = false,
    this.speed,
    this.eta,
    this.fragment,
    this.fragmentCount,
    this.stream = StreamKind.unknown,
  });

  final String status;
  final int? downloaded;
  final int? total;
  final bool totalIsEstimate;
  final double? speed;
  final int? eta;
  final int? fragment;
  final int? fragmentCount;
  final StreamKind stream;

  double? get fraction {
    if (status == 'finished') return 1;
    final d = downloaded, t = total;
    if (d != null && t != null && t > 0) return (d / t).clamp(0, 1).toDouble();
    final f = fragment, n = fragmentCount;
    if (f != null && n != null && n > 0) return (f / n).clamp(0, 1).toDouble();
    return null;
  }

  String get streamLabel => switch (stream) {
    StreamKind.video => 'Downloading video stream',
    StreamKind.audio => 'Downloading audio stream',
    _ => 'Downloading',
  };
}

sealed class ProgressEvent {
  const ProgressEvent();
}

class DownloadEvent extends ProgressEvent {
  const DownloadEvent(this.progress);
  final DownloadProgress progress;
}

class PostProcessEvent extends ProgressEvent {
  const PostProcessEvent(this.status, this.processor);
  final String status;
  final String processor;
}

class ItemEvent extends ProgressEvent {
  const ItemEvent({this.index, this.count, this.id, this.title});
  final int? index;
  final int? count;
  final String? id;
  final String? title;
}

class FileEvent extends ProgressEvent {
  const FileEvent(this.path);
  final String path;
}

class WarningEvent extends ProgressEvent {
  const WarningEvent(this.message);
  final String message;
}

class LogEvent extends ProgressEvent {
  const LogEvent(this.line);
  final String line;
}

ProgressEvent parseLine(String raw) {
  final line = raw.replaceAll(RegExp(r'[\r\n]+$'), '');
  if (line.startsWith(dlPrefix)) {
    final p = line.substring(dlPrefix.length).split('|');
    String? g(int i) => i < p.length ? p[i] : null;
    bool has(String? c) => c != null && c != 'none' && c != 'NA';
    final v = has(g(8)), au = has(g(9));
    final exact = _int(g(2));
    final est = _int(g(3));
    return DownloadEvent(
      DownloadProgress(
        status: _na(g(0)) ?? 'downloading',
        downloaded: _int(g(1)),
        total: exact ?? est,
        totalIsEstimate: exact == null && est != null,
        speed: _dbl(g(4)),
        eta: _int(g(5)),
        fragment: _int(g(6)),
        fragmentCount: _int(g(7)),
        stream: v && au
            ? StreamKind.combined
            : v
            ? StreamKind.video
            : au
            ? StreamKind.audio
            : StreamKind.unknown,
      ),
    );
  }
  if (line.startsWith(ppPrefix)) {
    final rest = line.substring(ppPrefix.length);
    final i = rest.indexOf('|');
    return i < 0 ? PostProcessEvent(rest, '') : PostProcessEvent(rest.substring(0, i), rest.substring(i + 1));
  }
  if (line.startsWith(itemPrefix)) {
    final parts = line.substring(itemPrefix.length).split('|');
    final title = parts.length > 3 ? parts.sublist(3).join('|') : null;
    return ItemEvent(
      index: _int(parts.isNotEmpty ? parts[0] : null),
      count: _int(parts.length > 1 ? parts[1] : null),
      id: _na(parts.length > 2 ? parts[2] : null),
      title: _na(title),
    );
  }
  if (line.startsWith(filePrefix)) return FileEvent(line.substring(filePrefix.length).trim());
  if (line.startsWith('WARNING:')) return WarningEvent(line.substring(8).trim());
  return LogEvent(line);
}

String postprocessorLabel(String name) => switch (name.trim()) {
  'Merger' || 'FFmpegMerger' => 'Merging video and audio',
  'ExtractAudio' || 'FFmpegExtractAudio' => 'Converting audio',
  'VideoRemuxer' || 'FFmpegVideoRemuxer' => 'Remuxing (no quality loss)',
  'VideoConvertor' || 'FFmpegVideoConvertor' => 'Re-encoding video',
  'EmbedThumbnail' => 'Embedding thumbnail',
  'Metadata' || 'FFmpegMetadata' => 'Writing metadata',
  'EmbedSubtitle' || 'FFmpegEmbedSubtitle' => 'Embedding subtitles',
  'MoveFiles' || 'MoveFilesAfterDownload' => 'Moving into place',
  final other => 'Processing ($other)',
};

String formatBytes(int n) {
  if (n < 1024) return '$n B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var v = n / 1024;
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return v >= 100 ? '${v.toStringAsFixed(0)} ${units[i]}' : '${v.toStringAsFixed(1)} ${units[i]}';
}

String formatDuration(num secs) {
  final s = secs.round();
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, r = s % 60;
  String two(int x) => x.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(r)}' : '$m:${two(r)}';
}

String formatEta(int secs) {
  final h = secs ~/ 3600, m = (secs % 3600) ~/ 60, s = secs % 60;
  if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
  if (m > 0) return '${m}m ${s.toString().padLeft(2, '0')}s';
  return '${s}s';
}

/// "12.3 MB of ~45 MB · 2.1 MB/s · 15s left" — only values yt-dlp reported.
String progressText(DownloadProgress p) {
  final parts = <String>[];
  final d = p.downloaded, t = p.total;
  if (d != null && t != null) {
    parts.add('${formatBytes(d)} of ${p.totalIsEstimate ? '~' : ''}${formatBytes(t)}');
  } else if (d != null) {
    parts.add(formatBytes(d));
  }
  final sp = p.speed;
  if (sp != null && sp > 0) parts.add('${formatBytes(sp.toInt())}/s');
  final e = p.eta;
  if (e != null && p.status == 'downloading') parts.add('${formatEta(e)} left');
  return parts.join(' · ');
}
