import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/core/audio_engine.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/bootstrap.dart';
import 'package:omnis/core/main_core.dart';
import 'package:omnis/core/plugin_interface.dart';
import 'package:omnis/ui/home_page.dart';
import 'package:omnis/ui/player_layouts/layout_manager.dart';
import 'package:omnis/ui/theme/declarative/theme_manager.dart';
import 'package:omnis_plugin_api/plugin_destination.dart';
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
/// (six core destinations plus one per enabled plugin tab) — other
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
      // Two plugins, so index 6 (the first plugin slot) means something
      // *different* after the first one is removed. With selection tracked
      // by raw index, disabling plugin A while it was selected left index 6
      // in range — length shrinks 8 -> 7, and `6 >= 7` is false, so no
      // bounds check fired — and index 6 silently resolved to plugin B's
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
      // Six core tabs + two plugin tabs; Alpha is the first plugin slot.
      expect(_homeStack(tester, childCount: 8).index, 6);

      await core.pluginManager
          .disablePlugin(core.pluginManager.byId('plugin_a')!);
      await tester.pumpAndSettle();

      // Beta's *tab* survives — it's only Alpha that went away.
      expect(find.text('Beta'), findsOneWidget);
      // The point of the test. Index 6 is now Beta; asserting on the
      // resolved index rather than on rendered text is deliberate, since
      // an IndexedStack keeps every child mounted and only the selected
      // one is actually shown.
      expect(_homeStack(tester, childCount: 7).index, isNot(6));
      expect(_homeStack(tester, childCount: 7).index, 0);
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
      // 'settings' is the last of the six core destinations — nowhere
      // near `_coreDestinationIds.first`, so this only passes if the
      // initial `_selectedDestinationId` actually comes from the
      // persisted setting rather than from that constant.
      AppSettings.instance.defaultLaunchTabId = 'settings';

      await tester.pumpWidget(const MaterialApp(home: HomePage()));
      await _settle(tester);

      // Six core tabs, no plugins registered; 'settings' is index 5.
      expect(_homeStack(tester, childCount: 6).index, 5);
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

      expect(_homeStack(tester, childCount: 6).index, 0);
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
}
