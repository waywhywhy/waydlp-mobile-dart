import 'dart:async';

import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../models/media.dart';
import '../models/options.dart';
import '../services/args.dart';
import '../services/engine.dart';
import '../services/errors.dart';
import '../services/progress.dart';
import '../services/url.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Analyse a link with yt-dlp, show real metadata and choose options.
class AnalyzeScreen extends StatefulWidget {
  const AnalyzeScreen({super.key, required this.url, this.singleOnly = false});
  final Uri url;
  final bool singleOnly;

  @override
  State<AnalyzeScreen> createState() => _AnalyzeScreenState();
}

class _AnalyzeScreenState extends State<AnalyzeScreen> {
  ProbeResult? _result;
  Failure? _failure;
  bool _loading = true;
  late DownloadOptions _options;
  String _presetId = '';
  List<bool> _selected = const [];
  bool _started = false;
  bool _adding = false;
  late Engine _engine;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _engine = AppScope.of(context).engine;
    if (_started) return;
    _started = true;
    final s = AppScope.of(context).settings.value;
    _presetId = s.defaultPreset;
    _options = s.defaultOptions;
    unawaited(_probe());
  }

  @override
  void dispose() {
    // Inherited widgets must not be looked up in dispose(); use the cached engine.
    if (_loading) unawaited(_engine.cancelProbe().catchError((_) {}));
    super.dispose();
  }

  Future<void> _probe() async {
    final engine = AppScope.of(context).engine;
    final noPlaylist = widget.singleOnly || hasVideoAndList(widget.url);
    try {
      final json = await engine.probe(widget.url.toString(), buildProbeArgs(noPlaylist: noPlaylist));
      final r = parseProbeJson(json);
      if (!mounted) return;
      setState(() {
        _result = r;
        _loading = false;
        if (r is PlaylistResult) _selected = List.filled(r.playlist.entries.length, true);
        if (r is SingleResult) _adaptTo(r.media);
      });
    } on EngineException catch (e) {
      if (!mounted) return;
      setState(() {
        _failure = e.code == 'cancelled' ? null : Failure.fromOutput('${e.message}\n${e.details}');
        _loading = false;
      });
    } on FormatException catch (e) {
      if (!mounted) return;
      setState(() {
        _failure = Failure(ErrorKind.unknown, e.message, e.message);
        _loading = false;
      });
    }
  }

  void _adaptTo(MediaInfo m) {
    if (!m.hasVideo &&
        m.hasAudio &&
        _options.mode != DownloadMode.audioOnly &&
        _options.mode != DownloadMode.original) {
      _options = _options.copyWith(mode: DownloadMode.audioOnly);
    }
    final h = _options.maxHeight;
    if (h != null && m.heights.isNotEmpty && !m.heights.any((x) => x <= h)) {
      _options = _options.copyWith(maxHeight: () => null);
    }
  }

  Future<void> _download() async {
    // A second tap while the first is being queued added the download twice.
    if (_adding) return;
    setState(() => _adding = true);
    try {
      await _addToQueue();
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _addToQueue() async {
    final s = AppScope.of(context);
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (s.settings.value.wifiOnly && await s.engine.isMetered()) {
      messenger.showSnackBar(const SnackBar(content: Text('Wi-Fi only is on and you are on a metered connection.')));
      return;
    }
    if (s.settings.value.notifications) unawaited(s.engine.requestNotificationPermission());
    final r = _result;
    try {
      if (r is SingleResult) {
        await s.downloads.add(widget.url, _options, title: r.media.displayTitle, thumbnail: r.media.thumbnail);
      } else if (r is PlaylistResult) {
        final idx = [
          for (var i = 0; i < _selected.length; i++)
            if (_selected[i]) r.playlist.entries[i].index,
        ];
        if (idx.isEmpty) return;
        final all = idx.length == r.playlist.entries.length;
        await s.downloads.add(
          widget.url,
          _options.copyWith(playlistItems: () => all ? null : itemsSpec(idx), formatId: () => null),
          isPlaylist: true,
          title: r.playlist.title,
        );
      }
      messenger.showSnackBar(const SnackBar(content: Text('Added to the queue')));
      nav.pop();
    } on ArgsError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(siteName(widget.url))),
      body: SafeArea(child: _body()),
      bottomNavigationBar: _result == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  onPressed: _adding ? null : _download,
                  icon: const Icon(Icons.download),
                  label: Text(
                    _result is PlaylistResult
                        ? 'Download ${_selected.where((x) => x).length} item(s) · ${_options.summary}'
                        : 'Download · ${_options.summary}',
                  ),
                ),
              ),
            ),
    );
  }

  Widget _body() {
    if (_loading) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const LinearProgressIndicator(),
            const SizedBox(height: 12),
            Text(
              'Asking yt-dlp about ${widget.url}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Palette.text2),
            ),
          ],
        ),
      );
    }
    final f = _failure;
    if (f != null) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionCard(child: FailureView(f)),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () {
              setState(() {
                _loading = true;
                _failure = null;
              });
              unawaited(_probe());
            },
            child: const Text('Try again'),
          ),
        ],
      );
    }
    final r = _result;
    if (r == null) return const SizedBox.shrink();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (r is SingleResult) _mediaCard(r.media) else if (r is PlaylistResult) _playlistCard(r.playlist),
        const SizedBox(height: 12),
        _optionsCard(r is SingleResult ? r.media : null),
      ],
    );
  }

  Widget _mediaCard(MediaInfo m) {
    final reduce = AppScope.of(context).settings.value.reduceMotion;
    return SectionCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (m.thumbnail != null)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.network(
                  m.thumbnail!,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  frameBuilder: reduce
                      ? null
                      : (c, child, frame, sync) => AnimatedOpacity(
                          opacity: frame == null && !sync ? 0 : 1,
                          duration: const Duration(milliseconds: 200),
                          child: child,
                        ),
                  errorBuilder: (_, _, _) => const ColoredBox(color: Palette.surface2),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.displayTitle, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                if (m.uploader != null) Text(m.uploader!, style: const TextStyle(color: Palette.text2)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (m.duration != null) Pill(formatDuration(m.duration!), color: Palette.text2),
                    if (m.heights.isNotEmpty) Pill('up to ${m.heights.first}p', color: Palette.text2),
                    if (m.bestAudioKbps != null) Pill('audio ~${m.bestAudioKbps!.round()} kbps', color: Palette.text2),
                    if (m.isLive) const Pill('LIVE', color: Palette.error),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _playlistCard(PlaylistInfo p) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Pill('PLAYLIST'),
          const SizedBox(height: 6),
          Text(p.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          if (p.uploader != null) Text(p.uploader!, style: const TextStyle(color: Palette.text2)),
          Row(
            children: [
              Text('${p.entries.length} items', style: const TextStyle(color: Palette.muted)),
              const Spacer(),
              TextButton(
                onPressed: () => setState(() => _selected = List.filled(_selected.length, true)),
                child: const Text('All'),
              ),
              TextButton(
                onPressed: () => setState(() => _selected = List.filled(_selected.length, false)),
                child: const Text('None'),
              ),
            ],
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: p.entries.length,
              itemBuilder: (c, i) {
                final e = p.entries[i];
                return CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: _selected[i],
                  onChanged: (v) => setState(() => _selected[i] = v ?? false),
                  title: Text('${e.index}. ${e.displayTitle}', maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: e.duration != null ? Text(formatDuration(e.duration!)) : null,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _optionsCard(MediaInfo? m) {
    final o = _options;
    final heights = m?.heights ?? const [2160, 1440, 1080, 720, 480, 360];
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            initialValue: builtinPresets.any((p) => p.id == _presetId) ? _presetId : null,
            decoration: const InputDecoration(labelText: 'Preset'),
            items: [for (final p in builtinPresets) DropdownMenuItem(value: p.id, child: Text(p.name))],
            onChanged: (id) => setState(() {
              if (id == null) return;
              _presetId = id;
              _options = presetById(id).options;
              if (m != null) _adaptTo(m);
            }),
          ),
          const SizedBox(height: 12),
          SegmentedButton<DownloadMode>(
            showSelectedIcon: false,
            segments: [
              for (final mode in [DownloadMode.videoAndAudio, DownloadMode.audioOnly, DownloadMode.original])
                ButtonSegment(
                  value: mode,
                  label: Text(mode.label),
                  enabled:
                      m == null ||
                      (mode == DownloadMode.audioOnly ? m.hasAudio : (mode == DownloadMode.original || m.hasVideo)),
                ),
            ],
            selected: {o.mode == DownloadMode.videoOnly ? DownloadMode.videoAndAudio : o.mode},
            onSelectionChanged: (v) => setState(() {
              _options = o.copyWith(mode: v.first, formatId: () => null);
              _presetId = '';
            }),
          ),
          const SizedBox(height: 12),
          if (o.mode == DownloadMode.videoAndAudio || o.mode == DownloadMode.videoOnly) ...[
            DropdownButtonFormField<int?>(
              initialValue: o.maxHeight != null && heights.contains(o.maxHeight) ? o.maxHeight : null,
              decoration: InputDecoration(labelText: m == null ? 'Maximum quality' : 'Quality'),
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('Best available')),
                for (final h in heights) DropdownMenuItem<int?>(value: h, child: Text(resolutionLabel(h))),
              ],
              onChanged: (h) => setState(() => _options = o.copyWith(maxHeight: () => h)),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<MediaContainer>(
              initialValue: o.container,
              decoration: const InputDecoration(labelText: 'Container'),
              items: [for (final c in MediaContainer.values) DropdownMenuItem(value: c, child: Text(c.label))],
              onChanged: (c) => setState(() => _options = o.copyWith(container: c)),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<CodecPreference>(
              initialValue: o.codec,
              decoration: const InputDecoration(labelText: 'Codec preference'),
              items: [
                for (final c in CodecPreference.values)
                  if (m == null || c.family == null || m.videoCodecs.contains(c.family))
                    DropdownMenuItem(value: c, child: Text(c.label)),
              ],
              onChanged: (c) => setState(() => _options = o.copyWith(codec: c)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Video only (no sound)'),
              value: o.mode == DownloadMode.videoOnly,
              onChanged: (v) =>
                  setState(() => _options = o.copyWith(mode: v ? DownloadMode.videoOnly : DownloadMode.videoAndAudio)),
            ),
          ],
          if (o.mode == DownloadMode.audioOnly) ...[
            DropdownButtonFormField<AudioFormat>(
              initialValue: o.audioFormat,
              decoration: const InputDecoration(labelText: 'Format'),
              items: [for (final f in AudioFormat.values) DropdownMenuItem(value: f, child: Text(f.label))],
              onChanged: (f) => setState(
                () => _options = o.copyWith(audioFormat: f, normalize: f == AudioFormat.original ? false : null),
              ),
            ),
            if (!o.audioFormat.isLossless && o.audioFormat != AudioFormat.original) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<AudioQuality>(
                initialValue: o.audioQuality,
                decoration: const InputDecoration(labelText: 'Encoding quality'),
                items: [for (final q in AudioQuality.choices) DropdownMenuItem(value: q, child: Text(q.label))],
                onChanged: (q) => setState(() => _options = o.copyWith(audioQuality: q)),
              ),
            ],
            const SizedBox(height: 6),
            Text(
              'Bitrates are encoder targets; converting cannot add quality missing from the source.'
              '${m?.bestAudioKbps != null ? ' Best source audio here: ~${m!.bestAudioKbps!.round()} kbps.' : ''}',
              style: const TextStyle(color: Palette.muted, fontSize: 12),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Normalize loudness'),
              subtitle: const Text('Similar volume across tracks (re-encodes)'),
              value: o.normalize,
              onChanged: o.audioFormat == AudioFormat.original
                  ? null
                  : (v) => setState(() => _options = o.copyWith(normalize: v)),
            ),
          ],
          if (o.mode == DownloadMode.original)
            const Text(
              'The best single file exactly as the site serves it, without conversion.',
              style: TextStyle(color: Palette.text2),
            ),
          if (o.mode != DownloadMode.original) ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Embed thumbnail & metadata'),
              value: o.embedThumbnail && o.embedMetadata,
              onChanged: (v) => setState(() => _options = o.copyWith(embedThumbnail: v, embedMetadata: v)),
            ),
            if (o.mode != DownloadMode.audioOnly && (m == null || m.subtitles.isNotEmpty))
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Download subtitles'),
                subtitle: m != null ? Text('Available: ${m.subtitles.take(8).join(', ')}') : null,
                value: o.subtitles,
                onChanged: (v) => setState(() {
                  final langs = m != null && m.subtitles.isNotEmpty && !m.subtitles.contains('en')
                      ? [m.subtitles.first]
                      : ['en'];
                  _options = o.copyWith(subtitles: v, subtitleLanguages: langs);
                }),
              ),
          ],
          if (_result is PlaylistResult) ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Number files by position'),
              value: o.numberFiles,
              onChanged: (v) => setState(() => _options = o.copyWith(numberFiles: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Folder per playlist'),
              value: o.playlistFolder,
              onChanged: (v) => setState(() => _options = o.copyWith(playlistFolder: v)),
            ),
          ],
          if (_result is SingleResult && hasVideoAndList(widget.url))
            TextButton(
              onPressed: () => Navigator.of(context).pushReplacement(
                MaterialPageRoute<void>(
                  builder: (_) => AnalyzeScreen(
                    url: Uri.parse('https://www.youtube.com/playlist?list=${widget.url.queryParameters['list']}'),
                  ),
                ),
              ),
              child: const Text('Open the whole playlist instead'),
            ),
        ],
      ),
    );
  }
}
