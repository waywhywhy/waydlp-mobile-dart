import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:waydlp/models/media.dart';
import 'package:waydlp/models/options.dart';
import 'package:waydlp/services/args.dart';
import 'package:waydlp/services/errors.dart';
import 'package:waydlp/services/progress.dart';
import 'package:waydlp/services/settings_store.dart';
import 'package:waydlp/services/url.dart';

String? after(List<String> a, String flag) {
  final i = a.indexOf(flag);
  return i >= 0 && i + 1 < a.length ? a[i + 1] : null;
}

void main() {
  group('url', () {
    test('accepts and normalises', () {
      expect(validateUrl('  youtu.be/xyz ').toString(), 'https://youtu.be/xyz');
      expect(validateUrl('"https://vimeo.com/1"').toString(), 'https://vimeo.com/1');
    });
    test('rejects bad and local addresses', () {
      for (final bad in [
        '',
        'hello world',
        'notaurl',
        'ftp://x.com/a',
        'javascript:alert(1)',
        'file:///etc',
        'http://127.0.0.1/x',
        'http://192.168.0.2/',
      ]) {
        expect(() => validateUrl(bad), throwsA(isA<UrlError>()), reason: bad);
      }
    });
    test('extracts urls from shared text', () {
      expect(firstUrlIn('Look at this https://youtu.be/abc cool')?.toString(), 'https://youtu.be/abc');
      expect(firstUrlIn('no link here'), isNull);
      final r = extractUrls('https://a.com/1\nhttps://a.com/1 garbage c.org/3');
      expect(r.valid.map((u) => u.toString()), ['https://a.com/1', 'https://c.org/3']);
      expect(r.rejected, ['garbage']);
    });
    test('site names and playlists', () {
      expect(siteName(Uri.parse('https://m.youtube.com/watch?v=1')), 'YouTube');
      expect(siteName(Uri.parse('https://www.example.org/x')), 'example.org');
      expect(looksLikePlaylist(Uri.parse('https://www.youtube.com/playlist?list=PL1')), isTrue);
      expect(hasVideoAndList(Uri.parse('https://www.youtube.com/watch?v=a&list=b')), isTrue);
    });
  });

  group('args', () {
    List<String> build(DownloadOptions o, {bool playlist = false, String template = defaultTemplate}) =>
        buildDownloadArgs(o: o, outputDir: '/out', tempDir: '/tmp', isPlaylist: playlist, template: template);

    test('ends with -- so the URL can never be an option', () {
      final a = build(const DownloadOptions());
      expect(a.last, '--');
      expect(a, contains('--ignore-config'));
      expect(a, contains('--no-playlist'));
      expect(after(a, '--progress-template'), downloadTemplate);
    });
    test('mp4 1080 h264', () {
      final a = build(presetById('mp4-1080').options);
      expect(after(a, '--format'), 'bv*[height<=1080]+ba/b[height<=1080]/bv*+ba/b');
      expect(after(a, '--format-sort'), 'res:1080,vcodec:h264,ext:mp4:m4a');
      expect(after(a, '--merge-output-format'), 'mp4');
      expect(after(a, '--remux-video'), 'mp4');
    });
    test('mp3 320', () {
      final a = build(presetById('mp3').options);
      expect(a, contains('--extract-audio'));
      expect(after(a, '--audio-format'), 'mp3');
      expect(after(a, '--audio-quality'), '320K');
      expect(a, contains('--embed-thumbnail'));
    });
    test('normalise needs conversion', () {
      expect(
        () => build(const DownloadOptions(mode: DownloadMode.audioOnly, normalize: true)),
        throwsA(isA<ArgsError>()),
      );
    });
    test('original mode has no post-processing', () {
      final a = build(presetById('original').options);
      expect(after(a, '--format'), 'b/bv*+ba');
      expect(a, isNot(contains('--embed-metadata')));
      expect(a, isNot(contains('--extract-audio')));
    });
    test('playlist template and items', () {
      final a = build(const DownloadOptions(playlistItems: '1,3-5'), playlist: true, template: '%(title)s.%(ext)s');
      expect(a, contains('--yes-playlist'));
      expect(after(a, '--playlist-items'), '1,3-5');
      expect(after(a, '--output'), '%(playlist_title,playlist_id|Playlist)s/%(playlist_index)03d - %(title)s.%(ext)s');
    });
    test('rejects unsafe input', () {
      expect(() => build(const DownloadOptions(), template: '../x.%(ext)s'), throwsA(isA<ArgsError>()));
      expect(() => build(const DownloadOptions(formatId: '1;rm')), throwsA(isA<ArgsError>()));
      expect(() => build(const DownloadOptions(playlistItems: '1;2'), playlist: true), throwsA(isA<ArgsError>()));
    });
    test('items spec', () {
      expect(itemsSpec([1, 2, 3, 5, 7, 8]), '1-3,5,7-8');
    });
    test('probe args', () {
      final a = buildProbeArgs(noPlaylist: true);
      expect(a, containsAll(['--dump-single-json', '--flat-playlist', '--no-playlist']));
      expect(a.last, '--');
    });
  });

  group('progress', () {
    test('download line', () {
      final e = parseLine('[waydlp:dl]downloading|1048576|4194304|NA|524288.5|6|NA|NA|avc1.64002A|none');
      final p = (e as DownloadEvent).progress;
      expect(p.fraction, 0.25);
      expect(p.stream, StreamKind.video);
      expect(progressText(p), '1.0 MB of 4.0 MB · 512 KB/s · 6s left');
    });
    test('estimate and unknown totals', () {
      final p = (parseLine('[waydlp:dl]downloading|500|NA|1000|NA|NA|NA|NA|none|opus') as DownloadEvent).progress;
      expect(p.totalIsEstimate, isTrue);
      expect(p.stream, StreamKind.audio);
      final q = (parseLine('[waydlp:dl]downloading|500|NA|NA|NA|NA|NA|NA|NA|NA') as DownloadEvent).progress;
      expect(q.fraction, isNull);
    });
    test('other lines', () {
      expect(parseLine('[waydlp:item]2|10|abc|A | b'), isA<ItemEvent>().having((e) => e.title, 'title', 'A | b'));
      expect(parseLine('[waydlp:file]/x/y.mp4'), isA<FileEvent>().having((e) => e.path, 'path', '/x/y.mp4'));
      expect(parseLine('[waydlp:pp]started|Merger'), isA<PostProcessEvent>());
      expect(postprocessorLabel('Merger'), 'Merging video and audio');
    });
  });

  group('errors', () {
    test('classifies', () {
      expect(classify('ERROR: [youtube] x: Private video'), ErrorKind.private);
      expect(classify('ERROR: Unsupported URL: https://x'), ErrorKind.unsupportedUrl);
      expect(classify('ERROR: HTTP Error 429: Too Many Requests'), ErrorKind.rateLimited);
      expect(classify('ERROR: Unable to extract data; please report this issue'), ErrorKind.extractorOutdated);
      expect(classify('ERROR: This video is DRM protected'), ErrorKind.drm);
      expect(ErrorKind.network.isTransient, isTrue);
      expect(ErrorKind.private.isTransient, isFalse);
    });
    test('redacts secrets', () {
      final f = Failure.fromOutput('Cookie: SID=1\nproxy http://u:p@h:1\nERROR: [x] y: Video unavailable');
      expect(f.kind, ErrorKind.unavailable);
      expect(f.summary, '[x] y: Video unavailable');
      expect(f.details, isNot(contains('SID=1')));
      expect(f.details, contains('http://***@h:1'));
    });
  });

  group('media', () {
    test('real youtube metadata', () {
      final r = parseProbeJson(File('test/fixtures/youtube_video.json').readAsStringSync());
      final m = (r as SingleResult).media;
      expect(m.displayTitle, contains('Big Buck Bunny'));
      expect(m.uploader, 'Blender');
      expect(m.heights, [2160, 1440, 1080, 720, 480, 360, 240, 144]);
      expect(m.videoCodecs, containsAll(['h264', 'vp9', 'av1']));
      expect(m.formats.every((f) => !f.isStoryboard), isTrue);
      expect(m.subtitles, ['de', 'en']);
    });
    test('flat playlist', () {
      final r = parseProbeJson(File('test/fixtures/youtube_playlist_flat.json').readAsStringSync());
      final p = (r as PlaylistResult).playlist;
      expect(p.entries.length, 4);
      expect(p.entries.first.index, 1);
    });
    test('invalid output', () {
      expect(() => parseProbeJson(''), throwsFormatException);
    });
  });

  group('settings & options', () {
    test('settings roundtrip and tolerate garbage', () {
      const s = Settings(maxConcurrent: 3, wifiOnly: true);
      expect(Settings.fromJson(s.toJson()).maxConcurrent, 3);
      expect(Settings.fromJson({'maxConcurrent': 99, 'unknown': 1}).maxConcurrent, 4);
      expect(Settings.fromJson({'defaultPreset': 5}).defaultPreset, 'mp4-1080');
    });
    test('options roundtrip and summary', () {
      final o = presetById('mp3').options;
      final back = DownloadOptions.fromJson(o.toJson());
      expect(back.audioFormat, AudioFormat.mp3);
      expect(back.summary, 'MP3 · 320 kbps');
      expect(presetById('mp4-720').options.summary, 'MP4 · 720p');
    });
  });

  group('regressions', () {
    test('shared text punctuation is not part of the link', () {
      expect(firstUrlIn("Watch this (https://youtu.be/jNQXAC9IVRw).").toString(), 'https://youtu.be/jNQXAC9IVRw');
      expect(firstUrlIn('see https://vimeo.com/1, https://x.com/2').toString(), 'https://vimeo.com/1');
      expect(validateUrl('https://example.com/a?b=c!').toString(), 'https://example.com/a?b=c');
      // Balanced brackets are part of the URL.
      expect(
        validateUrl('https://en.wikipedia.org/wiki/Foo_(bar)').toString(),
        'https://en.wikipedia.org/wiki/Foo_(bar)',
      );
      expect(
        firstUrlIn('(https://en.wikipedia.org/wiki/Foo_(bar))').toString(),
        'https://en.wikipedia.org/wiki/Foo_(bar)',
      );
    });

    test('HTTP 403 from an outdated yt-dlp asks for an update and is not retried', () {
      final f = Failure.fromOutput(
        'WARNING: Your yt-dlp version (2025.11.12) is older than 90 days!\n'
        'ERROR: unable to download video data: HTTP Error 403: Forbidden',
      );
      expect(f.kind, ErrorKind.extractorOutdated);
      expect(f.kind.isTransient, isFalse);
      // A specific error line still wins over the old-version warning.
      expect(
        Failure.fromOutput('WARNING: version is older than 90 days\nERROR: [youtube] x: Private video').kind,
        ErrorKind.private,
      );
    });

    test('speed limit validation', () {
      validateRateLimit('');
      validateRateLimit('2M');
      validateRateLimit('500k');
      expect(() => validateRateLimit('fast'), throwsA(isA<ArgsError>()));
    });
  });
}
