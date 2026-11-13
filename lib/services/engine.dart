/// Bridge to the native Android download engine (Kotlin, youtubedl-android).
///
/// Methods run yt-dlp on the device. Download jobs live in a native
/// foreground service so they keep running when the UI is in the
/// background; their output lines are streamed back here and parsed in Dart.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Age in days of a date-based yt-dlp version such as `2025.11.12`
/// (null for other version formats).
int? ytDlpAgeDays(String? version, {DateTime? now}) {
  final m = RegExp(r'^(\d{4})\.(\d{1,2})\.(\d{1,2})').firstMatch(version?.trim() ?? '');
  if (m == null) return null;
  final released = DateTime.utc(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  final n = (now ?? DateTime.now()).toUtc();
  final days = DateTime.utc(n.year, n.month, n.day).difference(released).inDays;
  return days < 0 ? 0 : days;
}

/// yt-dlp itself warns once a version is older than this; sites start failing.
const ytDlpStaleDays = 90;

class EngineException implements Exception {
  EngineException(this.code, this.message, [this.details = '']);
  final String code;
  final String message;
  final String details;
  @override
  String toString() => '$code: $message';
}

/// A native event about a job.
class JobEvent {
  JobEvent(this.type, this.jobId, this.data);
  final String type; // line | started | finished | failed | cancelled | saved
  final String jobId;
  final Map<Object?, Object?> data;
}

class Engine {
  Engine({MethodChannel? method, EventChannel? events})
    : _method = method ?? const MethodChannel('io.github.waywhywhy.waydlp/engine'),
      _events = events ?? const EventChannel('io.github.waywhywhy.waydlp/events');

  final MethodChannel _method;
  final EventChannel _events;
  Stream<Object?>? _stream;

  /// Installed yt-dlp version (null until known). Every screen listens to it.
  final ValueNotifier<String?> version = ValueNotifier(null);

  Future<String>? _updating;

  Stream<Object?> get rawEvents => _stream ??= _events.receiveBroadcastStream().asBroadcastStream();

  Stream<JobEvent> get jobEvents => rawEvents
      .where((e) => e is Map && e['kind'] == 'job')
      .map((e) => e as Map)
      .map((e) => JobEvent(e['type'] as String, e['id'] as String, (e['data'] as Map?) ?? const {}));

  Stream<String> get sharedText =>
      rawEvents.where((e) => e is Map && e['kind'] == 'shared').map((e) => (e as Map)['text'] as String);

  Future<T?> _call<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await _method.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      throw EngineException(e.code, e.message ?? 'native error', e.details?.toString() ?? '');
    }
  }

  /// Unpack the embedded runtime (first start) and report versions.
  Future<Map<String, Object?>> init() async {
    final info = Map<String, Object?>.from(await _call<Map<Object?, Object?>>('init') ?? const {});
    version.value = info['ytDlpVersion'] as String?;
    return info;
  }

  /// Returns yt-dlp's JSON output, or throws [EngineException] with stderr in `details`.
  Future<String> probe(String url, List<String> args) async =>
      await _call<String>('probe', {'url': url, 'args': args}) ?? '';

  Future<void> cancelProbe() => _call<void>('cancelProbe');

  /// Start (or queue) a download job in the foreground service.
  Future<void> enqueue({
    required String jobId,
    required String url,
    required List<String> args,
    required String title,
    required bool audio,
    int? historyId,
  }) => _call<void>('enqueue', {
    'id': jobId,
    'url': url,
    'args': args,
    'title': title,
    'audio': audio,
    'historyId': historyId,
  });

  /// Stop a job. `keepPartial` keeps its temporary files so it can resume.
  Future<void> stop(String jobId, {required bool keepPartial}) =>
      _call<void>('stop', {'id': jobId, 'keepPartial': keepPartial});

  /// Delete the partial data a paused job kept (it is being cancelled or removed).
  Future<void> discard(String jobId) => _call<void>('discard', {'id': jobId});

  Future<void> setMaxConcurrent(int n) => _call<void>('setMaxConcurrent', {'n': n});

  /// Paths the args builder needs: `{"output": ..., "temp": ...}` for a job.
  Future<Map<String, String>> jobPaths(String jobId) async {
    final m = await _call<Map<Object?, Object?>>('jobPaths', {'id': jobId}) ?? const {};
    return m.map((k, v) => MapEntry(k.toString(), v.toString()));
  }

  /// Update yt-dlp in place. Concurrent callers share one update.
  Future<String> updateYtDlp() => _updating ??= _update().whenComplete(() => _updating = null);

  /// Whether an update is running right now.
  bool get isUpdating => _updating != null;

  Future<String> _update() async {
    final r = await _call<String>('updateYtDlp') ?? 'unknown';
    try {
      version.value = await ytDlpVersion() ?? version.value;
    } on EngineException {
      // Keep the previous version label.
    }
    return r;
  }

  Future<void> openUri(String uri, String mime) => _call<void>('open', {'uri': uri, 'mime': mime});
  Future<void> shareUri(String uri, String mime) => _call<void>('share', {'uri': uri, 'mime': mime});
  Future<bool> deleteUri(String uri) async => await _call<bool>('delete', {'uri': uri}) ?? false;
  Future<bool> exists(String uri) async => await _call<bool>('exists', {'uri': uri}) ?? false;

  Future<bool> isMetered() async => await _call<bool>('isMetered') ?? false;
  Future<bool> requestNotificationPermission() async => await _call<bool>('requestNotifications') ?? true;

  /// Let the user pick a folder (Storage Access Framework). Returns a tree URI or null.
  Future<String?> pickFolder() => _call<String>('pickFolder');

  /// Where finished files are saved: null = Download/waydlp via MediaStore, else a SAF tree URI.
  Future<void> setSaveLocation(String? treeUri) => _call<void>('setSaveLocation', {'uri': treeUri});

  /// Text shared to waydlp before Dart was listening (app launched via Share).
  Future<String?> consumeSharedText() => _call<String>('consumeSharedText');

  /// Results of jobs that finished while no UI was attached.
  Future<List<Map<Object?, Object?>>> drainFinished() async =>
      (await _call<List<Object?>>('drainFinished') ?? const []).whereType<Map<Object?, Object?>>().toList();

  /// History ids of jobs the native service is still running or has queued.
  Future<Set<int>> activeHistoryIds() async =>
      (await _call<List<Object?>>('activeHistoryIds') ?? const []).whereType<int>().toSet();

  Future<String?> ytDlpVersion() => _call<String>('ytDlpVersion');

  Future<void> clearCache() => _call<void>('clearCache');
  Future<int> cacheSize() async => await _call<int>('cacheSize') ?? 0;
}
