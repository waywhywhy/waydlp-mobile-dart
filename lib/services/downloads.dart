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

  /// Invalidates a pending automatic-retry timer (manual retry, cancel, remove).
  int retryGen = 0;

  /// yt-dlp was already updated once for this job after an "outdated" failure.
  bool healed = false;
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

  /// Bumped after every history write has completed, so the History tab
  /// reloads once the database is up to date (not on every progress line).
  final ValueNotifier<int> historyRevision = ValueNotifier(0);

  void _historyChanged() => historyRevision.value++;

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
    buildDownloadArgs(
      o: options,
      outputDir: '/x',
      tempDir: '/t',
      isPlaylist: isPlaylist,
      template: s.filenameTemplate,
      net: NetworkOptions(rateLimit: s.rateLimit),
    );
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
      _historyChanged();
    }
    jobs.insert(0, job);
    notifyListeners();
    await _start(job);
    return job;
  }

  Future<void> _start(Job job) async {
    final s = settings.value;
    job.retryGen++; // a manual (re)start supersedes any pending automatic retry
    job
      ..state = JobState.queued
      ..stage = 'Waiting in queue'
      ..failure = null
      ..attempts += 1;
    // Classify a new failure only by this attempt's output.
    job.log.clear();
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
      // Invalid options never fix themselves: fail without automatic retries.
      _fail(job, Failure(ErrorKind.unknown, e.message, e.message), retry: false);
    } on EngineException catch (e) {
      _fail(job, Failure(ErrorKind.engine, e.message, e.details));
    }
  }

  void _onEvent(JobEvent e) {
    final job = byId(e.jobId);
    if (job == null) {
      // A job started by an earlier UI (the service outlived it): the native
      // side stored its result, so apply it now.
      if (const {'finished', 'failed', 'cancelled'}.contains(e.type)) unawaited(drainBackgroundResults());
      return;
    }
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
    // The native side also stores terminal results for UIs that come later;
    // consume them now so they don't pile up (ours are skipped).
    if (const {'finished', 'failed'}.contains(e.type) || (e.type == 'cancelled' && e.data['paused'] != true)) {
      unawaited(drainBackgroundResults());
    }
    notifyListeners();
  }

  void _fail(Job job, Failure f, {bool retry = true}) {
    final retries = settings.value.autoRetries;
    if (retry && f.kind == ErrorKind.extractorOutdated && settings.value.autoUpdateYtDlp && !job.healed) {
      // Self-healing: an outdated yt-dlp is the usual cause (e.g. YouTube's
      // HTTP 403). Update it once, then try again.
      job
        ..healed = true
        ..state = JobState.waitingRetry
        ..failure = f
        ..stage = 'Updating yt-dlp, then retrying…';
      final gen = ++job.retryGen;
      unawaited(
        engine.updateYtDlp().then<void>(
          (_) {
            if (job.retryGen == gen && job.state == JobState.waitingRetry && jobs.contains(job)) {
              unawaited(_start(job..attempts = 0));
            }
          },
          onError: (Object e) {
            if (job.retryGen == gen && job.state == JobState.waitingRetry && jobs.contains(job)) {
              job
                ..state = JobState.failed
                ..stage = f.kind.title;
              _recordHistory(job);
              notifyListeners();
            }
          },
        ),
      );
    } else if (retry && f.kind.isTransient && job.attempts <= retries) {
      job
        ..state = JobState.waitingRetry
        ..failure = f
        ..stage = '${f.kind.title} — retrying in ${5 * job.attempts}s';
      final gen = ++job.retryGen;
      Timer(Duration(seconds: 5 * job.attempts), () {
        if (job.retryGen == gen && job.state == JobState.waitingRetry && jobs.contains(job)) {
          unawaited(_start(job));
        }
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
      h
          .finish(
            id,
            status,
            files: job.savedUris,
            size: job.savedBytes == 0 ? null : job.savedBytes,
            error: job.failure == null ? null : '${job.failure!.kind.title}: ${job.failure!.summary}',
            mime: job.mime,
            title: job.isPlaylist ? null : job.title,
          )
          .then((_) => _historyChanged()),
    );
  }

  Future<void> cancel(Job job) async {
    if (job.state.isFinished) return;
    if (job.state == JobState.running || job.state == JobState.queued) {
      await engine.stop(job.id, keepPartial: false);
    } else {
      // Paused jobs kept their partial files for resuming; nothing will use them now.
      if (job.state == JobState.paused) unawaited(_discard(job));
      job
        ..state = JobState.cancelled
        ..stage = 'Cancelled';
      _recordHistory(job);
      notifyListeners();
    }
  }

  /// Delete partial data kept by a paused or failed job.
  Future<void> _discard(Job job) => engine.discard(job.id).catchError((Object _) {});

  Future<void> pause(Job job) async {
    if (job.state == JobState.running || job.state == JobState.queued) {
      await engine.stop(job.id, keepPartial: true);
    }
  }

  Future<void> resume(Job job) {
    // A paused job continues its retry budget; failed/cancelled ones get a fresh one.
    if (job.state != JobState.paused) job.healed = false;
    return _start(job..attempts = job.state == JobState.paused ? job.attempts - 1 : 0);
  }

  void remove(Job job) {
    if (job.state.isActive) unawaited(engine.stop(job.id, keepPartial: false));
    if (job.state == JobState.paused || job.state == JobState.failed) unawaited(_discard(job));
    if (!job.state.isFinished) {
      // Also stops a pending automatic retry from re-adding the job.
      job
        ..state = JobState.cancelled
        ..stage = 'Removed from the queue';
      _recordHistory(job);
    }
    jobs.remove(job);
    notifyListeners();
  }

  /// Pause every queued, running or retry-waiting download.
  Future<void> pauseAll() async {
    for (final j in jobs.where((j) => j.state.isActive).toList()) {
      if (j.state == JobState.waitingRetry) {
        j
          ..retryGen = j.retryGen + 1
          ..state = JobState.paused
          ..stage = 'Paused';
      } else {
        await pause(j);
      }
    }
    notifyListeners();
  }

  /// Resume every paused download.
  Future<void> resumeAll() async {
    for (final j in jobs.where((j) => j.state == JobState.paused).toList()) {
      await resume(j);
    }
  }

  /// Retry every failed download with a fresh retry budget.
  Future<void> retryFailed() async {
    for (final j in jobs.where((j) => j.state == JobState.failed).toList()) {
      await resume(j);
    }
  }

  /// Automatic daily yt-dlp update (when enabled). Skipped while downloads
  /// run, and on metered connections when Wi-Fi only is on. Returns the
  /// updater's message, or null when nothing was attempted.
  Future<String?> maybeAutoUpdate({DateTime? now}) async {
    final s = settings.value;
    final t = (now ?? DateTime.now()).millisecondsSinceEpoch;
    if (!s.autoUpdateYtDlp || activeCount > 0 || engine.isUpdating) return null;
    final last = s.ytDlpCheckedAt;
    if (last != null && t - last < const Duration(days: 1).inMilliseconds && t >= last) return null;
    if (s.wifiOnly && await engine.isMetered()) return null;
    await settings.update(settings.value.copyWith(ytDlpCheckedAt: () => t));
    try {
      return await engine.updateYtDlp();
    } on EngineException {
      return null; // Offline or GitHub unreachable: try again tomorrow.
    }
  }

  void clearFinished() {
    for (final j in jobs.where((j) => j.state == JobState.failed)) {
      unawaited(_discard(j));
    }
    jobs.removeWhere((j) => j.state.isFinished);
    notifyListeners();
  }

  /// Apply results of jobs that finished while the UI was detached.
  Future<void> drainBackgroundResults() async {
    // Jobs this UI tracks record their own (richer) result.
    final known = {for (final j in jobs) ?j.historyId};
    var changed = false;
    for (final r in await engine.drainFinished()) {
      final hid = r['historyId'];
      final entry = hid is int && history != null && !known.contains(hid) ? await history!.get(hid) : null;
      if (hid is int && entry != null && entry.status == EntryStatus.inProgress) {
        final ok = r['ok'] == true;
        final cancelled = r['cancelled'] == true;
        changed = true;
        await history!.finish(
          hid,
          ok
              ? EntryStatus.completed
              : cancelled
              ? EntryStatus.cancelled
              : EntryStatus.failed,
          files: ((r['uris'] as List<Object?>?) ?? const []).whereType<String>().toList(),
          size: switch (r['size']) {
            final int n when n > 0 => n,
            _ => null,
          },
          mime: r['mime'] as String?,
          error: ok || cancelled ? null : Failure.fromOutput(r['error'] as String? ?? '').kind.title,
          // Quick downloads started without analysis only knew the link.
          title: entry.isPlaylist ? null : r['title'] as String?,
        );
      }
    }
    if (changed) _historyChanged();
  }

  @override
  void dispose() {
    unawaited(_sub.cancel());
    historyRevision.dispose();
    super.dispose();
  }
}
