import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/platform_capabilities.dart';
import 'package:omnis/core/plugin_interface.dart';
import 'package:omnis/core/plugin_manager.dart';
import 'package:omnis/ui/settings/controls_settings_page.dart';
import 'package:omnis_plugin_api/plugin_destination.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A bundled plugin contributing exactly one tab — same minimal shape
/// `plugin_manager_home_destinations_test.dart`'s `_OneDestinationPlugin`
/// already uses, duplicated here rather than shared since these are two
/// independent test files.
class _TabContributingPlugin extends MusicPlugin {
  @override
  final String id;
  final String tabLabel;

  _TabContributingPlugin({required this.id, required this.tabLabel});

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
          pageBuilder: (context) => const Placeholder(),
        ),
      ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.initialize();
  });

  tearDown(PlatformCapabilities.resetOverridesForTesting);

  Future<void> pumpControls(WidgetTester tester,
      {PluginManager? pluginManager}) async {
    await tester.pumpWidget(
      MaterialApp(
          home: ControlsSettingsPage(
              pluginManager: pluginManager ?? PluginManager())),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
      'shows Gesture mode and Enable player gestures when not '
      'desktop-primary', (tester) async {
    PlatformCapabilities.debugIsDesktopPrimaryOverride = false;
    await pumpControls(tester);

    expect(find.text('Gesture mode'), findsOneWidget);
    expect(find.text('Enable player gestures'), findsOneWidget);
    // Button layout and auto-hide nav are unrelated to swipe-as-a-shortcut
    // and must stay visible on every platform.
    expect(find.text('Button layout'), findsOneWidget);
    expect(find.text('Auto-hide bottom navigation'), findsOneWidget);
  });

  testWidgets(
      'hides Gesture mode and Enable player gestures entirely on a '
      'desktop-primary platform — swipe is not a shortcut desktop users '
      'reach for', (tester) async {
    PlatformCapabilities.debugIsDesktopPrimaryOverride = true;
    await pumpControls(tester);

    expect(find.text('Gesture mode'), findsNothing);
    expect(find.text('Enable player gestures'), findsNothing);
    // Everything unrelated to swipe gestures stays put.
    expect(find.text('Button layout'), findsOneWidget);
    expect(find.text('Auto-hide bottom navigation'), findsOneWidget);
  });

  testWidgets(
      'Default launch tab defaults to Library and lists every core '
      'destination', (tester) async {
    await pumpControls(tester);

    expect(find.text('Default launch tab'), findsOneWidget);
    expect(AppSettings.instance.defaultLaunchTabId, 'library');
    // The dropdown's closed button shows only the current selection's
    // label.
    expect(find.text('Library'), findsOneWidget);

    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();

    // The closed button's own selection text is still present underneath
    // the open menu (same reason `library_settings_page_test.dart`'s own
    // dropdown test selects via `.last`), so every core label — including
    // the current selection — appears at least once.
    for (final label in [
      'Home',
      'Library',
      'Playlist',
      'Moods',
      'Online',
      'Settings',
    ]) {
      expect(find.text(label), findsWidgets);
    }
  });

  testWidgets(
      'lists a plugin-contributed destination as a launch tab option and '
      'persists selecting it', (tester) async {
    final manager = PluginManager();
    manager.register(_TabContributingPlugin(id: 'radio', tabLabel: 'Radio'));
    await pumpControls(tester, pluginManager: manager);

    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    expect(find.text('Radio'), findsOneWidget);

    await tester.tap(find.text('Radio').last);
    await tester.pumpAndSettle();

    expect(AppSettings.instance.defaultLaunchTabId, 'radio_tab');
    expect(find.text('Radio'), findsOneWidget);
  });

  testWidgets(
      'a stale persisted launch tab id (e.g. a since-disabled plugin) shows '
      'no selection rather than crashing', (tester) async {
    AppSettings.instance.defaultLaunchTabId = 'gone_plugin_tab';

    await pumpControls(tester);

    expect(find.text('Default launch tab'), findsOneWidget);
    expect(find.text('First available'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
