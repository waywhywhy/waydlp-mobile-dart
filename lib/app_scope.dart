import 'package:flutter/widgets.dart';

import 'services/downloads.dart';
import 'services/engine.dart';
import 'services/history_store.dart';
import 'services/settings_store.dart';

/// Shared services, available to every screen.
class AppServices {
  AppServices({
    required this.engine,
    required this.settings,
    required this.history,
    required this.downloads,
    this.engineInfo = const {},
    this.engineError,
  });

  final Engine engine;
  final SettingsStore settings;
  final HistoryStore? history;
  final Downloads downloads;
  final Map<String, Object?> engineInfo;
  final String? engineError;

  /// Installed yt-dlp version; follows updates (manual or automatic).
  ValueNotifier<String?> get ytDlpVersion => engine.version;
}

class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.services, required super.child});
  final AppServices services;

  static AppServices of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.services;

  @override
  bool updateShouldNotify(AppScope oldWidget) => services != oldWidget.services;
}
