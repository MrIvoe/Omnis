import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/plugin_interface.dart';
import 'package:omnis/core/plugin_manager.dart';
import 'package:omnis/ui/plugin_health_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Same minimal lifecycle-recording fixture `plugins_page_test.dart`
/// already defines for its own (now-moved-here) health tests — kept as
/// its own copy rather than shared across test files, matching this
/// codebase's existing "each test file is self-contained" convention.
class _RecordingPlugin extends MusicPlugin {
  final List<String> calls = [];

  @override
  String get id => 'recording';
  @override
  String get name => 'Recording Plugin';
  @override
  String get description => 'Records lifecycle calls for testing';
  @override
  String get version => '1.0.0';
  @override
  String get author => 'Test';

  @override
  Future<void> initialize() async => calls.add('initialize');
  @override
  Future<void> enable() async => calls.add('enable');
  @override
  Future<void> disable() async => calls.add('disable');
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
  setUp(() {
    // PluginStorage.initialize() (called from PluginManager.initPlugin)
    // calls SharedPreferences.getInstance() — a real platform channel
    // call that hangs indefinitely in a test environment without this
    // mock, the same "test hung for the full 10-minute timeout" class
    // of infrastructure issue this session has hit before.
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('an empty record list shows the healthy empty state',
      (tester) async {
    final manager = PluginManager();

    await tester.pumpWidget(MaterialApp(
      home: PluginHealthPage(pluginManager: manager, sandbox: manager.sandbox),
    ));
    await tester.pump();

    expect(find.text('No plugin failures. The Core is healthy.'),
        findsOneWidget);
    expect(find.text('Dismiss all'), findsNothing);
  });

  testWidgets('a real sandboxed failure renders one summary card with a '
      'Reset button; tapping it resets the named plugin and clears its '
      'record', (tester) async {
    final manager = PluginManager();
    final plugin = _RecordingPlugin();
    manager.register(plugin);
    await manager.initializeAll();
    expect(plugin.calls, ['initialize']);

    await manager.sandbox.run(
      pluginId: 'recording',
      pluginName: 'Recording Plugin',
      hook: 'onTrackStart',
      operation: () => throw StateError('boom'),
    );
    expect(manager.sandbox.healthRecords, hasLength(1));

    await tester.pumpWidget(MaterialApp(
      home: PluginHealthPage(pluginManager: manager, sandbox: manager.sandbox),
    ));
    await tester.pump();

    expect(find.text('Recording Plugin'), findsOneWidget);
    expect(find.textContaining('1 failure total'), findsOneWidget);
    expect(find.text('Reset'), findsOneWidget);

    await tester.tap(find.text('Reset'));
    await tester.pump();

    expect(plugin.calls, ['initialize', 'disable', 'enable']);
    expect(manager.sandbox.healthRecords, isEmpty);
    expect(find.text('No plugin failures. The Core is healthy.'),
        findsOneWidget);
  });

  testWidgets('resetting a plugin that has since been uninstalled shows '
      'a clear message instead of crashing', (tester) async {
    final manager = PluginManager();
    final plugin = _RecordingPlugin();
    manager.register(plugin);
    await manager.initializeAll();

    await manager.sandbox.run(
      pluginId: 'recording',
      pluginName: 'Recording Plugin',
      hook: 'onTrackStart',
      operation: () => throw StateError('boom'),
    );

    await tester.pumpWidget(MaterialApp(
      home: PluginHealthPage(pluginManager: manager, sandbox: manager.sandbox),
    ));
    await tester.pump();

    // Simulate the plugin having vanished between the health record
    // being created and the user tapping Reset — the record still
    // names 'recording', but the manager no longer has it registered.
    await manager.uninstallPlugin(manager.byId('recording')!);
    await tester.pump();

    await tester.tap(find.text('Reset'));
    await tester.pump();

    expect(find.textContaining('no longer installed'), findsOneWidget);
  });

  testWidgets('"View details" expands the raw per-failure records, and '
      'collapses again on a second tap', (tester) async {
    final manager = PluginManager();
    final plugin = _RecordingPlugin();
    manager.register(plugin);
    await manager.initializeAll();

    await manager.sandbox.run(
      pluginId: 'recording',
      pluginName: 'Recording Plugin',
      hook: 'onTrackStart',
      operation: () => throw StateError('boom one'),
    );
    await manager.sandbox.run(
      pluginId: 'recording',
      pluginName: 'Recording Plugin',
      hook: 'onLibraryScan',
      operation: () => throw StateError('boom two'),
    );

    await tester.pumpWidget(MaterialApp(
      home: PluginHealthPage(pluginManager: manager, sandbox: manager.sandbox),
    ));
    await tester.pump();

    expect(find.textContaining('boom one'), findsNothing);
    expect(find.textContaining('boom two'), findsNothing);

    await tester.tap(find.byTooltip('View details'));
    await tester.pump();

    expect(find.textContaining('boom one'), findsOneWidget);
    expect(find.textContaining('boom two'), findsOneWidget);

    await tester.tap(find.byTooltip('Hide details'));
    await tester.pump();

    expect(find.textContaining('boom one'), findsNothing);
  });

  testWidgets('"Dismiss all" clears every record and shows the empty '
      'state', (tester) async {
    final manager = PluginManager();
    final plugin = _RecordingPlugin();
    manager.register(plugin);
    await manager.initializeAll();

    await manager.sandbox.run(
      pluginId: 'recording',
      pluginName: 'Recording Plugin',
      hook: 'onTrackStart',
      operation: () => throw StateError('boom'),
    );

    await tester.pumpWidget(MaterialApp(
      home: PluginHealthPage(pluginManager: manager, sandbox: manager.sandbox),
    ));
    await tester.pump();

    await tester.tap(find.text('Dismiss all'));
    await tester.pump();

    expect(find.text('No plugin failures. The Core is healthy.'),
        findsOneWidget);
  });

  testWidgets('a heartbeat-timeout record renders as "Unresponsive", '
      'distinct from a regular hook crash (item 28)', (tester) async {
    final manager = PluginManager();
    final plugin = _RecordingPlugin();
    manager.register(plugin);
    await manager.initializeAll();

    await manager.sandbox.run(
      pluginId: 'recording',
      pluginName: 'Recording Plugin',
      hook: 'heartbeat',
      operation: () => throw StateError('boom'),
    );

    await tester.pumpWidget(MaterialApp(
      home: PluginHealthPage(pluginManager: manager, sandbox: manager.sandbox),
    ));
    await tester.pump();

    expect(find.textContaining('Unresponsive —'), findsOneWidget);
    expect(find.byIcon(Icons.hourglass_disabled), findsOneWidget);
  });

  testWidgets('a regular hook crash does not render as "Unresponsive"',
      (tester) async {
    final manager = PluginManager();
    final plugin = _RecordingPlugin();
    manager.register(plugin);
    await manager.initializeAll();

    await manager.sandbox.run(
      pluginId: 'recording',
      pluginName: 'Recording Plugin',
      hook: 'onTrackStart',
      operation: () => throw StateError('boom'),
    );

    await tester.pumpWidget(MaterialApp(
      home: PluginHealthPage(pluginManager: manager, sandbox: manager.sandbox),
    ));
    await tester.pump();

    expect(find.textContaining('Unresponsive —'), findsNothing);
    expect(find.byIcon(Icons.hourglass_disabled), findsNothing);
  });

  testWidgets('multiple failing plugins each get their own summary card',
      (tester) async {
    final manager = PluginManager();
    final plugin = _RecordingPlugin();
    manager.register(plugin);
    await manager.initializeAll();

    await manager.sandbox.run(
      pluginId: 'recording',
      pluginName: 'Recording Plugin',
      hook: 'onTrackStart',
      operation: () => throw StateError('boom'),
    );
    await manager.sandbox.run(
      pluginId: 'other_plugin',
      pluginName: 'Other Plugin',
      hook: 'onTrackStart',
      operation: () => throw StateError('boom'),
    );

    await tester.pumpWidget(MaterialApp(
      home: PluginHealthPage(pluginManager: manager, sandbox: manager.sandbox),
    ));
    await tester.pump();

    expect(find.text('Recording Plugin'), findsOneWidget);
    expect(find.text('Other Plugin'), findsOneWidget);
    expect(find.text('Reset'), findsNWidgets(2));
  });
}
