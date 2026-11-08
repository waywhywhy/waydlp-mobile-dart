/// Download options and presets (same model as the desktop app).
library;

enum DownloadMode {
  videoAndAudio('Video'),
  audioOnly('Audio'),
  videoOnly('Video only'),
  original('Original file');

  const DownloadMode(this.label);
  final String label;
}

enum MediaContainer {
  mp4('MP4', 'mp4'),
  mkv('MKV', 'mkv'),
  webm('WebM', 'webm'),
  original('Original', null);

  const MediaContainer(this.label, this.ext);
  final String label;
  final String? ext;

  bool get supportsThumbnail => this == mp4 || this == mkv;
  bool get supportsSubs => this != original;
}

enum CodecPreference {
  any('Automatic', null, null),
  h264('H.264 (most compatible)', 'vcodec:h264', 'h264'),
  h265('H.265 / HEVC', 'vcodec:h265', 'h265'),
  vp9('VP9', 'vcodec:vp9', 'vp9'),
  av1('AV1 (smallest files)', 'vcodec:av01', 'av1');

  const CodecPreference(this.label, this.sortToken, this.family);
  final String label;
  final String? sortToken;
  final String? family;
}

enum AudioFormat {
  mp3('MP3', 'mp3'),
  m4a('M4A (AAC)', 'm4a'),
  opus('Opus', 'opus'),
  flac('FLAC', 'flac'),
  wav('WAV', 'wav'),
  ogg('OGG (Vorbis)', 'vorbis'),
  original('Original (no conversion)', null);

  const AudioFormat(this.label, this.ytDlpName);
  final String label;
  final String? ytDlpName;

  bool get isLossless => this == flac || this == wav;
  bool get supportsCoverArt => this != wav;
  String? get preferredSource => switch (this) {
    m4a => 'acodec:aac',
    opus => 'acodec:opus',
    mp3 => 'acodec:mp3',
    _ => null,
  };
}

/// Audio quality: 0 = best VBR, otherwise a kbps target.
class AudioQuality {
  const AudioQuality(this.kbps);
  final int kbps;
  static const best = AudioQuality(0);
  static const choices = [best, AudioQuality(320), AudioQuality(256), AudioQuality(192), AudioQuality(128)];

  String get label => kbps == 0 ? 'Best (highest-quality VBR)' : '$kbps kbps target';
  String get ytDlpValue => kbps == 0 ? '0' : '${kbps}K';

  @override
  bool operator ==(Object other) => other is AudioQuality && other.kbps == kbps;
  @override
  int get hashCode => kbps.hashCode;
}

T _enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

class DownloadOptions {
  const DownloadOptions({
    this.mode = DownloadMode.videoAndAudio,
    this.container = MediaContainer.mp4,
    this.maxHeight,
    this.codec = CodecPreference.any,
    this.allowRecode = false,
    this.audioFormat = AudioFormat.original,
    this.audioQuality = AudioQuality.best,
    this.normalize = false,
    this.embedMetadata = true,
    this.embedThumbnail = true,
    this.embedChapters = true,
    this.subtitles = false,
    this.subtitleLanguages = const ['en'],
    this.embedSubtitles = true,
    this.formatId,
    this.formatIsVideoOnly = false,
    this.playlistItems,
    this.numberFiles = true,
    this.playlistFolder = true,
  });

  final DownloadMode mode;
  final MediaContainer container;
  final int? maxHeight;
  final CodecPreference codec;
  final bool allowRecode;
  final AudioFormat audioFormat;
  final AudioQuality audioQuality;
  final bool normalize;
  final bool embedMetadata;
  final bool embedThumbnail;
  final bool embedChapters;
  final bool subtitles;
  final List<String> subtitleLanguages;
  final bool embedSubtitles;
  final String? formatId;
  final bool formatIsVideoOnly;
  final String? playlistItems;
  final bool numberFiles;
  final bool playlistFolder;

  DownloadOptions copyWith({
    DownloadMode? mode,
    MediaContainer? container,
    int? Function()? maxHeight,
    CodecPreference? codec,
    bool? allowRecode,
    AudioFormat? audioFormat,
    AudioQuality? audioQuality,
    bool? normalize,
    bool? embedMetadata,
    bool? embedThumbnail,
    bool? embedChapters,
    bool? subtitles,
    List<String>? subtitleLanguages,
    bool? embedSubtitles,
    String? Function()? formatId,
    bool? formatIsVideoOnly,
    String? Function()? playlistItems,
    bool? numberFiles,
    bool? playlistFolder,
  }) {
    return DownloadOptions(
      mode: mode ?? this.mode,
      container: container ?? this.container,
      maxHeight: maxHeight != null ? maxHeight() : this.maxHeight,
      codec: codec ?? this.codec,
      allowRecode: allowRecode ?? this.allowRecode,
      audioFormat: audioFormat ?? this.audioFormat,
      audioQuality: audioQuality ?? this.audioQuality,
      normalize: normalize ?? this.normalize,
      embedMetadata: embedMetadata ?? this.embedMetadata,
      embedThumbnail: embedThumbnail ?? this.embedThumbnail,
      embedChapters: embedChapters ?? this.embedChapters,
      subtitles: subtitles ?? this.subtitles,
      subtitleLanguages: subtitleLanguages ?? this.subtitleLanguages,
      embedSubtitles: embedSubtitles ?? this.embedSubtitles,
      formatId: formatId != null ? formatId() : this.formatId,
      formatIsVideoOnly: formatIsVideoOnly ?? this.formatIsVideoOnly,
      playlistItems: playlistItems != null ? playlistItems() : this.playlistItems,
      numberFiles: numberFiles ?? this.numberFiles,
      playlistFolder: playlistFolder ?? this.playlistFolder,
    );
  }

  Map<String, Object?> toJson() => {
    'mode': mode.name,
    'container': container.name,
    'maxHeight': maxHeight,
    'codec': codec.name,
    'allowRecode': allowRecode,
    'audioFormat': audioFormat.name,
    'audioKbps': audioQuality.kbps,
    'normalize': normalize,
    'embedMetadata': embedMetadata,
    'embedThumbnail': embedThumbnail,
    'embedChapters': embedChapters,
    'subtitles': subtitles,
    'subtitleLanguages': subtitleLanguages,
    'embedSubtitles': embedSubtitles,
    'numberFiles': numberFiles,
    'playlistFolder': playlistFolder,
  };

  factory DownloadOptions.fromJson(Map<String, Object?> j) => DownloadOptions(
    mode: _enumByName(DownloadMode.values, j['mode'], DownloadMode.videoAndAudio),
    container: _enumByName(MediaContainer.values, j['container'], MediaContainer.mp4),
    maxHeight: (j['maxHeight'] as num?)?.toInt(),
    codec: _enumByName(CodecPreference.values, j['codec'], CodecPreference.any),
    allowRecode: j['allowRecode'] == true,
    audioFormat: _enumByName(AudioFormat.values, j['audioFormat'], AudioFormat.original),
    audioQuality: AudioQuality((j['audioKbps'] as num?)?.toInt() ?? 0),
    normalize: j['normalize'] == true,
    embedMetadata: j['embedMetadata'] != false,
    embedThumbnail: j['embedThumbnail'] != false,
    embedChapters: j['embedChapters'] != false,
    subtitles: j['subtitles'] == true,
    subtitleLanguages: (j['subtitleLanguages'] as List<Object?>?)?.whereType<String>().toList() ?? const ['en'],
    embedSubtitles: j['embedSubtitles'] != false,
    numberFiles: j['numberFiles'] != false,
    playlistFolder: j['playlistFolder'] != false,
  );

  /// Short description such as "MP4 · 1080p" or "MP3 · 320 kbps".
  String get summary {
    switch (mode) {
      case DownloadMode.audioOnly:
        final f = audioFormat == AudioFormat.original ? 'Audio (original)' : audioFormat.label.split(' ').first;
        if (audioFormat.isLossless || audioFormat == AudioFormat.original) return f;
        return audioQuality.kbps == 0 ? '$f · best' : '$f · ${audioQuality.kbps} kbps';
      case DownloadMode.original:
        return 'Original file';
      case DownloadMode.videoAndAudio:
      case DownloadMode.videoOnly:
        final res = maxHeight == null ? 'best' : '${maxHeight}p';
        return '${container.label} · $res${mode == DownloadMode.videoOnly ? ' · no audio' : ''}';
    }
  }

  /// The media kind used to choose the save collection.
  bool get isAudio => mode == DownloadMode.audioOnly;
}

class Preset {
  const Preset(this.id, this.name, this.options);
  final String id;
  final String name;
  final DownloadOptions options;
}

const builtinPresets = <Preset>[
  Preset('best-video', 'Best Video Quality', DownloadOptions(container: MediaContainer.mkv)),
  Preset('best-audio', 'Best Audio Quality', DownloadOptions(mode: DownloadMode.audioOnly)),
  Preset('mp4-1080', 'MP4 1080p', DownloadOptions(maxHeight: 1080, codec: CodecPreference.h264)),
  Preset('mp4-720', 'MP4 720p', DownloadOptions(maxHeight: 720, codec: CodecPreference.h264)),
  Preset(
    'mp3',
    'MP3',
    DownloadOptions(mode: DownloadMode.audioOnly, audioFormat: AudioFormat.mp3, audioQuality: AudioQuality(320)),
  ),
  Preset(
    'original',
    'Original Format',
    DownloadOptions(mode: DownloadMode.original, embedMetadata: false, embedThumbnail: false, embedChapters: false),
  ),
];

Preset presetById(String id) => builtinPresets.firstWhere((p) => p.id == id, orElse: () => builtinPresets[2]);
