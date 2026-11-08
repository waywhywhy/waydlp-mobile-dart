import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:waydlp/app.dart';
import 'package:waydlp/app_scope.dart';
import 'package:waydlp/main.dart' as app;
import 'package:waydlp/models/options.dart';
import 'package:waydlp/services/args.dart';
import 'package:waydlp/services/downloads.dart';
import 'package:waydlp/services/history_store.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('real runtime probes, downloads, converts, saves, records and deletes', (tester) async {
    await app.main();
    await tester.pumpAndSettle();
    final services = AppScope.of(tester.element(find.byType(Shell)));
    expect(services.engineError, isNull);
    expect(services.history, isNotNull);
    final url = Uri.parse(const String.fromEnvironment('SMOKE_URL', defaultValue: 'http://10.0.2.2:8765/tone.wav'));
    final probe = await tester.runAsync(() => services.engine.probe(url.toString(), buildProbeArgs(noPlaylist: true)));
    expect((jsonDecode(probe!) as Map)['ext'], 'wav');

    for (final convert in [false, true]) {
      final job = await tester.runAsync(
        () => services.downloads.add(
          url,
          DownloadOptions(
            mode: convert ? DownloadMode.audioOnly : DownloadMode.original,
            audioFormat: convert ? AudioFormat.mp3 : AudioFormat.original,
            embedThumbnail: false,
            embedMetadata: false,
            embedChapters: false,
          ),
          title: 'Smoke ${convert ? 'MP3' : 'original'}',
        ),
      );
      expect(job, isNotNull);
      final deadline = DateTime.now().add(const Duration(minutes: 3));
      while (!job!.state.isFinished && DateTime.now().isBefore(deadline)) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
        await tester.pump();
      }
      expect(job.state, JobState.completed, reason: '${job.failure?.details}\n${job.log.join('\n')}');
      expect(job.savedUris, hasLength(1));
      expect(job.savedBytes, greaterThan(1000));
      if (convert) expect(job.mime, 'audio/mpeg');
      final uri = job.savedUris.single;
      expect(await tester.runAsync(() => services.engine.exists(uri)), isTrue);
      final entry = await tester.runAsync(() => services.history!.get(job.historyId!));
      expect(entry?.status, EntryStatus.completed);
      expect(entry?.files, contains(uri));
      expect(await tester.runAsync(() => services.engine.deleteUri(uri)), isTrue);
      expect(await tester.runAsync(() => services.engine.exists(uri)), isFalse);
    }

    for (final label in ['Queue', 'History', 'Settings', 'Home']) {
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(label)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  }, timeout: const Timeout(Duration(minutes: 8)));
}
