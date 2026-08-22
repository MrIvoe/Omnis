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

class _TabContributingPlugin extends MusicPlugin {
  @override
  String get id => 'tab_plugin';
  @override
  String get name => 'Tab Plugin';
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
          id: 'tab_plugin_tab',
          icon: Icons.extension,
          label: 'Extra Tab',
          pageBuilder: (context) =>
              const Center(child: Text('Extra Tab Content')),
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
      core.pluginManager.register(_TabContributingPlugin());

      await tester.pumpWidget(const MaterialApp(home: HomePage()));
      await _settle(tester);

      expect(find.text('Extra Tab'), findsOneWidget);

      await tester.tap(find.text('Extra Tab'));
      await tester.pumpAndSettle();

      expect(find.text('Extra Tab Content'), findsOneWidget);
    });
  });

  testWidgets(
      'if _selectedIndex points past a shrunk destination list after a '
      'plugin is disabled, HomePage falls back to Home instead of '
      'crashing IndexedStack', (tester) async {
    await tester.runAsync(() async {
      final core = _registerBareCore();
      addTearDown(_unregisterCore);
      core.pluginManager.register(_TabContributingPlugin());

      await tester.pumpWidget(const MaterialApp(home: HomePage()));
      await _settle(tester);

      await tester.tap(find.text('Extra Tab'));
      await tester.pumpAndSettle();
      expect(find.text('Extra Tab Content'), findsOneWidget);

      // Simulate the plugin disappearing mid-session — this is the exact
      // shrinking-list scenario the clamp in home_page.dart guards. This
      // notifies AppSettings' listeners (HomePage is already subscribed
      // for its own auto-hide-nav reasons), which is what actually drives
      // HomePage to rebuild and recompute its now-shorter destination list.
      final managed = core.pluginManager.byId('tab_plugin')!;
      await core.pluginManager.disablePlugin(managed);
      await tester.pumpAndSettle();

      expect(find.text('Extra Tab Content'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
