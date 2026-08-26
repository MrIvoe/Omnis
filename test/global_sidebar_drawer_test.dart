import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/playlist_store.dart';
import 'package:omnis/core/plugin_manager.dart';
import 'package:omnis/core/sidebar_config.dart';
import 'package:omnis/plugin_api/custom_mood.dart';
import 'package:omnis/plugin_api/service_interfaces.dart';
import 'package:omnis/ui/home_navigation.dart';
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

/// Stands in for whichever plugin owns the Moods tab (the bundled
/// `MoodsPlugin`), recording which of [IMoodPlayer]'s two play paths the
/// drawer chose. A fake rather than the real plugin because this suite
/// tests the *drawer's* resolution logic — custom mood first, preset
/// fallback — not the plugin's own queue building, which
/// `Omnis-Plugins`' `moods_plugin_test.dart` covers against its real
/// page.
class _FakeMoodPlayer implements IMoodPlayer {
  final List<CustomMood> _customMoods;

  final List<String> playedPresetMoods = [];
  final List<CustomMood> playedCustomMoods = [];

  _FakeMoodPlayer(this._customMoods);

  @override
  Future<List<CustomMood>> customMoods() async => _customMoods;

  @override
  void playMood(String mood) => playedPresetMoods.add(mood);

  @override
  void playCustomMood(CustomMood custom) => playedCustomMoods.add(custom);
}

/// Supplies preset mood names the same way `SmartPlaylistPlugin`/
/// `QueuePresetPlugin` do — the drawer only ever reads
/// [IQueueBuilder.supportedQueries] from them.
class _FakeQueueBuilder implements IQueueBuilder {
  @override
  final List<String> supportedQueries;

  _FakeQueueBuilder(this.supportedQueries);

  @override
  List<BaseTrack> buildQueueFor(List<BaseTrack> tracks, String query) =>
      const [];
}

/// The core destinations first, then the two Tier 2 extracted them —
/// 'home' (HomeDashboardPlugin) and 'moods' (MoodsPlugin) — appended as
/// the plugin-contributed tabs they now are, since plugin destinations
/// always render after core ones.
const _destinations = [
  HomeDestinationInfo(Icons.library_music, 'Library'),
  HomeDestinationInfo(Icons.playlist_play, 'Playlist'),
  HomeDestinationInfo(Icons.settings, 'Settings'),
  HomeDestinationInfo(Icons.home, 'Home'),
  HomeDestinationInfo(Icons.mood, 'Moods'),
];

/// 1:1 with [_destinations], in the same order — mirrors `home_page.dart`'s
/// own `destinationIds`.
const _destinationIds = ['library', 'playlist', 'settings', 'home', 'moods'];

/// `GlobalSidebarDrawer._load` does real dart:io file reads (via
/// `SidebarConfigStore`/`PlaylistStore`), which never
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
  List<HomeDestinationInfo> destinations = _destinations,
  List<String> destinationIds = _destinationIds,
  ValueChanged<int>? onSelectDestination,
  PluginManager? pluginManager,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: const SizedBox(),
      drawer: GlobalSidebarDrawer(
        pluginManager: pluginManager ?? PluginManager(),
        selectedIndex: selectedIndex,
        destinations: destinations,
        destinationIds: destinationIds,
        playlistKey: GlobalKey<PlaylistPageState>(),
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

      await tester.tap(find.text('Playlist'));
      await _settle(tester);

      expect(selected, 1);
      expect(find.text('MY PLAYLISTS'), findsNothing); // drawer closed
    });
  });

  testWidgets(
      'tapping a pinned playlist resolves the Playlist tab by id, not a '
      'hardcoded index — regression guard for a future core-tab-list '
      'reorder (e.g. removing "home") shifting every subsequent index, '
      'even with plugin destinations appended after the core ones',
      (tester) async {
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

      int? selected;
      // Simulates the post-"remove 'home' from the core id list" world
      // this bug guards against, plus a plugin destination appended
      // after the core ones (plugin destinations always render after
      // core ones per this plan's Tier 0 contract) — 'playlist' sits at
      // index 1 here, not the old hardcoded literal `2`.
      await _pumpDrawer(
        tester,
        destinations: const [
          HomeDestinationInfo(Icons.library_music, 'Library'),
          HomeDestinationInfo(Icons.playlist_play, 'Playlist'),
          HomeDestinationInfo(Icons.mood, 'Moods'),
          HomeDestinationInfo(Icons.settings, 'Settings'),
          HomeDestinationInfo(Icons.extension, 'Sample Plugin Tab'),
        ],
        destinationIds: const [
          'library',
          'playlist',
          'moods',
          'settings',
          'sample_plugin_destination',
        ],
        onSelectDestination: (i) => selected = i,
      );

      await tester.tap(find.text('Road Trip'));
      await _settle(tester);

      expect(selected, 1);
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

  group('Moods reached through IMoodPlayer (Tier 2 task 4 — the Moods tab '
      'is plugin-owned, so this widget can no longer hold a '
      'GlobalKey<MoodsPageState> or read CustomMoodStore directly)', () {
    /// Pins [refIds] into the default "My moods" section, alongside the
    /// default "My playlists" one the drawer always renders.
    Future<void> pinMoods(List<String> refIds) async {
      await SidebarConfigStore.instance.save([
        const SidebarSection(
          id: 'my_playlists',
          title: 'My playlists',
          kind: SidebarItemKind.playlist,
        ),
        SidebarSection(
          id: 'my_moods',
          title: 'My moods',
          kind: SidebarItemKind.mood,
          items: [
            for (final id in refIds)
              SidebarItem(kind: SidebarItemKind.mood, refId: id),
          ],
        ),
      ]);
    }

    PluginManager managerWith({
      _FakeMoodPlayer? moodPlayer,
      List<String> presetMoods = const [],
    }) {
      final manager = PluginManager();
      if (moodPlayer != null) {
        manager.services.register(IMoodPlayer, moodPlayer);
      }
      if (presetMoods.isNotEmpty) {
        manager.services
            .register(IQueueBuilder, _FakeQueueBuilder(presetMoods));
      }
      return manager;
    }

    testWidgets('a custom mood supplied by IMoodPlayer is available to pin '
        'from the My moods section', (tester) async {
      await tester.runAsync(() async {
        final moodPlayer = _FakeMoodPlayer(
            const [CustomMood(id: 'm1', name: 'Late Night Drive')]);
        await _pumpDrawer(tester,
            pluginManager: managerWith(moodPlayer: moodPlayer));

        await tester.tap(find.widgetWithIcon(IconButton, Icons.add).last);
        await _settle(tester);

        expect(find.text('Late Night Drive'), findsOneWidget);
      });
    });

    testWidgets('tapping a pinned custom mood plays it via '
        'IMoodPlayer.playCustomMood, not playMood', (tester) async {
      await tester.runAsync(() async {
        final moodPlayer = _FakeMoodPlayer(
            const [CustomMood(id: 'm1', name: 'Late Night Drive')]);
        await pinMoods(['Late Night Drive']);
        await _pumpDrawer(tester,
            pluginManager: managerWith(moodPlayer: moodPlayer));

        // The pinned mood tile sits below the fold of the default 800x600
        // viewport (drawer header + five destinations + two section
        // headers already fill it), so a bare `tap` would silently miss —
        // same `ensureVisible` the reorder group below already needs.
        await tester.ensureVisible(find.text('Late Night Drive'));
        await _settle(tester);
        await tester.tap(find.text('Late Night Drive'));
        await _settle(tester);

        expect(moodPlayer.playedCustomMoods.map((m) => m.id), ['m1']);
        expect(moodPlayer.playedPresetMoods, isEmpty);
      });
    });

    testWidgets('tapping a pinned preset mood plays it via '
        'IMoodPlayer.playMood', (tester) async {
      await tester.runAsync(() async {
        final moodPlayer = _FakeMoodPlayer(const []);
        await pinMoods(['Chill']);
        await _pumpDrawer(
          tester,
          pluginManager:
              managerWith(moodPlayer: moodPlayer, presetMoods: const ['Chill']),
        );

        await tester.ensureVisible(find.text('Chill'));
        await _settle(tester);
        await tester.tap(find.text('Chill'));
        await _settle(tester);

        expect(moodPlayer.playedPresetMoods, ['Chill']);
        expect(moodPlayer.playedCustomMoods, isEmpty);
      });
    });

    testWidgets('with no Moods-owning plugin registered, a pinned custom '
        'mood is skipped as a stale reference and a pinned preset mood '
        'taps to a no-op rather than crashing', (tester) async {
      await tester.runAsync(() async {
        await pinMoods(['Late Night Drive', 'Chill']);
        // No IMoodPlayer registered — only a preset source, so 'Chill'
        // still resolves to a label while the custom mood cannot.
        await _pumpDrawer(tester,
            pluginManager: managerWith(presetMoods: const ['Chill']));

        expect(find.text('Late Night Drive'), findsNothing);
        expect(find.text('Chill'), findsOneWidget);

        await tester.ensureVisible(find.text('Chill'));
        await _settle(tester);
        await tester.tap(find.text('Chill'));
        await _settle(tester);

        expect(tester.takeException(), isNull);
      });
    });
  });

  group('ReorderMenuButton fallback (Task 6, item task-6/§1)', () {
    Future<void> seedThreePlaylists(WidgetTester tester) async {
      await PlaylistStore.instance.save([
        Playlist(
            id: 'p1', name: 'Alpha', trackIds: const [], createdAt: DateTime(2026)),
        Playlist(
            id: 'p2', name: 'Beta', trackIds: const [], createdAt: DateTime(2026)),
        Playlist(
            id: 'p3', name: 'Gamma', trackIds: const [], createdAt: DateTime(2026)),
      ]);
      await SidebarConfigStore.instance.save([
        const SidebarSection(
          id: 'my_playlists',
          title: 'My playlists',
          kind: SidebarItemKind.playlist,
          items: [
            SidebarItem(kind: SidebarItemKind.playlist, refId: 'p1'),
            SidebarItem(kind: SidebarItemKind.playlist, refId: 'p2'),
            SidebarItem(kind: SidebarItemKind.playlist, refId: 'p3'),
          ],
        ),
        const SidebarSection(
            id: 'my_moods', title: 'My moods', kind: SidebarItemKind.mood),
      ]);
    }

    Future<void> tapReorderMenuItem(
        WidgetTester tester, String rowText, String item) async {
      await tester.ensureVisible(find.text(rowText));
      await _settle(tester);
      final row = find.ancestor(
          of: find.text(rowText), matching: find.byType(ListTile));
      await tester.tap(
          find.descendant(of: row, matching: find.byIcon(Icons.swap_vert)));
      await _settle(tester);
      await tester.tap(find.text(item));
      await _settle(tester);
    }

    testWidgets(
        '"Move down" on the first pinned playlist reorders it exactly like '
        'a real drag would, and persists the new order', (tester) async {
      await tester.runAsync(() async {
        await seedThreePlaylists(tester);
        await _pumpDrawer(tester);

        await tapReorderMenuItem(tester, 'Alpha', 'Move down');

        final saved = await SidebarConfigStore.instance.load();
        final ids = saved
            .firstWhere((s) => s.id == 'my_playlists')
            .items
            .map((i) => i.refId)
            .toList();
        expect(ids, ['p2', 'p1', 'p3']);
      });
    });

    testWidgets(
        '"Move up" on the last pinned playlist reorders it exactly like a '
        'real drag would, and persists the new order', (tester) async {
      await tester.runAsync(() async {
        await seedThreePlaylists(tester);
        await _pumpDrawer(tester);

        await tapReorderMenuItem(tester, 'Gamma', 'Move up');

        final saved = await SidebarConfigStore.instance.load();
        final ids = saved
            .firstWhere((s) => s.id == 'my_playlists')
            .items
            .map((i) => i.refId)
            .toList();
        expect(ids, ['p1', 'p3', 'p2']);
      });
    });

    testWidgets(
        'the first pinned playlist has no "Move up" item, and the last has '
        'no "Move down" item', (tester) async {
      await tester.runAsync(() async {
        await seedThreePlaylists(tester);
        await _pumpDrawer(tester);

        final firstRow = find.ancestor(
            of: find.text('Alpha'), matching: find.byType(ListTile));
        await tester.tap(find.descendant(
            of: firstRow, matching: find.byIcon(Icons.swap_vert)));
        await _settle(tester);
        expect(find.text('Move up'), findsNothing);
        expect(find.text('Move down'), findsOneWidget);
        await tester.tapAt(const Offset(5, 5));
        await _settle(tester);

        await tester.ensureVisible(find.text('Gamma'));
        await _settle(tester);
        final lastRow = find.ancestor(
            of: find.text('Gamma'), matching: find.byType(ListTile));
        await tester.tap(find.descendant(
            of: lastRow, matching: find.byIcon(Icons.swap_vert)));
        await _settle(tester);
        expect(find.text('Move down'), findsNothing);
        expect(find.text('Move up'), findsOneWidget);
      });
    });

    testWidgets(
        'reordering around a mid-list stale reference produces the '
        'correct visible order and leaves the stale entry exactly where '
        'it was (regression: the drag handle and ReorderMenuButton must '
        'agree on rendered-position indexing, and _reorderItem must '
        'translate that back into the full-list splice)', (tester) async {
      await tester.runAsync(() async {
        // 'stale-id' has no matching playlist — _labelFor skips it, so
        // it is never a rendered child of the ReorderableListView, but
        // it does still occupy a real slot in section.items ahead of
        // both real entries. This is exactly the divergence between
        // "position among section.items" and "position among rendered
        // children" that the fixed code must reconcile correctly.
        await PlaylistStore.instance.save([
          Playlist(
              id: 'p1',
              name: 'Alpha',
              trackIds: const [],
              createdAt: DateTime(2026)),
          Playlist(
              id: 'p2',
              name: 'Beta',
              trackIds: const [],
              createdAt: DateTime(2026)),
        ]);
        await SidebarConfigStore.instance.save([
          const SidebarSection(
            id: 'my_playlists',
            title: 'My playlists',
            kind: SidebarItemKind.playlist,
            items: [
              SidebarItem(kind: SidebarItemKind.playlist, refId: 'stale-id'),
              SidebarItem(kind: SidebarItemKind.playlist, refId: 'p1'),
              SidebarItem(kind: SidebarItemKind.playlist, refId: 'p2'),
            ],
          ),
          const SidebarSection(
              id: 'my_moods', title: 'My moods', kind: SidebarItemKind.mood),
        ]);
        await _pumpDrawer(tester);

        // Only Alpha/Beta render — confirms the stale entry is skipped,
        // same as the pre-existing single-stale-item test.
        expect(find.text('Alpha'), findsOneWidget);
        expect(find.text('Beta'), findsOneWidget);

        // "Move down" on Alpha (rendered position 0) should swap Alpha
        // and Beta's relative order — and, since the stale entry can
        // never be rendered or targeted by either index convention,
        // must leave it exactly where it already was (first).
        await tapReorderMenuItem(tester, 'Alpha', 'Move down');

        final saved = await SidebarConfigStore.instance.load();
        final ids = saved
            .firstWhere((s) => s.id == 'my_playlists')
            .items
            .map((i) => i.refId)
            .toList();
        expect(ids, ['stale-id', 'p2', 'p1']);
      });
    });
  });
}
