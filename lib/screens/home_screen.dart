import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_scope.dart';
import '../models/options.dart';
import '../services/args.dart';
import '../services/downloads.dart';
import '../services/progress.dart';
import '../services/url.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'analyze_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.onOpenQueue});
  final VoidCallback onOpenQueue;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Uri? _validated() {
    try {
      final u = validateUrl(_controller.text);
      setState(() => _error = null);
      return u;
    } on UrlError catch (e) {
      setState(() => _error = e.message);
      return null;
    }
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) return;
    _controller.text = firstUrlIn(text)?.toString() ?? text;
    setState(() => _error = null);
  }

  void _analyze() {
    final u = _validated();
    if (u == null) return;
    unawaited(Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AnalyzeScreen(url: u))));
  }

  Future<void> _quick() async {
    final u = _validated();
    if (u == null) return;
    if (looksLikePlaylist(u) && !u.queryParameters.containsKey('v')) {
      _analyze(); // never download a whole playlist without a preview
      return;
    }
    final s = AppScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (s.settings.value.wifiOnly && await s.engine.isMetered()) {
      messenger.showSnackBar(const SnackBar(content: Text('Wi-Fi only is on and you are on a metered connection.')));
      return;
    }
    try {
      await s.downloads.add(u, s.settings.value.defaultOptions);
      _controller.clear();
      messenger.showSnackBar(const SnackBar(content: Text('Added to the queue')));
      widget.onOpenQueue();
    } on ArgsError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            const AppLogo(size: 40),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('waydlp', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                Text(
                  'Your media, your format, your way.',
                  style: TextStyle(color: Theme.of(context).colorScheme.secondary),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (s.engineError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SectionCard(
              child: Text(
                'The download engine could not start:\n${s.engineError}',
                style: const TextStyle(color: Palette.error),
              ),
            ),
          ),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _controller,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.go,
                onSubmitted: (_) => _analyze(),
                decoration: InputDecoration(
                  hintText: 'Paste a video, song or playlist link',
                  errorText: _error,
                  suffixIcon: IconButton(tooltip: 'Paste', icon: const Icon(Icons.content_paste), onPressed: _paste),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _analyze,
                      icon: const Icon(Icons.search),
                      label: const Text('Analyze'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _quick,
                      icon: const Icon(Icons.bolt),
                      label: Text(presetById(s.settings.value.defaultPreset).name, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Tip: share a link from any app to waydlp.',
                style: TextStyle(color: Palette.muted, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ListenableBuilder(
          listenable: s.downloads,
          builder: (context, _) {
            final active = s.downloads.jobs
                .where((j) => j.state.isActive || j.state == JobState.paused)
                .take(3)
                .toList();
            if (active.isEmpty) return const SizedBox.shrink();
            return SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('Active downloads', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                      const Spacer(),
                      TextButton(onPressed: widget.onOpenQueue, child: const Text('Queue →')),
                    ],
                  ),
                  for (final j in active) ...[
                    const SizedBox(height: 8),
                    Text(j.displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    JobProgress(
                      fraction: j.progress?.fraction,
                      text: j.progress != null && j.state == JobState.running
                          ? '${j.stage} · ${progressText(j.progress!)}'
                          : j.stage,
                      animate: !s.settings.value.reduceMotion,
                    ),
                  ],
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Engine', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
              const SizedBox(height: 6),
              Text(
                'yt-dlp ${s.ytDlpVersion ?? 'not ready'} · FFmpeg built in',
                style: const TextStyle(color: Palette.text2),
              ),
              const SizedBox(height: 4),
              const Text(
                'Downloads run on this device. No account, no servers, no tracking.',
                style: TextStyle(color: Palette.muted, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
