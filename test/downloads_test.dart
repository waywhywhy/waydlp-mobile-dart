import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waydlp/models/options.dart';
import 'package:waydlp/services/downloads.dart';
import 'package:waydlp/services/engine.dart';
import 'package:waydlp/services/settings_store.dart';

/// Drives the real [Downloads] controller against mocked native channels.
class FakeNative {
  FakeNative() {
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(const MethodChannel('io.github.waywhywhy.waydlp/engine'), (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'jobPaths':
          return {'output': '/out', 'temp': '/tmp'};
        case 'updateYtDlp':
          if (failUpdate) throw PlatformException(code: 'ytdlp', message: 'offline');
          return 'Updated';
        case 'ytDlpVersion':
          return '2026.10.26';
        case 'isMetered':
          return metered;
        case 'drainFinished':
        case 'activeHistoryIds':
          return <Object?>[];
      }
      return null;
    });
    m.setMockStreamHandler(
      const EventChannel('io.github.waywhywhy.waydlp/events'),
      MockStreamHandler.inline(onListen: (_, sink) => this.sink = sink),
    );
  }

  final calls = <String>[];
  MockStreamHandlerEventSink? sink;
  bool failUpdate = false;
  bool metered = false;

  int count(String method) => calls.where((c) => c == method).length;

  void emit(String type, String id, [Map<String, Object?> data = const {}]) =>
      sink!.success({'kind': 'job', 'type': type, 'id': id, 'data': data});
}

const _outdated =
    'WARNING: Your yt-dlp version (2025.11.12) is older than 90 days!\n'
    'ERROR: unable to download video data: HTTP Error 403: Forbidden';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeNative native;
  late SettingsStore settings;
  late Downloads d;

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    native = FakeNative();
    settings = SettingsStore(await SharedPreferences.getInstance());
    final engine = Engine();
    d = Downloads(engine: engine, history: null, settings: settings);
    await settle(); // let the event stream attach
  });

  test('yt-dlp age comes from the date-based version', () {
    final now = DateTime.utc(2026, 11, 13, 12);
    expect(ytDlpAgeDays('2025.11.12', now: now), 366);
    expect(ytDlpAgeDays('2026.11.13', now: now), 0);
    expect(ytDlpAgeDays('2026.07.04.1', now: now), 132);
    expect(ytDlpAgeDays('2030.01.01', now: now), 0);
    expect(ytDlpAgeDays(null, now: now), isNull);
    expect(ytDlpAgeDays('nightly', now: now), isNull);
  });

  test('an outdated-yt-dlp failure updates yt-dlp once and retries', () async {
    final job = await d.add(Uri.parse('https://www.youtube.com/watch?v=x'), const DownloadOptions());
    expect(native.count('enqueue'), 1);

    native.emit('failed', job.id, {'error': _outdated});
    await settle();
    expect(native.count('updateYtDlp'), 1);
    expect(native.count('enqueue'), 2, reason: 'retried after the update');
    expect(job.state, JobState.queued);
    expect(d.engine.version.value, '2026.10.26');

    // Still failing after the update: no endless update loop.
    native.emit('failed', job.id, {'error': _outdated});
    await settle();
    expect(native.count('updateYtDlp'), 1);
    expect(job.state, JobState.failed);
  });

  test('self-healing is off when automatic updates are off', () async {
    await settings.update(settings.value.copyWith(autoUpdateYtDlp: false));
    final job = await d.add(Uri.parse('https://www.youtube.com/watch?v=x'), const DownloadOptions());
    native.emit('failed', job.id, {'error': _outdated});
    await settle();
    expect(native.count('updateYtDlp'), 0);
    expect(job.state, JobState.failed);
  });

  test('a failed update leaves the job failed', () async {
    native.failUpdate = true;
    final job = await d.add(Uri.parse('https://www.youtube.com/watch?v=x'), const DownloadOptions());
    native.emit('failed', job.id, {'error': _outdated});
    await settle();
    expect(job.state, JobState.failed);
    expect(native.count('enqueue'), 1);
  });

  test('retry failed restarts only failed jobs', () async {
    final failed = await d.add(Uri.parse('https://example.com/a'), const DownloadOptions());
    final done = await d.add(Uri.parse('https://example.com/b'), const DownloadOptions());
    native.emit('failed', failed.id, {'error': 'ERROR: [x] a: Private video'});
    native.emit('finished', done.id);
    await settle();
    expect(failed.state, JobState.failed);
    expect(done.state, JobState.completed);

    await d.retryFailed();
    expect(failed.state, JobState.queued);
    expect(done.state, JobState.completed);
    expect(native.count('enqueue'), 3);
  });

  test('pause all and resume all', () async {
    final a = await d.add(Uri.parse('https://example.com/a'), const DownloadOptions());
    native.emit('started', a.id);
    await settle();
    await d.pauseAll();
    expect(native.count('stop'), 1);
    native.emit('cancelled', a.id, {'paused': true});
    await settle();
    expect(a.state, JobState.paused);
    await d.resumeAll();
    expect(a.state, JobState.queued);
    expect(native.count('enqueue'), 2);
  });

  test('automatic update runs at most once a day and respects Wi-Fi only', () async {
    final day1 = DateTime(2026, 11, 13, 9);
    expect(await d.maybeAutoUpdate(now: day1), 'Updated');
    expect(settings.value.ytDlpCheckedAt, day1.millisecondsSinceEpoch);
    expect(await d.maybeAutoUpdate(now: day1.add(const Duration(hours: 5))), isNull);
    expect(native.count('updateYtDlp'), 1);

    await settings.update(settings.value.copyWith(wifiOnly: true));
    native.metered = true;
    expect(await d.maybeAutoUpdate(now: day1.add(const Duration(days: 2))), isNull);
    native.metered = false;
    expect(await d.maybeAutoUpdate(now: day1.add(const Duration(days: 2))), 'Updated');

    await settings.update(settings.value.copyWith(autoUpdateYtDlp: false));
    expect(await d.maybeAutoUpdate(now: day1.add(const Duration(days: 9))), isNull);
    expect(native.count('updateYtDlp'), 2);
  });

  test('settings keep the new fields', () {
    final s = Settings.fromJson(
      const Settings(autoUpdateYtDlp: false, ytDlpCheckedAt: 42).toJson().cast<String, Object?>(),
    );
    expect(s.autoUpdateYtDlp, isFalse);
    expect(s.ytDlpCheckedAt, 42);
    expect(Settings.fromJson(const {}).autoUpdateYtDlp, isTrue, reason: 'on by default, also for 0.1.0 settings');
  });
}
