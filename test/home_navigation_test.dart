import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/plugin_interface.dart';
import 'package:omnis/core/plugin_manager.dart';
import 'package:omnis/ui/home_navigation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// A bundled plugin that injects a single declarative `nav_item` at
/// `sidebar_item` — the location `home_navigation.dart` renders after the
/// five fixed destinations. Used for the plain "does it render" checks
/// below, where no real hook call is involved.
class _SidebarItemPlugin extends MusicPlugin {
  @override
  String get id => 'sidebar_plugin';
  @override
  String get name => 'Sidebar Plugin';
  @override
  String get description => 'Injects a sidebar_item nav_item';
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
  dynamic uiSlot(String locationID) => locationID == 'sidebar_item'
      ? const {
          'type': 'nav_item',
          'text': 'Stats',
          'icon': 'history',
          'hook': 'openStats',
        }
      : null;
  @override
  Future<void> dispose() async {}
}

/// Writes a real external (dart_eval) plugin to disk that injects a
/// `nav_item` at `sidebar_item` whose declared `openStats` hook returns a
/// small declarative panel — for proving the *full* tap flow (right hook
/// called, panel it returns actually shown), not just static rendering.
Future<Directory> _writeSidebarItemPlugin(String tempRoot) async {
  final dir = Directory(p.join(tempRoot, 'sidebar_item_plugin'));
  await dir.create(recursive: true);
  await File(p.join(dir.path, 'omnis_plugin.yaml')).writeAsString('''
id: sidebar_item_plugin
name: Sidebar Item Plugin
description: Test plugin
version: 1.0.0
author: Test
entrypoint: plugin.dart
permissions:
''');
  await File(p.join(dir.path, 'plugin.dart')).writeAsString('''
dynamic createPlugin(dynamic api) {
  return {
    'id': 'sidebar_item_plugin',
    'name': 'Sidebar Item Plugin',
    'version': '1.0.0',
    'author': 'Test',
    'hooks': ['uiSlot', 'openStats'],
  };
}

dynamic uiSlot(dynamic locationId) {
  if (locationId != 'sidebar_item') return null;
  return {
    'type': 'nav_item',
    'text': 'Stats',
    'icon': 'history',
    'hook': 'openStats',
  };
}

dynamic openStats(dynamic arg) {
  return [
    {'type': 'text', 'text': 'Plays this week: 42'},
  ];
}
''');
  return dir;
}

const _destinations = [
  HomeDestinationInfo(Icons.home, 'Home'),
  HomeDestinationInfo(Icons.library_music, 'Library'),
  HomeDestinationInfo(Icons.playlist_play, 'Playlist'),
  HomeDestinationInfo(Icons.mood, 'Moods'),
  HomeDestinationInfo(Icons.radio, 'Radio'),
  HomeDestinationInfo(Icons.settings, 'Settings'),
];

Future<void> _pumpAt(
  WidgetTester tester,
  Size size,
  PluginManager manager,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: HomeNavigationBar(
        selectedIndex: 0,
        onDestinationSelected: (_) {},
        pluginManager: manager,
        destinations: _destinations,
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // In-process plugin initialization warms PluginStorage.initialize()
    // (see PluginManager.initPlugin) — a real SharedPreferences.
    // getInstance() platform-channel call with nothing to answer it
    // otherwise, which hangs (not throws) until the test's own timeout —
    // the same standard mock every other file touching PluginStorage/
    // AppSettings already uses (see plugin_system_test.dart's setUp).
    SharedPreferences.setMockInitialValues({});
  });

  group('HomeNavigationBar — responsive choice', () {
    testWidgets(
        'narrower than the breakpoint renders the bottom NavigationBar',
        (tester) async {
      final manager = PluginManager();
      await _pumpAt(tester, const Size(400, 800), manager);

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
    });

    testWidgets('at or above the breakpoint renders a NavigationRail',
        (tester) async {
      final manager = PluginManager();
      await _pumpAt(
          tester, const Size(kNavigationRailBreakpoint, 800), manager);

      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('the five fixed destinations are present in both layouts',
        (tester) async {
      final manager = PluginManager();

      await _pumpAt(tester, const Size(400, 800), manager);
      for (final d in _destinations) {
        expect(find.text(d.label), findsOneWidget);
      }

      final wideManager = PluginManager();
      await _pumpAt(tester, const Size(900, 800), wideManager);
      for (final d in _destinations) {
        expect(find.text(d.label), findsOneWidget);
      }
    });
  });

  group('HomeNavigationBar — sidebar_item plugin slot', () {
    testWidgets(
        "a plugin's uiSlot('sidebar_item') result renders in the bottom "
        'bar at a narrow width', (tester) async {
      final manager = PluginManager();
      manager.register(_SidebarItemPlugin());
      await manager.initializeAll();

      await _pumpAt(tester, const Size(400, 800), manager);

      expect(find.text('Stats'), findsOneWidget);
      expect(find.byIcon(Icons.history), findsOneWidget);
    });

    testWidgets(
        "a plugin's uiSlot('sidebar_item') result renders in the rail at "
        'a wide width', (tester) async {
      final manager = PluginManager();
      manager.register(_SidebarItemPlugin());
      await manager.initializeAll();

      await _pumpAt(tester, const Size(900, 800), manager);

      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.text('Stats'), findsOneWidget);
      expect(find.byIcon(Icons.history), findsOneWidget);
    });

    testWidgets(
        'tapping the injected nav_item calls that exact plugin\'s declared '
        'hook and shows the panel it returns', (tester) async {
      // installFromPath does real dart:io + dart_eval compilation work
      // with genuine async gaps — same reasoning as every other real-I/O
      // test in this codebase's own established convention (see
      // radio_page_test.dart's _settle doc comment): a plain await inside
      // testWidgets' fake-async zone never lets that actually finish;
      // runAsync exits to the real zone for it.
      await tester.runAsync(() async {
        final tempRoot =
            (await Directory.systemTemp.createTemp('omnis_home_nav_test'))
                .path;
        addTearDown(() => Directory(tempRoot).delete(recursive: true));
        final dir = await _writeSidebarItemPlugin(tempRoot);

        final manager = PluginManager();
        await manager.installFromPath(dir.path, sourceUrl: 'local');

        await _pumpAt(tester, const Size(400, 800), manager);
        expect(find.text('Stats'), findsOneWidget);

        await tester.tap(find.text('Stats'));
        await tester.pumpAndSettle();

        // The bottom sheet opened with exactly what `openStats` (and
        // only `openStats` — no other hook was ever declared) returned.
        expect(find.text('Plays this week: 42'), findsOneWidget);
      });
    });
  });
}
