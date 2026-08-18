import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/custom_mood.dart';
import 'package:omnis/core/playlist_store.dart';
import 'package:omnis/core/plugin_manager.dart';
import 'package:omnis/core/sidebar_config.dart';
import 'package:omnis/ui/home_navigation.dart';
import 'package:omnis/ui/home_page.dart' show MoodsPageState;
import 'package:omnis/ui/playlist_page.dart';
import 'package:omnis/ui/widgets/global_sidebar_drawer.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String tempDir;

  _FakePathProvider(this.tempDir);

  @override
  Future<String?> getApplicationDocumentsPath() async => tempDir;

  @override
  Future<String?> getApplicationSupportPath() async => tempDir;

  @override
  Future<String?> getTemporaryPath() async => tempDir;
}

const _destinations = [
  HomeDestinationInfo(Icons.home, 'Home'),
  HomeDestinationInfo(Icons.library_music, 'Library'),
  HomeDestinationInfo(Icons.playlist_play, 'Playlist'),
  HomeDestinationInfo(Icons.mood, 'Moods'),
  HomeDestinationInfo(Icons.settings, 'Settings'),
];

/// `GlobalSidebarDrawer._load` does real dart:io file reads (via
/// `SidebarConfigStore`/`PlaylistStore`/`CustomMoodStore`), which never
/// actually complete inside `testWidgets`' fake-async zone — the same
/// established bug class this codebase already works around elsewhere
/// (see `online_page_test.dart`/`home_navigation_test.dart`'s own
/// `tester.runAsync` doc comments). Every test below wraps its whole body
/// in `tester.runAsync` for exactly that reason.
///
/// `tester.pump()` alone, even inside `runAsync`, never lets
/// `GlobalSidebarDrawer._load`'s real file reads actually complete —
/// root-caused during this feature's own build: `runAsync` runs *this
/// callback's own* code in the real zone, but a widget's `initState`-
/// triggered async work still executes under `TestWidgetsFlutterBinding`'s
/// own fake-clock-bound zone regardless of the caller's zone, so a bare
/// `pump(fakeDuration)` never actually drains the real `dart:io` event
/// queue those reads are waiting on — confirmed via a file-based trace
/// (print output is unreliably buffered by the test runner) showing the
/// drawer's `CircularProgressIndicator` never clearing across 10 pumps of
/// 100ms fake time each. Interleaving a real `Future.delayed` between
/// pumps does let the real I/O callbacks fire (proven the same way,
/// content appearing from the very next pump on) — this is a different,
/// stronger case than the "wrap the whole call in runAsync" fix
/// `online_page_test.dart`/`home_navigation_test.dart` already established
/// for a *test-initiated* real I/O call; here the real I/O is initiated
/// by the widget's own `initState`, which needs this extra real-delay
/// nudge on top.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pumpDrawer(
  WidgetTester tester, {
  int selectedIndex = 0,
  ValueChanged<int>? onSelectDestination,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: const SizedBox(),
      drawer: GlobalSidebarDrawer(
        pluginManager: PluginManager(),
        selectedIndex: selectedIndex,
        destinations: _destinations,
        playlistKey: GlobalKey<PlaylistPageState>(),
        moodsKey: GlobalKey<MoodsPageState>(),
        onSelectDestination: onSelectDestination ?? (_) {},
      ),
    ),
  ));
  tester.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
  await _settle(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final tempDir =
        (await Directory.systemTemp.createTemp('omnis_sidebar_drawer_test'))
            .path;
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
    SidebarConfigStore.instance.resetForTesting();
    CustomMoodStore.instance.resetForTesting();
    // PlaylistStore has no resetForTesting (matches this codebase's own
    // established convention — see playlist_page_test.dart's identical
    // setUp): its cached file handle sticks across tests in this file,
    // but every test below explicitly saves fresh content before
    // reading, so that staleness never affects a test's own assertions.
    await PlaylistStore.instance.save(const []);
  });

  testWidgets('renders the fixed destinations and the default section '
      'titles', (tester) async {
    await tester.runAsync(() async {
      await _pumpDrawer(tester);

      for (final d in _destinations) {
        expect(find.text(d.label), findsOneWidget);
      }
      expect(find.text('MY PLAYLISTS'), findsOneWidget);
      expect(find.text('MY MOODS'), findsOneWidget);
    });
  });

  testWidgets('tapping a destination closes the drawer and calls '
      'onSelectDestination', (tester) async {
    await tester.runAsync(() async {
      int? selected;
      await _pumpDrawer(tester, onSelectDestination: (i) => selected = i);

      await tester.tap(find.text('Library'));
      await _settle(tester);

      expect(selected, 1);
      expect(find.text('MY PLAYLISTS'), findsNothing); // drawer closed
    });
  });

  testWidgets('adding a playlist to My playlists persists it and shows it '
      'in the drawer', (tester) async {
    await tester.runAsync(() async {
      await PlaylistStore.instance.save([
        Playlist(
            id: 'p1',
            name: 'Road Trip',
            trackIds: const [],
            createdAt: DateTime(2026)),
      ]);
      await _pumpDrawer(tester);

      await tester.tap(find.widgetWithIcon(IconButton, Icons.add).first);
      await _settle(tester);
      expect(find.text('Road Trip'), findsOneWidget);

      await tester.tap(find.text('Road Trip'));
      await _settle(tester);

      final saved = await SidebarConfigStore.instance.load();
      final playlistsSection =
          saved.firstWhere((s) => s.id == 'my_playlists');
      expect(playlistsSection.items.single.refId, 'p1');
    });
  });

  testWidgets('removing a pinned item persists the removal', (tester) async {
    await tester.runAsync(() async {
      await PlaylistStore.instance.save([
        Playlist(
            id: 'p1',
            name: 'Road Trip',
            trackIds: const [],
            createdAt: DateTime(2026)),
      ]);
      await SidebarConfigStore.instance.save([
        const SidebarSection(
          id: 'my_playlists',
          title: 'My playlists',
          kind: SidebarItemKind.playlist,
          items: [SidebarItem(kind: SidebarItemKind.playlist, refId: 'p1')],
        ),
        const SidebarSection(
            id: 'my_moods', title: 'My moods', kind: SidebarItemKind.mood),
      ]);
      await _pumpDrawer(tester);
      expect(find.text('Road Trip'), findsOneWidget);

      await tester.tap(find.widgetWithIcon(IconButton, Icons.close));
      await _settle(tester);

      expect(find.text('Road Trip'), findsNothing);
      final saved = await SidebarConfigStore.instance.load();
      expect(saved.firstWhere((s) => s.id == 'my_playlists').items, isEmpty);
    });
  });

  testWidgets('a stale reference (referenced playlist since deleted) is '
      'skipped, not shown as a broken entry', (tester) async {
    await tester.runAsync(() async {
      await PlaylistStore.instance.save(const []); // p1 no longer exists
      await SidebarConfigStore.instance.save([
        const SidebarSection(
          id: 'my_playlists',
          title: 'My playlists',
          kind: SidebarItemKind.playlist,
          items: [SidebarItem(kind: SidebarItemKind.playlist, refId: 'p1')],
        ),
        const SidebarSection(
            id: 'my_moods', title: 'My moods', kind: SidebarItemKind.mood),
      ]);
      await _pumpDrawer(tester);

      // Every fixed destination + the two section-header ListTiles ("MY
      // PLAYLISTS"/"MY MOODS") + zero item tiles (the one saved item is a
      // stale reference, skipped rather than rendered).
      expect(find.byType(ListTile), findsNWidgets(_destinations.length + 2));
    });
  });

  testWidgets('a custom mood is available to pin from the My moods section',
      (tester) async {
    await tester.runAsync(() async {
      await CustomMoodStore.instance
          .save(const [CustomMood(id: 'm1', name: 'Late Night Drive')]);
      await _pumpDrawer(tester);

      await tester.tap(find.widgetWithIcon(IconButton, Icons.add).last);
      await _settle(tester);

      expect(find.text('Late Night Drive'), findsOneWidget);
    });
  });
}
