import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/options.dart';

/// Persisted settings with schema versioning.
class Settings {
  const Settings({
    this.defaultPreset = 'mp4-1080',
    this.defaultAudio = AudioFormat.mp3,
    this.maxConcurrent = 2,
    this.wifiOnly = false,
    this.notifications = true,
    this.accent = 0xFF9D4EDD,
    this.reduceMotion = false,
    this.saveHistory = true,
    this.historyDays = 0,
    this.saveTreeUri,
    this.saveLocationLabel,
    this.filenameTemplate = '%(title).150B [%(id)s].%(ext)s',
    this.autoRetries = 2,
    this.rateLimit = '',
    this.autoUpdateYtDlp = true,
    this.ytDlpCheckedAt,
  });

  static const schemaVersion = 1;

  final String defaultPreset;
  final AudioFormat defaultAudio;
  final int maxConcurrent;
  final bool wifiOnly;
  final bool notifications;
  final int accent;
  final bool reduceMotion;
  final bool saveHistory;
  final int historyDays;
  final String? saveTreeUri;
  final String? saveLocationLabel;
  final String filenameTemplate;
  final int autoRetries;
  final String rateLimit;

  /// Update yt-dlp at most once a day, and once more when a download fails
  /// because yt-dlp is outdated. On by default: the bundled copy ages with
  /// the app and sites (YouTube especially) block old versions.
  final bool autoUpdateYtDlp;

  /// Last automatic yt-dlp update check (milliseconds since epoch).
  final int? ytDlpCheckedAt;

  DownloadOptions get defaultOptions => presetById(defaultPreset).options;

  Settings copyWith({
    String? defaultPreset,
    AudioFormat? defaultAudio,
    int? maxConcurrent,
    bool? wifiOnly,
    bool? notifications,
    int? accent,
    bool? reduceMotion,
    bool? saveHistory,
    int? historyDays,
    String? Function()? saveTreeUri,
    String? Function()? saveLocationLabel,
    String? filenameTemplate,
    int? autoRetries,
    String? rateLimit,
    bool? autoUpdateYtDlp,
    int? Function()? ytDlpCheckedAt,
  }) => Settings(
    defaultPreset: defaultPreset ?? this.defaultPreset,
    defaultAudio: defaultAudio ?? this.defaultAudio,
    maxConcurrent: (maxConcurrent ?? this.maxConcurrent).clamp(1, 4),
    wifiOnly: wifiOnly ?? this.wifiOnly,
    notifications: notifications ?? this.notifications,
    accent: accent ?? this.accent,
    reduceMotion: reduceMotion ?? this.reduceMotion,
    saveHistory: saveHistory ?? this.saveHistory,
    historyDays: historyDays ?? this.historyDays,
    saveTreeUri: saveTreeUri != null ? saveTreeUri() : this.saveTreeUri,
    saveLocationLabel: saveLocationLabel != null ? saveLocationLabel() : this.saveLocationLabel,
    filenameTemplate: filenameTemplate ?? this.filenameTemplate,
    autoRetries: (autoRetries ?? this.autoRetries).clamp(0, 5),
    rateLimit: rateLimit ?? this.rateLimit,
    autoUpdateYtDlp: autoUpdateYtDlp ?? this.autoUpdateYtDlp,
    ytDlpCheckedAt: ytDlpCheckedAt != null ? ytDlpCheckedAt() : this.ytDlpCheckedAt,
  );

  Map<String, Object?> toJson() => {
    'schema': schemaVersion,
    'defaultPreset': defaultPreset,
    'defaultAudio': defaultAudio.name,
    'maxConcurrent': maxConcurrent,
    'wifiOnly': wifiOnly,
    'notifications': notifications,
    'accent': accent,
    'reduceMotion': reduceMotion,
    'saveHistory': saveHistory,
    'historyDays': historyDays,
    'saveTreeUri': saveTreeUri,
    'saveLocationLabel': saveLocationLabel,
    'filenameTemplate': filenameTemplate,
    'autoRetries': autoRetries,
    'rateLimit': rateLimit,
    'autoUpdateYtDlp': autoUpdateYtDlp,
    'ytDlpCheckedAt': ytDlpCheckedAt,
  };

  /// Unknown keys are ignored and missing keys use defaults, so older and
  /// newer files both load. Migrations go here when the schema changes.
  factory Settings.fromJson(Map<String, Object?> j) {
    const d = Settings();
    T get<T>(String k, T fallback) => j[k] is T ? j[k] as T : fallback;
    return Settings(
      defaultPreset: get('defaultPreset', d.defaultPreset),
      defaultAudio: AudioFormat.values.firstWhere((a) => a.name == j['defaultAudio'], orElse: () => d.defaultAudio),
      maxConcurrent: get<int>('maxConcurrent', d.maxConcurrent).clamp(1, 4),
      wifiOnly: get('wifiOnly', d.wifiOnly),
      notifications: get('notifications', d.notifications),
      accent: get('accent', d.accent),
      reduceMotion: get('reduceMotion', d.reduceMotion),
      saveHistory: get('saveHistory', d.saveHistory),
      historyDays: get('historyDays', d.historyDays),
      saveTreeUri: j['saveTreeUri'] as String?,
      saveLocationLabel: j['saveLocationLabel'] as String?,
      filenameTemplate: get('filenameTemplate', d.filenameTemplate),
      autoRetries: get<int>('autoRetries', d.autoRetries).clamp(0, 5),
      rateLimit: get('rateLimit', d.rateLimit),
      autoUpdateYtDlp: get('autoUpdateYtDlp', d.autoUpdateYtDlp),
      ytDlpCheckedAt: j['ytDlpCheckedAt'] is int ? j['ytDlpCheckedAt'] as int : null,
    );
  }
}

class SettingsStore extends ChangeNotifier {
  SettingsStore(this._prefs) : _value = _load(_prefs);

  static const _key = 'settings.v1';
  final SharedPreferences _prefs;
  Settings _value;

  Settings get value => _value;

  static Settings _load(SharedPreferences p) {
    final raw = p.getString(_key);
    if (raw == null) return const Settings();
    try {
      return Settings.fromJson(jsonDecode(raw) as Map<String, Object?>);
    } catch (_) {
      return const Settings();
    }
  }

  Future<void> update(Settings s) async {
    _value = s;
    notifyListeners();
    await _prefs.setString(_key, jsonEncode(s.toJson()));
  }

  Future<void> reset() => update(const Settings());
}
