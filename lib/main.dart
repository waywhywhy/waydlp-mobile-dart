import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'app_scope.dart';
import 'services/downloads.dart';
import 'services/engine.dart';
import 'services/history_store.dart';
import 'services/settings_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final settings = SettingsStore(prefs);
  final engine = Engine();

  HistoryStore? history;
  try {
    history = await HistoryStore.open();
  } catch (_) {
    history = null; // The app still works; the History tab explains the problem.
  }

  final downloads = Downloads(engine: engine, history: history, settings: settings);

  Map<String, Object?> info = const {};
  String? engineError;
  try {
    // First start unpacks the embedded Python/yt-dlp/FFmpeg runtime.
    info = await engine.init();
    await downloads.drainBackgroundResults();
  } on EngineException catch (e) {
    engineError = '${e.message}\n${e.details}'.trim();
  }
  if (history != null) {
    await history.markInterrupted();
    await history.pruneOlderThan(settings.value.historyDays);
  }

  runApp(
    AppScope(
      services: AppServices(
        engine: engine,
        settings: settings,
        history: history,
        downloads: downloads,
        engineInfo: info,
        engineError: engineError,
      ),
      child: const WaydlpApp(),
    ),
  );
}
