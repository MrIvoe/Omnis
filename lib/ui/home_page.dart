import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/core/audio_engine.dart';
import 'package:omnis/core/bootstrap.dart';
import 'package:omnis/core/library_repository.dart';
import 'package:omnis/core/main_core.dart';
import 'package:omnis/core/playlist_store.dart';
import 'package:omnis/core/platform_capabilities.dart';
import 'package:omnis/core/plugin_manager.dart';
import 'package:omnis/plugin_api/plugin_destination.dart';
import 'package:omnis/plugin_api/service_interfaces.dart';
import 'package:omnis/ui/command_palette_dialog.dart';
import 'package:omnis/ui/global_keyboard_shortcuts.dart';
import 'package:omnis/ui/home_navigation.dart';
import 'package:omnis/ui/library_page.dart';
import 'package:omnis/ui/now_playing_page.dart';
import 'package:omnis/ui/player_layouts/layout_manager.dart';
import 'package:omnis/ui/playlist_page.dart';
import 'package:omnis/ui/settings/appearance_settings_page.dart';
import 'package:omnis/ui/settings_page.dart';
import 'package:omnis/ui/theme/declarative/theme_manager.dart';
import 'package:omnis/ui/theme/omnis_icon_catalog.dart';
import 'package:omnis/ui/widgets/global_sidebar_drawer.dart';
import 'package:omnis/ui/widgets/mini_player_bar.dart';

/// Home shell with navigation tabs.
///
/// "Now Playing" used to be one of these tabs — an `IndexedStack` swap
/// with no route boundary, which meant there was nowhere for a real
/// `Hero` shared-element transition to animate across. It's now reached
/// through [MiniPlayerBar] (a persistent bar above the bottom nav,
/// visible whenever a track is loaded) via a genuine `Navigator.push`,
/// which is what makes the album-art `Hero` between the mini-player and
/// the full screen possible at all.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

/// Stable ids for the three fixed core destinations, in render order —
/// the same ids [PluginDestination.id]'s own dartdoc reserves as
/// off-limits to plugins. Selection is tracked by id rather than by
/// index (see [_HomePageState._selectedDestinationId]), so these are
/// the id half of the `pages`/`destinations` lists built in `build()`.
const _coreDestinationIds = <String>[
  'library',
  'playlist',
  'settings',
];

class _HomePageState extends State<HomePage> {
  /// The *id* of the selected destination, not its index.
  ///
  /// An index is not a stable handle on a destination once plugins can
  /// add and remove tabs around the one you're on: with destinations
  /// `[...6 core, pluginA(6), pluginB(7)]`, disabling pluginA while it's
  /// selected shrinks the list to length 7, so a bounds check on index 6
  /// passes — and index 6 now silently resolves to pluginB's tab. The
  /// user would land on a completely different plugin's page with no
  /// indication anything had changed. Keying on the id makes a vanished
  /// destination *look* vanished: `indexOf` returns -1 and `build()`
  /// falls back to Home deliberately. The render index is derived from
  /// this id at build time and never stored.
  String _selectedDestinationId = AppSettings.instance.defaultLaunchTabId;
  bool _coreReady = false;

  /// Plugin-contributed tabs, cached rather than read from
  /// `pluginManager.homeDestinations` inside `build()`.
  ///
  /// That getter runs each plugin's `homeDestinations()` hook through
  /// `Sandbox.runSync`, whose failure path records a health event and
  /// notifies health listeners *synchronously* — and two of those
  /// listeners (`plugins_page.dart`, `plugin_health_page.dart`) call
  /// `setState`. Reading it from `build()` therefore meant one throwing
  /// plugin could fire "setState() or markNeedsBuild() called during
  /// build" on either of those pages while they were mounted. Sandbox's
  /// `_notify` catches and drops whatever a listener throws, so that
  /// surfaced as a silently-dropped rebuild rather than a red screen —
  /// worse to diagnose, not better. `runSync`'s own dartdoc scopes it to
  /// constructor/`attach`-time use, not per-frame use, either way.
  /// Refreshed from [_pluginManagerSub] instead, so the sandbox-touching
  /// call only ever happens outside a build.
  List<PluginDestination> _pluginDestinations = const [];

  /// Keeps [_pluginDestinations] live as plugins are registered, enabled
  /// or disabled at runtime. The suite passed before this existed only
  /// because `enablePlugin`/`disablePlugin` also write through
  /// `AppSettings.setPluginEnabled`, which this state already listens to
  /// for unrelated reasons — an accidental coupling. A plugin registered
  /// by any path that doesn't touch `AppSettings` would never have had
  /// its tab appear.
  StreamSubscription<List<ManagedPlugin>>? _pluginManagerSub;

  /// Same reach-into-an-already-alive-IndexedStack-page pattern the old
  /// `_homeDashboardKey`/`_moodsKey` fields used before Tier 2 moved the
  /// Home dashboard and the Moods cluster into plugins — for the §37
  /// "search everywhere" command palette's Playlist results,
  /// [PlaylistPageState.openPlaylist] reuses that page's own existing
  /// open logic instead of duplicating it here. Playlist is still a core
  /// tab this widget constructs itself, so a `GlobalKey` is still the
  /// right reach for it; the two extracted tabs go through their
  /// plugins' [IHomeCustomizer]/[IMoodPlayer] registrations instead.
  final _playlistKey = GlobalKey<PlaylistPageState>();
  final _scaffoldKey = GlobalKey<ScaffoldState>();

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
    MainCore? core;
    try {
      core = await ensureCoreReady();
      await ensureLayoutManagerReady();
      await ensureThemeManagerReady();
    } catch (e) {
      debugPrint('Omnis: failed to bootstrap core for HomePage: $e');
    } finally {
      // The plugin manager only exists once bootstrap has resolved, so
      // this is the earliest point the destination list can be primed
      // and kept live. Seeding it here rather than in the listener means
      // the initial list and _coreReady land in the same first real
      // build, instead of the first build painting four core tabs and a
      // second one adding the plugin tabs.
      final readyCore = core;
      // `mounted` guards against a route push/pop or hot restart that
      // unmounts HomePage while bootstrap is still awaiting above — without
      // it, a subscription created here after dispose() already ran would
      // never be cancelled and would leak for the process lifetime (its
      // callback's own `mounted` check makes the leak inert, not harmless).
      if (readyCore != null && mounted) {
        _pluginDestinations = readyCore.pluginManager.homeDestinations;
        _pluginManagerSub = readyCore.pluginManager.changes.listen((_) {
          if (mounted) {
            setState(() {
              _pluginDestinations = readyCore.pluginManager.homeDestinations;
            });
          }
        });
      }
      if (mounted) {
        setState(() => _coreReady = true);
      }
    }
    if (core != null) {
      // Deliberately after the first frame with _coreReady painted, not
      // before: the resume prompt is a dialog *over* the real UI, per §42
      // of the product spec ("the user should reopen Omnis and see:
      // Resume where you left off?"), not a blocker in front of it.
      unawaited(_offerResumeIfAvailable(core));
    }
  }

  /// Checks the recovery journal and, if there's something worth
  /// resuming, asks the user before touching playback — the journal can
  /// be stale or from a session the user doesn't care about, so this
  /// never auto-resumes silently.
  Future<void> _offerResumeIfAvailable(MainCore core) async {
    final state = await core.loadResumableState();
    if (state == null || !mounted) return;
    final track = state.currentTrack;
    if (track == null) return;

    final resume = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Resume where you left off?'),
        content: Text('${track.title} — ${track.artists.join(', ')}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Dismiss'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Resume'),
          ),
        ],
      ),
    );

    if (resume == true) {
      await core.resumePlayback(state);
    } else {
      await core.dismissResumableState();
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
    _pluginManagerSub?.cancel();
    super.dispose();
  }

  /// Item 48/spec §38's command palette action list. A separate map from
  /// [GlobalKeyboardShortcuts]'s own bindings — that class's whole
  /// contract is playback key bindings operating on [AudioEngine] alone
  /// (see its own doc comment); the palette needs [BuildContext]/
  /// [MainCore]/the tab index/[AppSettings], a different action surface
  /// entirely, so it stays a sibling rather than growing that class.
  Map<String, VoidCallback> _paletteActions(BuildContext context, MainCore core) {
    return {
      'play': core.audioEngine.play,
      'pause': core.audioEngine.pause,
      'next': core.audioEngine.next,
      'previous': core.audioEngine.previous,
      'shuffle': () => core.audioEngine
          .setShuffleEnabled(!core.audioEngine.shuffleEnabled),
      'open_settings': () =>
          setState(() => _selectedDestinationId = 'settings'),
      'enable_driving_mode': () =>
          setState(() => AppSettings.instance.playerLayoutId = 'car_mode'),
      'open_lyrics': () {
        AppSettings.instance.karaokeMode = true;
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const NowPlayingPage()),
        );
      },
      'change_theme': () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => AppearanceSettingsPage(
              layoutManager: locator<LayoutManager>(),
              themeManager: locator<ThemeManager>(),
            ),
          )),
      'customize_home': () {
        setState(() => _selectedDestinationId = 'home');
        core.pluginManager.services.get<IHomeCustomizer>()?.openCustomizeSheet();
      },
      'scan_library': () async {
        try {
          await core.rescanNow();
        } catch (e) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Library scan failed: $e')),
          );
        }
      },
    };
  }

  /// Opens the command palette with §37's "search everywhere" data
  /// wired in — [LibraryRepository.load]/[PlaylistStore.load] are both
  /// already cheap/in-memory-cached by the time `HomePage` is up (see
  /// their own doc comments elsewhere in this codebase), so awaiting them
  /// right before showing the dialog doesn't introduce a visible delay in
  /// practice; it keeps this dialog itself free of loading-state UI, the
  /// same "caller supplies ready data" shape [_paletteActions] already
  /// uses for commands.
  Future<void> _openCommandPalette(BuildContext context, MainCore core) async {
    final tracks = await LibraryRepository.instance.load();
    final playlists = await PlaylistStore.instance.load();
    final moods = <String>{
      for (final builder
          in core.pluginManager.services.getAll<IQueueBuilder>())
        ...builder.supportedQueries,
    }.toList();
    if (!context.mounted) return;

    showCommandPalette(
      context,
      actions: _paletteActions(context, core),
      tracks: tracks,
      playlists: playlists,
      moods: moods,
      onSelectTrack: (track) async {
        await core.audioEngine.setQueue([track]);
        await core.audioEngine.play();
      },
      onSelectPlaylist: (playlist) {
        setState(() => _selectedDestinationId = 'playlist');
        _playlistKey.currentState?.openPlaylist(playlist);
      },
      // Same shape as the 'customize_home' palette action above: switch
      // to the tab the owning plugin contributes, then act through its
      // registered capability interface. With no Moods-owning plugin
      // enabled, `'moods'` resolves to no destination and `build()`
      // falls back to the first tab, and the lookup below returns null,
      // so this degrades to a harmless no-op rather than throwing.
      onSelectMood: (mood) {
        setState(() => _selectedDestinationId = 'moods');
        core.pluginManager.services.get<IMoodPlayer>()?.playMood(mood);
      },
    );
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

    // Cached, not read from `core.pluginManager.homeDestinations` here —
    // see [_pluginDestinations] for why that getter must not be called
    // from inside build().
    final pluginDestinations = _pluginDestinations;

    final pages = <Widget>[
      LibraryPage(engine: core.audioEngine, pluginManager: core.pluginManager),
      PlaylistPage(
          key: _playlistKey,
          engine: core.audioEngine,
          pluginManager: core.pluginManager),
      SettingsPage(
          engine: core.audioEngine,
          pluginManager: core.pluginManager,
          sandbox: core.sandbox,
          layoutManager: locator<LayoutManager>(),
          themeManager: locator<ThemeManager>()),
      // Keyed by destination id: without a key `IndexedStack` matches
      // its children to existing elements positionally, so when the
      // plugin list shifts, two different plugins' pages that happen to
      // share a widget type would swap `State` with each other.
      for (final d in pluginDestinations)
        Builder(key: ValueKey(d.id), builder: d.pageBuilder),
    ];

    // Landscape and Car Mode both want the bottom nav out of the way of
    // playback controls by default; a swipe from the bottom edge or the
    // small handle button bring it back without permanently covering the
    // screen the way always-visible nav would in those orientations.
    final isLandscape = PlatformCapabilities.isRotatable &&
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final isCarMode = settings.playerLayoutId == 'car_mode';
    final autoHideActive =
        settings.bottomNavAutoHide && (isLandscape || isCarMode);
    if (autoHideActive != _wasAutoHideActive) {
      _wasAutoHideActive = autoHideActive;
      _navRevealed = false;
    }
    final navVisible = !autoHideActive || _navRevealed;

    // The four fixed destinations, unchanged in identity and behavior —
    // only *where* they render (bottom bar vs. side rail) is responsive.
    // See `home_navigation.dart` for the breakpoint/rail-vs-drawer
    // reasoning.
    // Icons resolved through OmnisIconCatalog rather than bare `Icons.xxx`
    // constants (so this list can no longer be `const`) — every glyph
    // here follows the active theme's `icons.style`
    // (OmnisIconStyle.current), the same closed-vocabulary
    // filled/outlined/rounded/sharp switch ThemeEditorPage exposes.
    final destinations = [
      HomeDestinationInfo(OmnisIconCatalog.libraryMusic.resolve(), 'Library'),
      HomeDestinationInfo(OmnisIconCatalog.playlistPlay.resolve(), 'Playlist'),
      HomeDestinationInfo(OmnisIconCatalog.settings.resolve(), 'Settings'),
      for (final d in pluginDestinations) HomeDestinationInfo(d.icon, d.label),
    ];

    // The id of each entry above, in the same order, 1:1 with both
    // `pages` and `destinations` — this is what turns the stored
    // destination *id* back into the index those two lists are indexed
    // by. Kept adjacent to them so the three stay in sync.
    final destinationIds = <String>[
      ..._coreDestinationIds,
      for (final d in pluginDestinations) d.id,
    ];

    // A plugin contributing a destination can be disabled/uninstalled
    // mid-session, removing its id from the list above. Resolving by id
    // rather than clamping an index means that reads as "the tab you
    // were on is gone" and falls back to Home — a shrinking list can no
    // longer quietly hand the user a *different* plugin's page that
    // happens to now sit at the old numeric position. Home, not the last
    // valid index, because "the destination you were on disappeared"
    // should read as "back to the start," not "landed on some other tab."
    var selectedIndex = destinationIds.indexOf(_selectedDestinationId);
    if (selectedIndex < 0) {
      selectedIndex = 0;
      _selectedDestinationId = destinationIds[0];
    }

    final isWideLayout = isWideHomeLayout(context);
    final homeNav = HomeNavigationBar(
      selectedIndex: selectedIndex,
      // HomeNavigationBar reports the tapped *index* (it's also used with
      // plain fixed destination lists elsewhere, so its ValueChanged<int>
      // signature stays as-is); convert to an id at this call site.
      onDestinationSelected: (i) =>
          setState(() => _selectedDestinationId = destinationIds[i]),
      pluginManager: core.pluginManager,
      destinations: destinations,
      onOpenSidebar: () => _scaffoldKey.currentState?.openDrawer(),
    );

    final mainContent = Stack(
      children: [
        IndexedStack(index: selectedIndex, children: pages),
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
    );

    return GlobalKeyboardShortcuts(
      engine: core.audioEngine,
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.keyK, control: true): () {
            if (!AppSettings.instance.keyboardShortcutsEnabled) return;
            _openCommandPalette(context, core);
          },
          const SingleActivator(LogicalKeyboardKey.keyP, control: true): () {
            if (!AppSettings.instance.keyboardShortcutsEnabled) return;
            _openCommandPalette(context, core);
          },
          // UI_SPEC §3's "summoned from anywhere" — the same
          // Ctrl+<letter> convention Ctrl+K/Ctrl+P already establish for
          // the command palette, here for the pop-out sidebar.
          const SingleActivator(LogicalKeyboardKey.keyB, control: true): () {
            if (!AppSettings.instance.keyboardShortcutsEnabled) return;
            _scaffoldKey.currentState?.openDrawer();
          },
        },
        child: Scaffold(
          key: _scaffoldKey,
          drawer: GlobalSidebarDrawer(
            pluginManager: core.pluginManager,
            selectedIndex: selectedIndex,
            destinations: destinations,
            destinationIds: destinationIds,
            playlistKey: _playlistKey,
            onSelectDestination: (i) =>
                setState(() => _selectedDestinationId = destinationIds[i]),
          ),
          // Wide layout: the rail sits beside the content permanently —
          // unlike the bottom bar it's never subject to
          // autoHideActive/navVisible, since it's a side column, not
          // something that overlaps playback controls the way a bottom
          // bar does in landscape/Car Mode.
          body: isWideLayout
              ? Row(
                  children: [
                    homeNav,
                    const VerticalDivider(width: 1, thickness: 1),
                    Expanded(child: mainContent),
                  ],
                )
              : mainContent,
          bottomNavigationBar: AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: navVisible
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      MiniPlayerBar(engine: core.audioEngine),
                      if (!isWideLayout) homeNav,
                    ],
                  )
                : const SizedBox(width: double.infinity),
          ),
        ),
      ),
    );
  }
}
