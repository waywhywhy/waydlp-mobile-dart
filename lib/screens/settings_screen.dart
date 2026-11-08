import 'dart:async';

import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../models/options.dart';
import '../services/args.dart';
import '../services/engine.dart';
import '../services/progress.dart';
import '../services/settings_store.dart';
import '../theme.dart';
import '../widgets/common.dart';

const _accents = <int>[0xFF9D4EDD, 0xFF7C3AED, 0xFFEC4899, 0xFF3B82F6, 0xFF14B8A6, 0xFF22C55E, 0xFFF59E0B];

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _updating = false;
  String? _updateResult;
  int? _cache;

  Future<void> _set(Settings s) async {
    final services = AppScope.of(context);
    await services.settings.update(s);
    await services.engine.setMaxConcurrent(s.maxConcurrent).catchError((_) {});
  }

  Future<void> _updateYtDlp() async {
    setState(() {
      _updating = true;
      _updateResult = null;
    });
    final engine = AppScope.of(context).engine;
    String result;
    try {
      result = await engine.updateYtDlp();
    } on EngineException catch (e) {
      result = 'Update failed: ${e.message}';
    }
    if (mounted) {
      setState(() {
        _updating = false;
        _updateResult = result;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return ListenableBuilder(
      listenable: services.settings,
      builder: (context, _) {
        final s = services.settings.value;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Settings', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            _section('Downloads', [
              DropdownButtonFormField<String>(
                initialValue: s.defaultPreset,
                decoration: const InputDecoration(labelText: 'Default preset'),
                items: [for (final p in builtinPresets) DropdownMenuItem(value: p.id, child: Text(p.name))],
                onChanged: (v) => _set(s.copyWith(defaultPreset: v)),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Save location'),
                subtitle: Text(s.saveLocationLabel ?? 'Download/waydlp (default)'),
                trailing: Wrap(
                  children: [
                    if (s.saveTreeUri != null)
                      TextButton(
                        onPressed: () async {
                          await services.engine.setSaveLocation(null);
                          await _set(s.copyWith(saveTreeUri: () => null, saveLocationLabel: () => null));
                        },
                        child: const Text('Default'),
                      ),
                    TextButton(
                      onPressed: () async {
                        final uri = await services.engine.pickFolder();
                        if (uri == null) return;
                        await services.engine.setSaveLocation(uri);
                        final label = Uri.decodeComponent(
                          uri.split('/').last,
                        ).replaceFirst('primary:', 'Internal storage/');
                        await _set(s.copyWith(saveTreeUri: () => uri, saveLocationLabel: () => label));
                      },
                      child: const Text('Choose…'),
                    ),
                  ],
                ),
              ),
              _slider('Simultaneous downloads', s.maxConcurrent, 1, 4, (v) => _set(s.copyWith(maxConcurrent: v))),
              _slider('Automatic retries', s.autoRetries, 0, 5, (v) => _set(s.copyWith(autoRetries: v))),
              TextFormField(
                initialValue: s.filenameTemplate,
                decoration: const InputDecoration(labelText: 'File name template'),
                onFieldSubmitted: (v) {
                  try {
                    validateTemplate(v);
                    unawaited(_set(s.copyWith(filenameTemplate: v)));
                  } on ArgsError catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
                  }
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: s.rateLimit,
                decoration: const InputDecoration(labelText: 'Speed limit (e.g. 2M, empty = unlimited)'),
                onFieldSubmitted: (v) => _set(s.copyWith(rateLimit: v.trim())),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Wi-Fi only'),
                subtitle: const Text("Don't start downloads on metered/mobile data"),
                value: s.wifiOnly,
                onChanged: (v) => _set(s.copyWith(wifiOnly: v)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Notifications'),
                subtitle: const Text('Progress and completion notifications'),
                value: s.notifications,
                onChanged: (v) async {
                  if (v) await services.engine.requestNotificationPermission();
                  await _set(s.copyWith(notifications: v));
                },
              ),
            ]),
            _section('Appearance', [
              const Text('Accent colour'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                children: [
                  for (final c in _accents)
                    Semantics(
                      label: 'Accent colour',
                      selected: s.accent == c,
                      button: true,
                      child: InkWell(
                        onTap: () => _set(s.copyWith(accent: c)),
                        customBorder: const CircleBorder(),
                        child: CircleAvatar(
                          radius: 16,
                          backgroundColor: Color(c),
                          child: s.accent == c ? const Icon(Icons.check, size: 18, color: Colors.white) : null,
                        ),
                      ),
                    ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Reduce motion'),
                value: s.reduceMotion,
                onChanged: (v) => _set(s.copyWith(reduceMotion: v)),
              ),
            ]),
            _section('Privacy & storage', [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Save download history'),
                value: s.saveHistory,
                onChanged: (v) => _set(s.copyWith(saveHistory: v)),
              ),
              _slider(
                'Keep history (days, 0 = forever)',
                s.historyDays,
                0,
                365,
                (v) => _set(s.copyWith(historyDays: v)),
                divisions: 73,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Cache'),
                subtitle: Text(_cache == null ? 'Temporary download files' : formatBytes(_cache!)),
                trailing: Wrap(
                  children: [
                    TextButton(
                      onPressed: () async {
                        final n = await services.engine.cacheSize();
                        if (mounted) setState(() => _cache = n);
                      },
                      child: const Text('Size'),
                    ),
                    TextButton(
                      onPressed: () async {
                        await services.engine.clearCache();
                        final n = await services.engine.cacheSize();
                        if (mounted) setState(() => _cache = n);
                      },
                      child: const Text('Clear'),
                    ),
                  ],
                ),
              ),
            ]),
            _section('yt-dlp', [
              Text('Installed: ${services.ytDlpVersion ?? 'unknown'}', style: const TextStyle(color: Palette.text2)),
              const SizedBox(height: 4),
              const Text(
                'Websites change often. Update yt-dlp if a site stops working.',
                style: TextStyle(color: Palette.muted, fontSize: 12),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  FilledButton(onPressed: _updating ? null : _updateYtDlp, child: const Text('Update yt-dlp')),
                  const SizedBox(width: 12),
                  if (_updating) const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  if (_updateResult != null)
                    Expanded(
                      child: Text(_updateResult!, style: const TextStyle(color: Palette.text2)),
                    ),
                ],
              ),
            ]),
            _section('About', [
              const Row(
                children: [
                  AppLogo(size: 36),
                  SizedBox(width: 12),
                  Text('waydlp for Android', style: TextStyle(fontSize: 16)),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Free and open-source (GPL-3.0-or-later). No ads, no accounts, no tracking. '
                'Powered by yt-dlp and FFmpeg via youtubedl-android.',
                style: TextStyle(color: Palette.text2),
              ),
              const SizedBox(height: 8),
              const Text(
                'Only download media you have the right to access. waydlp does not circumvent DRM.',
                style: TextStyle(color: Palette.muted, fontSize: 12),
              ),
              const SizedBox(height: 8),
              const SelectableText(
                'github.com/waywhywhy/waydlp-mobile-dart',
                style: TextStyle(color: Palette.accentHover),
              ),
              TextButton(
                onPressed: () => showLicensePage(context: context, applicationName: 'waydlp'),
                child: const Text('Open-source licenses'),
              ),
              TextButton(onPressed: () => _set(const Settings()), child: const Text('Reset settings to defaults')),
            ]),
          ],
        );
      },
    );
  }

  Widget _section(String title, List<Widget> children) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(fontSize: 12, color: Palette.muted, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    ),
  );

  Widget _slider(String label, int value, int min, int max, ValueChanged<int> onChanged, {int? divisions}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('$label: $value'),
      Slider(
        value: value.toDouble().clamp(min.toDouble(), max.toDouble()),
        min: min.toDouble(),
        max: max.toDouble(),
        divisions: divisions ?? (max - min),
        label: '$value',
        onChanged: (v) => onChanged(v.round()),
      ),
    ],
  );
}
