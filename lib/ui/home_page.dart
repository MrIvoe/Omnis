import 'package:flutter/material.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/core/audio_engine.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/bootstrap.dart';
import 'package:omnis/core/library_store.dart';
import 'package:omnis/core/main_core.dart';
import 'package:omnis/core/plugin_manager.dart';
import 'package:omnis/plugin_api/service_interfaces.dart';
import 'package:omnis/ui/library_page.dart';
import 'package:omnis/ui/now_playing_page.dart';
import 'package:omnis/ui/player_layouts/layout_manager.dart';
import 'package:omnis/ui/playlist_page.dart';
import 'package:omnis/ui/settings_page.dart';
import 'package:omnis/ui/theme/declarative/theme_manager.dart';

/// Home shell with navigation tabs.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;
  bool _coreReady = false;

  /// Whether the user has manually revealed the bottom nav during the
  /// current auto-hide episode (landscape or Car Mode layout, while
  /// [AppSettings.bottomNavAutoHide] is on). Reset to `false` every time
  /// that episode starts fresh — see [build] — so entering landscape/Car
  /// Mode always starts hidden, matching "hide when in car mode or
  /// landscape... show when swiped or a button."
  bool _navRevealed = false;
  bool _wasAutoHideActive = false;

  @override
  void initState() {
    super.initState();
    _bootstrapCore();
    // The nav's auto-hide state depends on AppSettings.bottomNavAutoHide
    // and AppSettings.playerLayoutId (Car Mode) — HomePage is a
    // StatefulWidget reused via a `const` instance across app-level
    // rebuilds, so without its own listener it would never notice a
    // change made in Settings.
    AppSettings.instance.addListener(_onSettingsChanged);
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _bootstrapCore() async {
    // `main()` normally has the core (and the layout manager) up before
    // this widget ever builds; both are idempotent and cover the cases
    // where they aren't (tests, deep links, hot restart).
    try {
      await ensureCoreReady();
      await ensureLayoutManagerReady();
      await ensureThemeManagerReady();
    } catch (e) {
      debugPrint('Omnis: failed to bootstrap core for HomePage: $e');
    } finally {
      if (mounted) {
        setState(() => _coreReady = true);
      }
    }
  }

  // NOTE: deliberately no dispose() of MainCore here.
  //
  // This used to call `locator<MainCore>().dispose()` whenever the widget
  // was disposed — but HomePage does not own the core, `main()` does. Any
  // rebuild that replaced this element (a route push that unmounted it, a
  // hot restart) tore down the audio engine and every plugin underneath a
  // still-running app, and left the disposed instance registered in GetIt
  // for the next caller to use. Core teardown belongs to the app
  // lifecycle: see `disposeCore()` in `core/bootstrap.dart`.

  @override
  void dispose() {
    AppSettings.instance.removeListener(_onSettingsChanged);
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
    final settings = AppSettings.instance;

    final pages = <Widget>[
      const NowPlayingPage(),
      LibraryPage(engine: core.audioEngine, pluginManager: core.pluginManager),
      PlaylistPage(engine: core.audioEngine, pluginManager: core.pluginManager),
      _MoodsPage(
        engine: core.audioEngine,
        pluginManager: core.pluginManager,
        onPlaybackStarted: () => setState(() => _selectedIndex = 0),
      ),
      SettingsPage(
          engine: core.audioEngine,
          pluginManager: core.pluginManager,
          sandbox: core.sandbox,
          layoutManager: locator<LayoutManager>(),
          themeManager: locator<ThemeManager>()),
    ];

    // Landscape and Car Mode both want the bottom nav out of the way of
    // playback controls by default; a swipe from the bottom edge or the
    // small handle button bring it back without permanently covering the
    // screen the way always-visible nav would in those orientations.
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final isCarMode = settings.playerLayoutId == 'car_mode';
    final autoHideActive =
        settings.bottomNavAutoHide && (isLandscape || isCarMode);
    if (autoHideActive != _wasAutoHideActive) {
      _wasAutoHideActive = autoHideActive;
      _navRevealed = false;
    }
    final navVisible = !autoHideActive || _navRevealed;

    final navBar = NavigationBar(
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
    );

    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(index: _selectedIndex, children: pages),
          if (autoHideActive)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 28,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onVerticalDragEnd: (details) {
                  final velocity = details.primaryVelocity ?? 0;
                  if (velocity < -150) {
                    setState(() => _navRevealed = true);
                  } else if (velocity > 150) {
                    setState(() => _navRevealed = false);
                  }
                },
              ),
            ),
          if (autoHideActive && !navVisible)
            Positioned(
              right: 12,
              bottom: 12,
              child: FloatingActionButton.small(
                heroTag: 'reveal_bottom_nav',
                tooltip: 'Show navigation',
                onPressed: () => setState(() => _navRevealed = true),
                child: const Icon(Icons.keyboard_arrow_up),
              ),
            ),
        ],
      ),
      bottomNavigationBar: AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeInOut,
        alignment: Alignment.topCenter,
        child: navVisible ? navBar : const SizedBox(width: double.infinity),
      ),
    );
  }
}

/// Moods tab.
///
/// This used to be entirely decorative: every card had `onTap: () {}` (tap
/// did nothing at all), and the mood/preset lists came from brand-new
/// `QueuePresetPlugin()` / `SmartPlaylistPlugin()` instances that were
/// disconnected from the ones actually registered in `PluginManager` —
/// the same disconnected-instance problem the equalizer had. Tapping a
/// mood now actually builds a queue from the real library (via
/// `SmartPlaylistPlugin.buildQueue`, which existed and was never called
/// by anything) and starts playback.
class _MoodsPage extends StatefulWidget {
  final AudioEngine engine;
  final PluginManager pluginManager;
  final VoidCallback onPlaybackStarted;

  const _MoodsPage({
    required this.engine,
    required this.pluginManager,
    required this.onPlaybackStarted,
  });

  @override
  State<_MoodsPage> createState() => _MoodsPageState();
}

class _MoodsPageState extends State<_MoodsPage> {
  bool _loading = false;

  /// Every registered `IQueueBuilder`, in registration order —
  /// `SmartPlaylistPlugin` (curated mood-tag matches) before
  /// `QueuePresetPlugin` (objective BPM/genre fallback), enforced by
  /// `bundled_plugins.dart`'s list order. Looked up by interface, not
  /// concrete plugin type, so a future third mood source registers here
  /// automatically.
  List<IQueueBuilder> get _queueBuilders =>
      widget.pluginManager.services.getAll<IQueueBuilder>();

  /// Builds a queue for [mood]/[preset] by trying every registered
  /// `IQueueBuilder` in order and keeping the first non-empty result.
  /// Previously this hardcoded exactly two concrete plugins and their
  /// fallback order by hand; every preset used to dead-end with "no
  /// tracks tagged" until the user had separately run metadata lookup or
  /// audio analysis, since only the mood-tag path was ever tried —
  /// "Sleep" (a preset only `QueuePresetPlugin` contributes) could never
  /// work at all.
  Future<void> _playMood(String mood) async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final library = await LibraryStore.instance.load();
      if (library.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Your library is empty — add tracks in the Library tab first.',
            ),
          ),
        );
        return;
      }

      var queue = const <BaseTrack>[];
      var usedFallback = false;
      final builders = _queueBuilders;
      for (var i = 0; i < builders.length; i++) {
        final result = builders[i].buildQueueFor(library, mood);
        if (result.isNotEmpty) {
          queue = result;
          usedFallback = i > 0;
          break;
        }
      }

      if (queue.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'No tracks tagged for "$mood" yet — mood matching uses '
              'each track\'s mood/genre metadata.',
            ),
          ),
        );
        return;
      }
      await widget.engine.setQueue(queue);
      await widget.engine.play();
      widget.onPlaybackStarted();
      if (usedFallback && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'No tracks tagged "$mood" yet — playing a BPM/genre-based '
              'match instead.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final moods = <String>{
      for (final builder in _queueBuilders) ...builder.supportedQueries,
    }.toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Moods')),
      body: Stack(
        children: [
          GridView.builder(
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
                  onTap: _loading ? null : () => _playMood(mood),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.mood,
                            size: 36, color: theme.colorScheme.primary),
                        const SizedBox(height: 12),
                        Text(mood, style: theme.textTheme.titleMedium),
                        const SizedBox(height: 4),
                        Text('Tap to build and play a queue',
                            style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          if (_loading)
            const ColoredBox(
              color: Colors.black26,
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}
