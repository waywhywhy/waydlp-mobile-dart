import 'dart:async';

import 'package:flutter/material.dart';

import 'app_scope.dart';
import 'screens/analyze_screen.dart';
import 'screens/history_screen.dart';
import 'screens/home_screen.dart';
import 'screens/queue_screen.dart';
import 'screens/settings_screen.dart';
import 'services/url.dart';
import 'theme.dart';

class WaydlpApp extends StatelessWidget {
  const WaydlpApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = AppScope.of(context).settings;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => MaterialApp(
        title: 'waydlp',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(accent: Color(settings.value.accent), reduceMotion: settings.value.reduceMotion),
        darkTheme: buildTheme(accent: Color(settings.value.accent), reduceMotion: settings.value.reduceMotion),
        themeMode: ThemeMode.dark,
        home: const Shell(),
      ),
    );
  }
}

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;
  StreamSubscription<String>? _shareSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final s = AppScope.of(context);
      _shareSub = s.engine.sharedText.listen(_onShared);
      final initial = await s.engine.consumeSharedText();
      if (initial != null) _onShared(initial);
    });
  }

  void _onShared(String text) {
    final url = firstUrlIn(text);
    if (!mounted) return;
    if (url == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No supported link found in the shared text.')));
      return;
    }
    unawaited(Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AnalyzeScreen(url: url))));
  }

  @override
  void dispose() {
    unawaited(_shareSub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final downloads = AppScope.of(context).downloads;
    final pages = [
      HomeScreen(onOpenQueue: () => setState(() => _tab = 1)),
      const QueueScreen(),
      const HistoryScreen(),
      const SettingsScreen(),
    ];
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(index: _tab, children: pages),
      ),
      bottomNavigationBar: ListenableBuilder(
        listenable: downloads,
        builder: (context, _) {
          final active = downloads.activeCount;
          return NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: active > 0,
                  label: Text('$active'),
                  child: const Icon(Icons.download_outlined),
                ),
                selectedIcon: const Icon(Icons.download),
                label: 'Queue',
              ),
              const NavigationDestination(icon: Icon(Icons.history), label: 'History'),
              const NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: 'Settings',
              ),
            ],
          );
        },
      ),
    );
  }
}
