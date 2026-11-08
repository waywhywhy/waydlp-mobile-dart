/// Download queue state for the UI. The native foreground service runs the
/// jobs (with the concurrency limit); this controller tracks their real
/// progress, records history and retries transient failures.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/options.dart';
import 'args.dart';
import 'engine.dart';
import 'errors.dart';
import 'history_store.dart';
import 'progress.dart';
import 'settings_store.dart';
import 'url.dart';

enum JobState { queued, running, paused, waitingRetry, completed, failed, cancelled }

extension JobStateX on JobState {
  bool get isFinished => this == JobState.completed || this == JobState.failed || this == JobState.cancelled;
  bool get isActive => this == JobState.queued || this == JobState.running || this == JobState.waitingRetry;
  String get label => switch (this) {
    JobState.queued => 'Queued',
    JobState.running => 'Downloading',
    JobState.paused => 'Paused',
    JobState.waitingRetry => 'Waiting to retry',
    JobState.completed => 'Completed',
    JobState.failed => 'Failed',
    JobState.cancelled => 'Cancelled',
  };
}

class Job {
  Job({
    required this.id,
    required this.url,
    required this.options,
    required this.isPlaylist,
    this.title,
    this.thumbnail,
  });

  final String id;
  final Uri url;
  final DownloadOptions options;
  final bool isPlaylist;
  String? title;
  final String? thumbnail;
  int? historyId;

  JobState state = JobState.queued;
  String stage = 'Waiting in queue';
  DownloadProgress? progress;
  int? itemIndex, itemCount;
  final List<String> savedUris = [];
  String? mime;
  int savedBytes = 0;
  final List<String> warnings = [];
  Failure? failure;
  int attempts = 0;
  final List<String> log = [];

  String get displayTitle => title ?? url.toString();
}

class Downloads extends ChangeNotifier {
  Downloads({required this.engine, required this.history, required this.settings}) {
    _sub = engine.jobEvents.listen(_onEvent);
  }

  final Engine engine;
  final HistoryStore? history;
  final SettingsStore settings;
  late final StreamSubscription<JobEvent> _sub;

  final List<Job> jobs = [];
  int _seq = 0;

  int get activeCount => jobs.where((j) => j.state.isActive).length;

  Job? byId(String id) {
    for (final j in jobs) {
      if (j.id == id) return j;
    }
    return null;
  }

  /// Validate options and add a job. Throws [ArgsError] for invalid options.
  Future<Job> add(Uri url, DownloadOptions options, {bool isPlaylist = false, String? title, String? thumbnail}) async {
    final s = settings.value;
    // Validate early (paths are placeholders here; real ones come from native).
    buildDownloadArgs(o: options, outputDir: '/x', tempDir: '/t', isPlaylist: isPlaylist, template: s.filenameTemplate);
    final job = Job(
      id: '${DateTime.now().millisecondsSinceEpoch}-${_seq++}',
      url: url,
      options: options,
      isPlaylist: isPlaylist,
      title: title,
      thumbnail: thumbnail,
    );
    if (s.saveHistory && history != null) {
      job.historyId = await history!.insert(
        title: title ?? url.toString(),
        url: url.toString(),
        site: siteName(url),
        format: options.summary,
        optionsJson: jsonEncode(options.toJson()),
        isPlaylist: isPlaylist,
        thumbnail: thumbnail,
      );
    }
    jobs.insert(0, job);
    notifyListeners();
    await _start(job);
    return job;
  }

  Future<void> _start(Job job) async {
    final s = settings.value;
    job
      ..state = JobState.queued
      ..stage = 'Waiting in queue'
      ..failure = null
      ..attempts += 1;
    notifyListeners();
    try {
      final paths = await engine.jobPaths(job.id);
      final args = buildDownloadArgs(
        o: job.options,
        outputDir: paths['output']!,
        tempDir: paths['temp']!,
        isPlaylist: job.isPlaylist,
        template: s.filenameTemplate,
        net: NetworkOptions(rateLimit: s.rateLimit),
      );
      await engine.setMaxConcurrent(s.maxConcurrent);
      await engine.enqueue(
        jobId: job.id,
        url: job.url.toString(),
        args: args,
        title: job.displayTitle,
        audio: job.options.isAudio,
        historyId: job.historyId,
      );
    } on ArgsError catch (e) {
      _fail(job, Failure(ErrorKind.unknown, e.message, e.message));
    } on EngineException catch (e) {
      _fail(job, Failure(ErrorKind.engine, e.message, e.details));
    }
  }

  void _onEvent(JobEvent e) {
    final job = byId(e.jobId);
    if (job == null) return;
    switch (e.type) {
      case 'started':
        job
          ..state = JobState.running
          ..stage = 'Starting…';
      case 'line':
        final line = e.data['line'] as String? ?? '';
        if (job.log.length > 300) job.log.removeAt(0);
        switch (parseLine(line)) {
          case DownloadEvent(:final progress):
            job.progress = progress;
            final i = job.itemIndex, n = job.itemCount;
            job.stage = i != null && n != null ? '${progress.streamLabel} · item $i of $n' : progress.streamLabel;
          case PostProcessEvent(:final status, :final processor):
            if (status == 'started' || status == 'processing') {
              job
                ..stage = postprocessorLabel(processor)
                ..progress = null;
            }
            job.log.add(line);
          case ItemEvent(:final index, :final count, :final title):
            job
              ..itemIndex = index
              ..itemCount = count;
            if (!job.isPlaylist && title != null) job.title ??= title;
            job.log.add(line);
          case WarningEvent(:final message):
            if (job.warnings.length < 30) job.warnings.add(message);
            job.log.add(line);
          case FileEvent():
            job.stage = 'Saving…';
            job.log.add(line);
          case LogEvent():
            job.log.add(line);
        }
      case 'saved':
        job.savedUris.add(e.data['uri'] as String);
        job.mime = e.data['mime'] as String?;
        job.savedBytes += (e.data['size'] as int?) ?? 0;
      case 'finished':
        job
          ..state = JobState.completed
          ..stage = job.savedUris.isEmpty ? 'Nothing new to download (already downloaded)' : 'Saved'
          ..progress = null;
        _recordHistory(job);
      case 'cancelled':
        final paused = e.data['paused'] == true;
        job
          ..state = paused ? JobState.paused : JobState.cancelled
          ..stage = paused ? 'Paused — partial data kept' : 'Cancelled';
        if (!paused) _recordHistory(job);
      case 'failed':
        final f = Failure.fromOutput('${e.data['error'] ?? ''}\n${job.log.join('\n')}');
        _fail(job, f);
    }
    notifyListeners();
  }

  void _fail(Job job, Failure f) {
    final retries = settings.value.autoRetries;
    if (f.kind.isTransient && job.attempts <= retries) {
      job
        ..state = JobState.waitingRetry
        ..failure = f
        ..stage = '${f.kind.title} — retrying in ${5 * job.attempts}s';
      Timer(Duration(seconds: 5 * job.attempts), () {
        if (job.state == JobState.waitingRetry) unawaited(_start(job));
      });
    } else {
      job
        ..state = JobState.failed
        ..failure = f
        ..stage = f.kind.title;
      _recordHistory(job);
    }
    notifyListeners();
  }

  void _recordHistory(Job job) {
    final h = history, id = job.historyId;
    if (h == null || id == null) return;
    final status = switch (job.state) {
      JobState.completed => EntryStatus.completed,
      JobState.failed => EntryStatus.failed,
      _ => EntryStatus.cancelled,
    };
    unawaited(
      h.finish(
        id,
        status,
        files: job.savedUris,
        size: job.savedBytes == 0 ? null : job.savedBytes,
        error: job.failure == null ? null : '${job.failure!.kind.title}: ${job.failure!.summary}',
        mime: job.mime,
        title: job.isPlaylist ? null : job.title,
      ),
    );
  }

  Future<void> cancel(Job job) async {
    if (job.state == JobState.running || job.state == JobState.queued) {
      await engine.stop(job.id, keepPartial: false);
    } else {
      job
        ..state = JobState.cancelled
        ..stage = 'Cancelled';
      _recordHistory(job);
      notifyListeners();
    }
  }

  Future<void> pause(Job job) async {
    if (job.state == JobState.running || job.state == JobState.queued) {
      await engine.stop(job.id, keepPartial: true);
    }
  }

  Future<void> resume(Job job) => _start(job..attempts = job.state == JobState.paused ? job.attempts - 1 : 0);

  void remove(Job job) {
    if (job.state.isActive) unawaited(engine.stop(job.id, keepPartial: false));
    jobs.remove(job);
    notifyListeners();
  }

  void clearFinished() {
    jobs.removeWhere((j) => j.state.isFinished);
    notifyListeners();
  }

  /// Apply results of jobs that finished while the UI was detached.
  Future<void> drainBackgroundResults() async {
    for (final r in await engine.drainFinished()) {
      final hid = r['historyId'];
      if (hid is int && history != null) {
        final ok = r['ok'] == true;
        await history!.finish(
          hid,
          ok ? EntryStatus.completed : EntryStatus.failed,
          files: ((r['uris'] as List<Object?>?) ?? const []).whereType<String>().toList(),
          size: r['size'] as int?,
          mime: r['mime'] as String?,
          error: ok ? null : Failure.fromOutput(r['error'] as String? ?? '').kind.title,
        );
      }
    }
  }

  @override
  void dispose() {
    unawaited(_sub.cancel());
    super.dispose();
  }
}
