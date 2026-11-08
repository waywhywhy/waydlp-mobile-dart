/// Parsing of yt-dlp `--dump-single-json --flat-playlist` output.
/// Only values yt-dlp reported are exposed; nothing is invented.
library;

import 'dart:convert';

int? _asInt(Object? v) => v is num && v >= 0 ? v.toInt() : null;
double? _asDouble(Object? v) => v is num && v >= 0 ? v.toDouble() : null;
String? _asString(Object? v) => v is String && v.isNotEmpty ? v : null;

String? codecFamily(String? codec) {
  if (codec == null || codec == 'none' || codec.isEmpty) return null;
  final c = codec.toLowerCase();
  if (c.startsWith('avc') || c.startsWith('h264')) return 'h264';
  if (c.startsWith('hev') || c.startsWith('hvc') || c.startsWith('h265')) return 'h265';
  if (c.startsWith('vp09') || c.startsWith('vp9')) return 'vp9';
  if (c.startsWith('av01') || c.startsWith('av1')) return 'av1';
  if (c.startsWith('mp4a') || c.startsWith('aac')) return 'aac';
  if (c.startsWith('opus')) return 'opus';
  if (c.startsWith('mp3')) return 'mp3';
  return 'other';
}

class FormatInfo {
  FormatInfo.fromJson(Map<String, Object?> j)
    : id = j['format_id']?.toString() ?? '?',
      ext = _asString(j['ext']),
      vcodec = _asString(j['vcodec']),
      acodec = _asString(j['acodec']),
      height = _asInt(j['height']),
      fps = _asDouble(j['fps']),
      abr = _asDouble(j['abr']) ?? _asDouble(j['tbr']),
      filesize = _asInt(j['filesize']),
      filesizeApprox = _asInt(j['filesize_approx']),
      note = _asString(j['format_note']),
      protocol = _asString(j['protocol']);

  final String id;
  final String? ext, vcodec, acodec, note, protocol;
  final int? height, filesize, filesizeApprox;
  final double? fps, abr;

  bool get isStoryboard => ext == 'mhtml' || protocol == 'mhtml' || note == 'storyboard';
  bool get hasVideo => !isStoryboard && ((vcodec != null && vcodec != 'none') || (vcodec == null && (height ?? 0) > 0));
  bool get hasAudio =>
      !isStoryboard && ((acodec != null && acodec != 'none') || (acodec == null && vcodec == null && height == null));
  bool get isAudioOnly => hasAudio && !hasVideo;
  bool get isVideoOnly => hasVideo && !hasAudio;
  int? get size => filesize ?? filesizeApprox;
}

class MediaInfo {
  MediaInfo.fromJson(Map<String, Object?> j)
    : id = j['id']?.toString() ?? '',
      title = _asString(j['title']),
      uploader = _asString(j['uploader']) ?? _asString(j['channel']),
      duration = _asDouble(j['duration']),
      webpageUrl = _asString(j['webpage_url']),
      extractor = _asString(j['extractor_key']),
      thumbnail = _asString(j['thumbnail']) ?? _bestThumb(j['thumbnails']),
      isLive = j['is_live'] == true || j['live_status'] == 'is_live',
      formats = ((j['formats'] as List<Object?>?) ?? const [])
          .whereType<Map<String, Object?>>()
          .map(FormatInfo.fromJson)
          .where((f) => !f.isStoryboard)
          .toList(),
      subtitles = ((j['subtitles'] as Map<String, Object?>?) ?? const {}).keys.where((k) => k != 'live_chat').toList()
        ..sort();

  static String? _bestThumb(Object? list) {
    if (list is! List) return null;
    String? best;
    var area = -1;
    for (final t in list.whereType<Map<String, Object?>>()) {
      final a = (_asInt(t['width']) ?? 0) * (_asInt(t['height']) ?? 0);
      final u = _asString(t['url']);
      if (u != null && a >= area) {
        best = u;
        area = a;
      }
    }
    return best;
  }

  final String id;
  final String? title, uploader, webpageUrl, extractor, thumbnail;
  final double? duration;
  final bool isLive;
  final List<FormatInfo> formats;
  final List<String> subtitles;

  String get displayTitle => title ?? id;

  bool get hasVideo => formats.any((f) => f.hasVideo) || formats.isEmpty;
  bool get hasAudio => formats.any((f) => f.hasAudio) || formats.isEmpty;

  /// Distinct real heights, highest first.
  List<int> get heights {
    final s = <int>{
      for (final f in formats)
        if (f.hasVideo && (f.height ?? 0) > 0) f.height!,
    };
    return s.toList()..sort((a, b) => b.compareTo(a));
  }

  Set<String> get videoCodecs => {
    for (final f in formats)
      if (f.hasVideo) ?codecFamily(f.vcodec),
  };

  double? get bestAudioKbps {
    double? best;
    for (final f in formats.where((f) => f.isAudioOnly)) {
      final a = f.abr;
      if (a != null && (best == null || a > best)) best = a;
    }
    return best;
  }
}

class PlaylistEntry {
  PlaylistEntry(this.index, Map<String, Object?> j)
    : id = _asString(j['id']),
      url = _asString(j['url']),
      title = _asString(j['title']),
      duration = _asDouble(j['duration']);

  final int index;
  final String? id, url, title;
  final double? duration;

  String get displayTitle => title ?? id ?? 'Item $index';
}

class PlaylistInfo {
  PlaylistInfo.fromJson(Map<String, Object?> j)
    : title = _asString(j['title']) ?? _asString(j['id']) ?? 'Playlist',
      uploader = _asString(j['uploader']) ?? _asString(j['channel']),
      entries = [
        for (final (i, e) in ((j['entries'] as List<Object?>?) ?? const []).indexed)
          if (e is Map<String, Object?>) PlaylistEntry(i + 1, e),
      ];

  final String title;
  final String? uploader;
  final List<PlaylistEntry> entries;
}

sealed class ProbeResult {}

class SingleResult extends ProbeResult {
  SingleResult(this.media);
  final MediaInfo media;
}

class PlaylistResult extends ProbeResult {
  PlaylistResult(this.playlist);
  final PlaylistInfo playlist;
}

ProbeResult parseProbeJson(String text) {
  final t = text.trim();
  if (t.isEmpty || t == 'null') throw const FormatException('yt-dlp returned no media information');
  final decoded = jsonDecode(t);
  if (decoded is! Map<String, Object?>) throw const FormatException('unexpected yt-dlp output');
  final type = decoded['_type'];
  if (type == 'playlist' || type == 'multi_video') return PlaylistResult(PlaylistInfo.fromJson(decoded));
  return SingleResult(MediaInfo.fromJson(decoded));
}

String resolutionLabel(int h) => switch (h) {
  >= 4320 => '${h}p (8K)',
  >= 2160 => '${h}p (4K)',
  >= 1440 => '${h}p (QHD)',
  >= 1080 => '${h}p (Full HD)',
  >= 720 => '${h}p (HD)',
  _ => '${h}p',
};
