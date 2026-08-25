import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/core/audio_engine.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/bootstrap.dart';
import 'package:omnis/core/main_core.dart';
import 'package:omnis/core/plugin_context.dart';
import 'package:omnis/core/plugin_interface.dart';
import 'package:omnis/ui/home_page.dart';
import 'package:omnis/ui/player_layouts/layout_manager.dart';
import 'package:omnis/ui/theme/declarative/theme_manager.dart';
import 'package:omnis_plugin_api/custom_mood.dart';
import 'package:omnis_plugin_api/plugin_destination.dart';
import 'package:omnis_plugin_api/service_interfaces.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fake path_provider — HomePage's `_offerResumeIfAvailable` unconditionally
/// reads `RecoveryJournal` (app-documents-dir-backed) once bootstrap
/// completes, so this needs a real, writable directory even though this
/// suite never populates a journal file.
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String tempDir;
  _FakePathProvider(this.tempDir);
  @override
  Future<String?> getApplicationDocumentsPath() async => tempDir;
  @override
  Future<String?> getApplicationSupportPath() async => tempDir;
}

/// A bundled plugin contributing exactly one tab. Parameterised by id and
/// label so a test can register two of them and tell their tabs apart —
/// which the id-keyed-selection tests need, since the whole point is that
/// one plugin's tab must not be mistaken for another's.
class _TabContributingPlugin extends MusicPlugin {
  @override
  final String id;
  final String tabLabel;
  final int tabOrder;

  _TabContributingPlugin({
    this.id = 'tab_plugin',
    this.tabLabel = 'Extra Tab',
    this.tabOrder = 0,
  });

  /// The text this plugin's page renders — derived from [tabLabel] so a
  /// test never has to keep the two in sync by hand.
  String get pageText => '$tabLabel Content';

  @override
  String get name => 'Tab Plugin $id';
  @override
  String get description => 'test plugin';
  @override
  String get version => '1.0.0';
  @override
  String get author => 'test';
  @override
  Future<void> initialize() async {}
  @override
  Future<void> onTrackStart(BaseTrack track) async {}
  @override
  Future<void> onLibraryScan(String file) async {}
  @override
  dynamic uiSlot(String locationID) => null;
  @override
  Future<void> dispose() async {}

  @override
  List<PluginDestination> homeDestinations() => [
        PluginDestination(
          id: '${id}_tab',
          icon: Icons.extension,
          label: tabLabel,
          pageBuilder: (context) => Center(child: Text(pageText)),
          order: tabOrder,
        ),
      ];
}

/// A minimal stand-in for `HomeDashboardPlugin` (Omnis-Plugins) — a
/// plugin that contributes the `'home'` destination and implements
/// `IHomeCustomizer`, exactly the shape Tier 2 task 3 extracted the real
/// Home dashboard into. A spy rather than the real
/// `omnis_plugins.HomeDashboardPlugin` deliberately: that plugin's own
/// page needs a fully-wired `PluginContext` (library/play-history reads)
/// to render without erroring, which is already exhaustively covered by
/// Omnis-Plugins' own `home_dashboard_page_test.dart`/
/// `home_dashboard_plugin_test.dart`. This test only needs to prove
/// `home_page.dart`'s own wiring — the tab's presence/absence and the
/// command palette's `'customize_home'` action reaching whatever's
/// registered as `IHomeCustomizer` — which this lighter double
/// demonstrates just as well, without needing to render the dashboard
/// page itself at all.
class _SpyHomeCustomizerPlugin extends MusicPlugin implements IHomeCustomizer {
  bool openCustomizeSheetCalled = false;

  @override
  String get id => 'home_dashboard';
  @override
  String get name => 'Home Dashboard (spy)';
  @override
  String get description => 'test plugin';
  @override
  String get version => '1.0.0';
  @override
  String get author => 'test';
  @override
  Future<void> initialize() async {
    context?.services.register(IHomeCustomizer, this);
  }
  @override
  Future<void> onTrackStart(BaseTrack track) async {}
  @override
  Future<void> onLibraryScan(String file) async {}
  @override
  dynamic uiSlot(String locationID) => null;
  @override
  Future<void> dispose() async {
    context?.services.unregister(IHomeCustomizer, this);
  }
  @override
  Future<void> disable() async {
    context?.services.unregister(IHomeCustomizer, this);
  }

  @override
  List<PluginDestination> homeDestinations() => [
        PluginDestination(
          id: 'home',
          icon: Icons.home,
          label: 'Home',
          pageBuilder: (context) => const Center(child: Text('Home Content')),
        ),
      ];

  @override
  void openCustomizeSheet() {
    openCustomizeSheetCalled = true;
  }
}

/// The Moods equivalent of [_SpyHomeCustomizerPlugin]: contributes the
/// `'moods'` destination and records what reaches [IMoodPlayer], without
/// rendering the real `MoodsPage` (which lives in `omnis_plugins` and has
/// its own tests there). Also implements [IQueueBuilder] so the command
/// palette actually has a mood name to offer — that list comes from every
/// registered queue builder's `supportedQueries`, not from
/// [IMoodPlayer].
class _SpyMoodPlayerPlugin extends MusicPlugin
    implements IMoodPlayer, IQueueBuilder {
  final List<String> playedMoods = [];

  @override
  String get id => 'moods';
  @override
  String get name => 'Moods (spy)';
  @override
  String get description => 'test plugin';
  @override
  String get version => '1.0.0';
  @override
  String get author => 'test';
  @override
  Future<void> initialize() async {
    context?.services.register(IMoodPlayer, this);
    context?.services.register(IQueueBuilder, this);
  }
  @override
  Future<void> onTrackStart(BaseTrack track) async {}
  @override
  Future<void> onLibraryScan(String file) async {}
  @override
  dynamic uiSlot(String locationID) => null;
  @override
  Future<void> dispose() async {
    context?.services.unregister(IMoodPlayer, this);
    context?.services.unregister(IQueueBuilder, this);
  }
  @override
  Future<void> disable() async {
    context?.services.unregister(IMoodPlayer, this);
    context?.services.unregister(IQueueBuilder, this);
  }

  @override
  List<PluginDestination> homeDestinations() => [
        PluginDestination(
          id: 'moods',
          icon: Icons.mood,
          label: 'Moods',
          pageBuilder: (context) => const Center(child: Text('Moods Content')),
        ),
      ];

  @override
  List<String> get supportedQueries => const ['Moonlight Cruise'];

  @override
  List<BaseTrack> buildQueueFor(List<BaseTrack> tracks, String query) =>
      const [];

  @override
  List<CustomMood> get customMoods => const [];

  @override
  void playMood(String mood) => playedMoods.add(mood);

  @override
  void playCustomMood(CustomMood custom) => playedMoods.add(custom.name);
}

/// Supplies a mood name to the command palette with **no** [IMoodPlayer]
/// registered alongside it — the "Moods plugin disabled, but some other
/// queue builder still names moods" shape the no-op degradation test
/// below needs.
class _MoodNamingQueueBuilderPlugin extends MusicPlugin
    implements IQueueBuilder {
  @override
  String get id => 'mood_names_only';
  @override
  String get name => 'Mood names only';
  @override
  String get description => 'test plugin';
  @override
  String get version => '1.0.0';
  @override
  String get author => 'test';
  @override
  Future<void> initialize() async {
    context?.services.register(IQueueBuilder, this);
  }
  @override
  Future<void> onTrackStart(BaseTrack track) async {}
  @override
  Future<void> onLibraryScan(String file) async {}
  @override
  dynamic uiSlot(String locationID) => null;
  @override
  Future<void> dispose() async {
    context?.services.unregister(IQueueBuilder, this);
  }

  @override
  List<String> get supportedQueries => const ['Moonlight Cruise'];

  @override
  List<BaseTrack> buildQueueFor(List<BaseTrack> tracks, String query) =>
      const [];
}

/// Registers bare (no-I/O) MainCore/AudioEngine/LayoutManager/ThemeManager
/// singletons directly, instead of going through `ensureCoreReady()`/
/// `ensureLayoutManagerReady()`/`ensureThemeManagerReady()` — the same
/// pattern `mini_player_bar_test.dart`'s "pushes a new route"/"reduce
/// motion" tests use to pump a page with real GetIt dependencies. Those
/// three helpers each await real dart:io (`MainCore.initialize()` touches
/// several JSON stores; `LayoutManager.loadInstalled()`/
/// `ThemeManager.loadInstalled()` read installed-layout/theme files off
/// disk), and a real dart:io await inside a plain `testWidgets()` callback
/// reliably hangs forever on this Windows setup (see
/// `declarative_layout_test.dart`'s doc comment for the isolated repro).
/// Bare constructors do none of that I/O, and `HomePage._bootstrapCore()`'s
/// own calls to those three helpers short-circuit to the already-registered
/// instance with no I/O at all once this has run.
MainCore _registerBareCore() {
  final core = MainCore();
  locator.registerSingleton<MainCore>(core);
  locator.registerSingleton<AudioEngine>(core.audioEngine);
  locator.registerSingleton<LayoutManager>(LayoutManager());
  locator.registerSingleton<ThemeManager>(ThemeManager());
  return core;
}

Future<void> _unregisterCore() async {
  await locator.unregister<AudioEngine>();
  await locator.unregister<MainCore>();
  final layoutManager = locator<LayoutManager>();
  await locator.unregister<LayoutManager>();
  await layoutManager.dispose();
  final themeManager = locator<ThemeManager>();
  await locator.unregister<ThemeManager>();
  await themeManager.dispose();
}

/// HomePage's tab `IndexedStack`, identified by how many children it has
/// (four core destinations — Home and Moods were extracted into bundled
/// plugins at Tier 2 tasks 3 and 4 and no longer count — plus one per
/// enabled plugin tab) — other
/// `IndexedStack`s exist deeper in the page tree, and `.first` is not a
/// reliable way to pick this one out. Asserting on `index` rather than on
/// which page's text is rendered matters here: an `IndexedStack` keeps
/// every child mounted, so a page being "not shown" is a property of the
/// stack's index, not of whether its widgets exist.
IndexedStack _homeStack(WidgetTester tester, {required int childCount}) {
  return tester
      .widgetList<IndexedStack>(find.byType(IndexedStack))
      .firstWhere((stack) => stack.children.length == childCount);
}

/// Even with the core pre-registered above, `_bootstrapCore()` still fires
/// an unawaited `RecoveryJournal.instance.load()` (real dart:io) the moment
/// bootstrap resolves. `pumpAndSettle()` alone pumps frames back-to-back
/// with no real time between them, which never gives that read a chance to
/// finish — same "even inside `tester.runAsync()`, an explicit real delay
/// between two pumps is what actually lets it complete" reasoning
/// `home_dashboard_page_test.dart`'s own `_settle` helper documents.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await Future<void>.delayed(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

void main() {
  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir =
        await Directory.systemTemp.createTemp('omnis_home_page_plugin_test');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    await AppSettings.instance.initialize();
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  testWidgets(
      'a plugin-contributed destination appears in the nav after the '
      'six core destinations and its page renders when tapped',
      (tester) async {
    await tester.runAsync(() async {
      final core = _registerBareCore();
      addTearDown(_unregisterCore);
      core.pluginManager.register(_TabContributingPlugin(id: 'tab_plugin'));

      await tester.pumpWidget(const MaterialApp(home: HomePage()));
      await _settle(tester);

      expect(find.text('Extra Tab'), findsOneWidget);

      await tester.tap(find.text('Extra Tab'));
      await tester.pumpAndSettle();

      expect(find.text('Extra Tab Content'), findsOneWidget);
    });
  });

  testWidgets(
      'when the selected plugin tab disappears, HomePage falls back to Home '
      'instead of crashing IndexedStack', (tester) async {
    await tester.runAsync(() async {
      final core = _registerBareCore();
      addTearDown(_unregisterCore);
      core.pluginManager.register(_TabContributingPlugin(id: 'tab_plugin'));

      await tester.pumpWidget(const MaterialApp(home: HomePage()));
      await _settle(tester);

      await tester.tap(find.text('Extra Tab'));
      await tester.pumpAndSettle();
      expect(find.text('Extra Tab Content'), findsOneWidget);

      // Simulate the plugin disappearing mid-session — the exact
      // shrinking-list scenario home_page.dart's id lookup guards.
      final managed = core.pluginManager.byId('tab_plugin')!;
      await core.pluginManager.disablePlugin(managed);
      await tester.pumpAndSettle();

      expect(find.text('Extra Tab Content'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets(
      'disabling the selected plugin falls back to Home rather than to '
      'whichever plugin now occupies its old index', (tester) async {
    await tester.runAsync(() async {
      final core = _registerBareCore();
      addTearDown(_unregisterCore);
      // Two plugins, so index 4 (the first plugin slot) means something
      // *different* after the first one is removed. With selection tracked
      // by raw index, disabling plugin A while it was selected left index 4
      // in range — length shrinks 6 -> 5, and `4 >= 5` is false, so no
      // bounds check fired — and index 4 silently resolved to plugin B's
      // tab instead. Keying selection by destination id is what makes the
      // vanished tab read as vanished.
      core.pluginManager.register(
        _TabContributingPlugin(id: 'plugin_a', tabLabel: 'Alpha', tabOrder: 0),
      );
      core.pluginManager.register(
        _TabContributingPlugin(id: 'plugin_b', tabLabel: 'Beta', tabOrder: 1),
      );

      await tester.pumpWidget(const MaterialApp(home: HomePage()));
      await _settle(tester);

      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Beta'), findsOneWidget);

      await tester.tap(find.text('Alpha'));
      await tester.pumpAndSettle();
      // Four core tabs + two plugin tabs; Alpha is the first plugin slot.
      expect(_homeStack(tester, childCount: 6).index, 4);

      await core.pluginManager
          .disablePlugin(core.pluginManager.byId('plugin_a')!);
      await tester.pumpAndSettle();

      // Beta's *tab* survives — it's only Alpha that went away.
      expect(find.text('Beta'), findsOneWidget);
      // The point of the test. Index 4 is now Beta; asserting on the
      // resolved index rather than on rendered text is deliberate, since
      // an IndexedStack keeps every child mounted and only the selected
      // one is actually shown.
      expect(_homeStack(tester, childCount: 5).index, isNot(4));
      expect(_homeStack(tester, childCount: 5).index, 0);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets(
      'a plugin registered after the first build gets its tab without any '
      'AppSettings change', (tester) async {
    await tester.runAsync(() async {
      final core = _registerBareCore();
      addTearDown(_unregisterCore);

      await tester.pumpWidget(const MaterialApp(home: HomePage()));
      await _settle(tester);

      expect(find.text('Late Tab'), findsNothing);

      // `PluginManager.register` emits on `changes` and never touches
      // AppSettings — unlike enable/disable, which write through
      // `AppSettings.setPluginEnabled` and so used to be the *only* reason
      // HomePage rebuilt at all (it listens to AppSettings for unrelated
      // auto-hide-nav reasons). This is the path that stayed invisible
      // until _HomePageState subscribed to `changes` directly.
      core.pluginManager.register(
        _TabContributingPlugin(id: 'late_plugin', tabLabel: 'Late Tab'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Late Tab'), findsOneWidget);

      await tester.tap(find.text('Late Tab'));
      await tester.pumpAndSettle();
      expect(find.text('Late Tab Content'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets(
      'opens to the destination named by AppSettings.defaultLaunchTabId '
      'instead of always defaulting to the first core tab', (tester) async {
    await tester.runAsync(() async {
      _registerBareCore();
      addTearDown(_unregisterCore);
      // 'settings' is the last of the four core destinations — nowhere
      // near `_coreDestinationIds.first`, so this only passes if the
      // initial `_selectedDestinationId` actually comes from the
      // persisted setting rather than from that constant.
      AppSettings.instance.defaultLaunchTabId = 'settings';

      await tester.pumpWidget(const MaterialApp(home: HomePage()));
      await _settle(tester);

      // Four core tabs, no plugins registered; 'settings' is index 3.
      expect(_homeStack(tester, childCount: 4).index, 3);
    });
  });

  testWidgets(
      'falls back to the first available destination, rather than '
      "crashing, when the persisted default launch tab id doesn't "
      'currently exist (e.g. a disabled plugin)', (tester) async {
    await tester.runAsync(() async {
      _registerBareCore();
      addTearDown(_unregisterCore);
      // Names a destination that was never registered at all — the same
      // "vanished destination" shape a since-disabled plugin's launch-tab
      // choice would leave behind, exercising the existing Tier 0
      // fallback logic (`destinationIds.indexOf` returns -1) for this new
      // call site specifically.
      AppSettings.instance.defaultLaunchTabId = 'a_disabled_plugin_tab';

      await tester.pumpWidget(const MaterialApp(home: HomePage()));
      await _settle(tester);

      expect(_homeStack(tester, childCount: 4).index, 0);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets(
      'a wide-but-not-rotated window (the default flutter test viewport, '
      'and every normal desktop window) does not trigger bottom-nav '
      'auto-hide even though bottomNavAutoHide defaults to true', (tester) async {
    await tester.runAsync(() async {
      _registerBareCore();
      addTearDown(_unregisterCore);

      // Default settings: bottomNavAutoHide == true. The default test
      // surface (800x600) is wider than tall, so
      // `MediaQuery.orientationOf(context) == Orientation.landscape` is
      // also true here — exactly the desktop-window shape that used to
      // conflate "wide window" with "device rotated." On the `flutter
      // test` host platform, `PlatformCapabilities.isRotatable` is
      // `false` (neither Android nor iOS), so `autoHideActive` must stay
      // `false` and the reveal FAB must never appear.
      expect(AppSettings.instance.bottomNavAutoHide, isTrue);

      await tester.pumpWidget(const MaterialApp(home: HomePage()));
      await _settle(tester);

      expect(find.byTooltip('Show navigation'), findsNothing);
    });
  });

  group('Home dashboard plugin (Tier 2 task 3 — Home is no longer a core '
      'destination)', () {
    testWidgets(
        'with no Home-owning plugin registered, no "home" tab renders and '
        'HomePage does not crash', (tester) async {
      await tester.runAsync(() async {
        _registerBareCore();
        addTearDown(_unregisterCore);

        await tester.pumpWidget(const MaterialApp(home: HomePage()));
        await _settle(tester);

        // Four core tabs (library/playlist/online/settings), no "Home"
        // tab among them. The default 800x600 test viewport is wider than
        // tall, so HomeNavigationBar renders a NavigationRail (see
        // home_navigation.dart), not the narrow-layout NavigationBar.
        expect(_homeStack(tester, childCount: 4).index, 0);
        expect(
            find.widgetWithText(NavigationRailDestination, 'Home'),
            findsNothing);
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets(
        'with a Home-owning plugin registered and enabled, its "home" '
        'destination renders as an ordinary plugin tab', (tester) async {
      await tester.runAsync(() async {
        final core = _registerBareCore();
        addTearDown(_unregisterCore);
        core.pluginManager.register(_SpyHomeCustomizerPlugin());

        await tester.pumpWidget(const MaterialApp(home: HomePage()));
        await _settle(tester);

        expect(find.text('Home'), findsWidgets);

        await tester.tap(find.text('Home').first);
        await tester.pumpAndSettle();

        expect(find.text('Home Content'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets(
        "the command palette's 'Customize home' action reaches "
        'openCustomizeSheet() on whatever is registered as '
        'IHomeCustomizer — the interface path that replaced '
        "home_page.dart's own GlobalKey<HomeDashboardPageState> reach "
        'once the dashboard became a plugin-owned page', (tester) async {
      await tester.runAsync(() async {
        final core = _registerBareCore();
        addTearDown(_unregisterCore);
        core.pluginManager.attachContext(OmnisPluginContext(
          audioEngine: core.audioEngine,
          services: core.pluginManager.services,
          events: core.pluginManager.events,
        ));
        final plugin = _SpyHomeCustomizerPlugin();
        core.pluginManager.register(plugin);
        await core.pluginManager.initializeAll();
        expect(core.pluginManager.services.get<IHomeCustomizer>(),
            same(plugin));

        await tester.pumpWidget(const MaterialApp(home: HomePage()));
        await _settle(tester);

        await _focusSomethingInsideHomePageScaffold(tester);

        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await _settle(tester);

        await tester.enterText(find.byType(TextField), 'customize');
        await tester.pumpAndSettle();
        await tester.tap(find.text('Customize home'));
        await tester.pumpAndSettle();

        expect(plugin.openCustomizeSheetCalled, isTrue);
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets(
        "the command palette's 'Customize home' action is a harmless "
        'no-op — not a crash — when nothing is registered as '
        'IHomeCustomizer (the Home plugin disabled/never installed)',
        (tester) async {
      await tester.runAsync(() async {
        _registerBareCore();
        addTearDown(_unregisterCore);

        await tester.pumpWidget(const MaterialApp(home: HomePage()));
        await _settle(tester);

        await _focusSomethingInsideHomePageScaffold(tester);

        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await _settle(tester);

        await tester.enterText(find.byType(TextField), 'customize');
        await tester.pumpAndSettle();
        await tester.tap(find.text('Customize home'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      });
    });
  });

  group('Moods plugin (Tier 2 task 4 — Moods is no longer a core '
      'destination)', () {
    testWidgets(
        'with no Moods-owning plugin registered, no "moods" tab renders and '
        'HomePage does not crash', (tester) async {
      await tester.runAsync(() async {
        _registerBareCore();
        addTearDown(_unregisterCore);

        await tester.pumpWidget(const MaterialApp(home: HomePage()));
        await _settle(tester);

        expect(_homeStack(tester, childCount: 4).index, 0);
        expect(find.widgetWithText(NavigationRailDestination, 'Moods'),
            findsNothing);
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets(
        'with a Moods-owning plugin registered and enabled, its "moods" '
        'destination renders as an ordinary plugin tab', (tester) async {
      await tester.runAsync(() async {
        final core = _registerBareCore();
        addTearDown(_unregisterCore);
        core.pluginManager.register(_SpyMoodPlayerPlugin());

        await tester.pumpWidget(const MaterialApp(home: HomePage()));
        await _settle(tester);

        expect(find.text('Moods'), findsWidgets);

        await tester.tap(find.text('Moods').first);
        await tester.pumpAndSettle();

        expect(find.text('Moods Content'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets(
        "the command palette's mood results reach playMood() on whatever "
        'is registered as IMoodPlayer — the interface path that replaced '
        "home_page.dart's own GlobalKey<MoodsPageState> reach once the "
        'Moods page became plugin-owned', (tester) async {
      await tester.runAsync(() async {
        final core = _registerBareCore();
        addTearDown(_unregisterCore);
        core.pluginManager.attachContext(OmnisPluginContext(
          audioEngine: core.audioEngine,
          services: core.pluginManager.services,
          events: core.pluginManager.events,
        ));
        final plugin = _SpyMoodPlayerPlugin();
        core.pluginManager.register(plugin);
        await core.pluginManager.initializeAll();
        expect(core.pluginManager.services.get<IMoodPlayer>(), same(plugin));

        await tester.pumpWidget(const MaterialApp(home: HomePage()));
        await _settle(tester);

        await _focusSomethingInsideHomePageScaffold(tester);

        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await _settle(tester);

        // A prefix, not the whole name, so the result row's own text stays
        // the only `find.text` match (the query itself renders in the
        // search field).
        await tester.enterText(find.byType(TextField), 'moonl');
        await tester.pumpAndSettle();
        await tester.tap(find.text('Moonlight Cruise'));
        await tester.pumpAndSettle();

        expect(plugin.playedMoods, ['Moonlight Cruise']);
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets(
        "the command palette's mood results are a harmless no-op — not a "
        'crash — when nothing is registered as IMoodPlayer (the Moods '
        'plugin disabled/never installed, while some other queue builder '
        'still names moods)', (tester) async {
      await tester.runAsync(() async {
        final core = _registerBareCore();
        addTearDown(_unregisterCore);
        core.pluginManager.attachContext(OmnisPluginContext(
          audioEngine: core.audioEngine,
          services: core.pluginManager.services,
          events: core.pluginManager.events,
        ));
        core.pluginManager.register(_MoodNamingQueueBuilderPlugin());
        await core.pluginManager.initializeAll();
        expect(core.pluginManager.services.get<IMoodPlayer>(), isNull);

        await tester.pumpWidget(const MaterialApp(home: HomePage()));
        await _settle(tester);

        await _focusSomethingInsideHomePageScaffold(tester);

        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await _settle(tester);

        await tester.enterText(find.byType(TextField), 'moonl');
        await tester.pumpAndSettle();
        await tester.tap(find.text('Moonlight Cruise'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      });
    });
  });
}

/// `HomePage.build()` wraps its `Scaffold` in **two** nested key-handling
/// widgets: `GlobalKeyboardShortcuts` (outer — Space/arrows/Ctrl+Left/
/// Right) and, one level further in, its own `CallbackShortcuts` for
/// Ctrl+K/Ctrl+P/Ctrl+B. `GlobalKeyboardShortcuts` claims a fallback
/// "anchor" `FocusNode` when nothing more specific holds focus (see that
/// class's own doc comment) — but that anchor's `Focus` widget sits
/// *between* the two `CallbackShortcuts`, i.e. it is an ancestor of the
/// inner one, never a descendant. Key-event dispatch only walks upward
/// from whatever node currently holds focus, so with the anchor holding
/// focus (the state `_settle()` alone leaves things in, since nothing in
/// this bare `HomePage()` harness otherwise claims it), Ctrl+K's binding —
/// declared on the *inner* `CallbackShortcuts` — is never reached: the
/// dialog it would open simply never appears, and a subsequent
/// `tester.tap(find.text('Customize home'))` fails with "found 0 widgets"
/// for that reason, not because the palette's list needs narrowing (it
/// still does, separately — see the `enterText` call after this).
///
/// Moving keyboard focus onto any real descendant of the *inner*
/// `CallbackShortcuts` before sending Ctrl+K sidesteps this: dispatch then
/// walks up from that descendant, through the inner `CallbackShortcuts`
/// (where Ctrl+K's binding lives), and only then further out — so the
/// binding fires. The `NavigationRail`/`NavigationBar` destinations
/// (`HomeNavigationBar`, rendered as part of the `Scaffold`'s body/
/// bottomNavigationBar, both inside the inner `CallbackShortcuts`) are a
/// convenient, always-present target for this — 'Library' is always the
/// first destination.
Future<void> _focusSomethingInsideHomePageScaffold(WidgetTester tester) async {
  Focus.of(tester.element(find.text('Library').first), scopeOk: true)
      .requestFocus();
  await tester.pump();
}
