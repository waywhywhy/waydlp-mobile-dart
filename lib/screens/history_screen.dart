import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_scope.dart';
import '../models/options.dart';
import '../services/args.dart';
import '../services/history_store.dart';
import '../services/progress.dart';
import '../theme.dart';
import '../widgets/common.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  String _search = '';
  EntryStatus? _status;
  List<HistoryEntry> _rows = const [];
  bool _listening = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_listening) {
      _listening = true;
      AppScope.of(context).downloads.addListener(_reload);
      unawaited(_reload());
    }
  }

  Future<void> _reload() async {
    final h = AppScope.of(context).history;
    if (h == null) return;
    final rows = await h.list(search: _search, status: _status);
    if (mounted) setState(() => _rows = rows);
  }

  Color _color(EntryStatus s) => switch (s) {
    EntryStatus.completed => Palette.success,
    EntryStatus.failed => Palette.error,
    EntryStatus.cancelled => Palette.muted,
    EntryStatus.inProgress => Palette.warning,
  };

  String _label(EntryStatus s) => switch (s) {
    EntryStatus.completed => 'Completed',
    EntryStatus.failed => 'Failed',
    EntryStatus.cancelled => 'Cancelled',
    EntryStatus.inProgress => 'In progress',
  };

  Future<void> _confirmDelete(HistoryEntry e) async {
    final s = AppScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete downloaded files?'),
        content: Text('${e.files.length} file(s) will be permanently deleted from your device.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Palette.error),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    var failed = 0;
    for (final f in e.files) {
      if (!await s.engine.deleteUri(f)) failed++;
    }
    if (failed == 0) await s.history?.remove(e.id);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          failed == 0 ? 'Deleted' : '$failed file(s) could not be deleted. Remove them with your file manager.',
        ),
      ),
    );
    await _reload();
  }

  Future<void> _clear() async {
    final s = AppScope.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Clear history?'),
        content: const Text('All entries are removed. Downloaded files are kept.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Clear')),
        ],
      ),
    );
    if (ok == true) {
      await s.history?.clear();
      await _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    if (s.history == null) {
      return const EmptyState(
        icon: Icons.error_outline,
        title: 'History unavailable',
        hint: 'The history database could not be opened.',
      );
    }
    return CustomScrollView(
      slivers: [
        SliverAppBar(
          pinned: true,
          title: const Text('History'),
          actions: [
            IconButton(tooltip: 'Clear history', onPressed: _clear, icon: const Icon(Icons.delete_sweep_outlined)),
          ],
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(
              children: [
                TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search title, link or site',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (v) {
                    _search = v;
                    unawaited(_reload());
                  },
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final st in [null, EntryStatus.completed, EntryStatus.failed, EntryStatus.cancelled])
                      ChoiceChip(
                        label: Text(st == null ? 'All' : _label(st)),
                        selected: _status == st,
                        onSelected: (_) {
                          setState(() => _status = st);
                          unawaited(_reload());
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (_rows.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(icon: Icons.history, title: 'No history yet', hint: 'Finished downloads appear here.'),
          )
        else
          SliverList.separated(
            itemCount: _rows.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (c, i) {
              final e = _rows[i];
              final date = e.createdAt.toLocal().toString().substring(0, 16);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Pill(_label(e.status), color: _color(e.status)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              e.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${e.site} · ${e.format} · $date${e.size != null ? ' · ${formatBytes(e.size!)}' : ''}',
                        style: const TextStyle(color: Palette.muted, fontSize: 12),
                      ),
                      if (e.error != null && e.status != EntryStatus.completed)
                        Text(e.error!, style: const TextStyle(color: Palette.error, fontSize: 12)),
                      Wrap(
                        spacing: 4,
                        children: [
                          if (e.files.isNotEmpty) ...[
                            IconButton(
                              tooltip: 'Open',
                              icon: const Icon(Icons.play_arrow),
                              onPressed: () => unawaited(s.engine.openUri(e.files.first, e.mime ?? '*/*')),
                            ),
                            IconButton(
                              tooltip: 'Share',
                              icon: const Icon(Icons.share),
                              onPressed: () => unawaited(s.engine.shareUri(e.files.first, e.mime ?? '*/*')),
                            ),
                          ],
                          IconButton(
                            tooltip: 'Copy link',
                            icon: const Icon(Icons.link),
                            onPressed: () {
                              unawaited(Clipboard.setData(ClipboardData(text: e.url)));
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link copied')));
                            },
                          ),
                          IconButton(
                            tooltip: 'Download again',
                            icon: const Icon(Icons.refresh),
                            onPressed: () async {
                              final messenger = ScaffoldMessenger.of(context);
                              try {
                                final opts = DownloadOptions.fromJson(
                                  jsonDecode(e.optionsJson) as Map<String, Object?>,
                                );
                                await s.downloads.add(Uri.parse(e.url), opts, isPlaylist: e.isPlaylist, title: e.title);
                                messenger.showSnackBar(const SnackBar(content: Text('Added to the queue')));
                              } on ArgsError catch (err) {
                                messenger.showSnackBar(SnackBar(content: Text(err.message)));
                              }
                            },
                          ),
                          IconButton(
                            tooltip: 'Remove entry (keeps files)',
                            icon: const Icon(Icons.remove_circle_outline),
                            onPressed: () async {
                              await s.history?.remove(e.id);
                              await _reload();
                            },
                          ),
                          if (e.files.isNotEmpty)
                            IconButton(
                              tooltip: 'Delete files',
                              icon: const Icon(Icons.delete_forever, color: Palette.error),
                              onPressed: () => _confirmDelete(e),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}
