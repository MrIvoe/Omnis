import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/plugin_interface.dart';
import 'package:omnis/core/plugin_manager.dart';
import 'package:omnis/ui/plugin_settings_page.dart';
import 'package:omnis/ui/plugins_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SettingsPlugin extends MusicPlugin {
  @override
  String get id => 'with_settings';
  @override
  String get name => 'Has Settings';
  @override
  String get description => 'A plugin with configurable settings';
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
  dynamic uiSlot(String locationID) => locationID == 'plugin_settings'
      ? const Text('my custom setting field')
      : null;
  @override
  Future<void> dispose() async {}
}

class _NoSettingsPlugin extends MusicPlugin {
  @override
  String get id => 'no_settings';
  @override
  String get name => 'No Settings';
  @override
  String get description => 'A plugin with nothing to configure';
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
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('renders whatever the plugin returns for plugin_settings',
      (tester) async {
    final manager = PluginManager();
    manager.register(_SettingsPlugin());
    await manager.initializeAll();

    await tester.pumpWidget(MaterialApp(
      home: PluginSettingsPage(
        pluginManager: manager,
        plugin: manager.byId('with_settings')!,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Has Settings'), findsOneWidget); // AppBar title
    expect(find.text('my custom setting field'), findsOneWidget);
    expect(find.text('This plugin has no configurable settings.'),
        findsNothing);
  });

  testWidgets('shows a fallback message for a plugin with no settings',
      (tester) async {
    final manager = PluginManager();
    manager.register(_NoSettingsPlugin());
    await manager.initializeAll();

    await tester.pumpWidget(MaterialApp(
      home: PluginSettingsPage(
        pluginManager: manager,
        plugin: manager.byId('no_settings')!,
      ),
    ));
    await tester.pumpAndSettle();

    expect(
        find.text('This plugin has no configurable settings.'), findsOneWidget);
  });

  testWidgets('shows a disabled notice when the plugin is off', (tester) async {
    final manager = PluginManager();
    manager.register(_SettingsPlugin());
    await manager.initializeAll();
    await manager.disablePlugin(manager.byId('with_settings')!);

    await tester.pumpWidget(MaterialApp(
      home: PluginSettingsPage(
        pluginManager: manager,
        plugin: manager.byId('with_settings')!,
      ),
    ));
    await tester.pumpAndSettle();

    // Settings are still shown (a disabled plugin must stay configurable)…
    expect(find.text('my custom setting field'), findsOneWidget);
    // …alongside a clear notice that it's currently off.
    expect(find.textContaining('disabled'), findsOneWidget);
  });

  testWidgets('tapping a plugin in the Plugins list opens its settings page',
      (tester) async {
    final manager = PluginManager();
    manager.register(_SettingsPlugin());
    await manager.initializeAll();

    await tester.pumpWidget(MaterialApp(
      home: PluginsPage(
        pluginManager: manager,
        sandbox: manager.sandbox,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Has Settings'));
    await tester.pumpAndSettle();

    expect(find.text('my custom setting field'), findsOneWidget);
  });
}
