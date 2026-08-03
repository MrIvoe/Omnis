import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:omnis/core/main_core.dart';
import 'package:omnis/core/queue_preset_plugin.dart';
import 'package:omnis/core/smart_playlist_plugin.dart';
import 'package:omnis/ui/library_page.dart';
import 'package:omnis/ui/now_playing_page.dart';
import 'package:omnis/ui/playlist_page.dart';
import 'package:omnis/ui/settings_page.dart';

/// Global GetIt instance (same singleton used in main.dart).
GetIt get locator => GetIt.instance;

/// Home shell with navigation tabs.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;
  bool _coreReady = false;

  @override
  void initState() {
    super.initState();
    _bootstrapCore();
  }

  Future<void> _bootstrapCore() async {
    try {
      if (!locator.isRegistered<MainCore>()) {
        final core = MainCore();
        await core.initialize();
        locator.registerSingleton<MainCore>(core);
        locator.registerSingleton(core.audioEngine);
      }
    } catch (e) {
      debugPrint('Omnis: failed to bootstrap core for HomePage: $e');
    } finally {
      if (mounted) {
        setState(() => _coreReady = true);
      }
    }
  }

  @override
  void dispose() {
    if (locator.isRegistered<MainCore>()) {
      unawaited(locator<MainCore>().dispose());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_coreReady) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final core = locator<MainCore>();

    final pages = <Widget>[
      const NowPlayingPage(),
      LibraryPage(engine: core.audioEngine),
      PlaylistPage(engine: core.audioEngine),
      const _MoodsPage(),
      SettingsPage(engine: core.audioEngine, pluginManager: core.pluginManager, sandbox: core.sandbox),
    ];

    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        height: 72,
        elevation: 0,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.graphic_eq),
            label: 'Now playing',
          ),
          NavigationDestination(
            icon: Icon(Icons.library_music),
            label: 'Library',
          ),
          NavigationDestination(
            icon: Icon(Icons.playlist_play),
            label: 'Playlist',
          ),
          NavigationDestination(
            icon: Icon(Icons.mood),
            label: 'Moods',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

class _MoodsPage extends StatelessWidget {
  const _MoodsPage();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final presetPlugin = QueuePresetPlugin();
    final smartPlugin = SmartPlaylistPlugin();
    final moods = [...presetPlugin.presets, ...smartPlugin.moods];

    return Scaffold(
      appBar: AppBar(title: const Text('Moods')),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.1,
        ),
        itemCount: moods.length,
        itemBuilder: (context, index) {
          final mood = moods[index];
          return Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {},
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.mood, size: 36, color: theme.colorScheme.primary),
                    const SizedBox(height: 12),
                    Text(mood, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text('Curated mood-based listening', style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
