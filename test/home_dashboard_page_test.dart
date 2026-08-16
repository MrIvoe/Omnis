import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/core/audio_engine.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/bootstrap.dart';
import 'package:omnis/core/home_layout_store.dart';
import 'package:omnis/core/library_repository.dart';
import 'package:omnis/core/library_store.dart';
import 'package:omnis/core/main_core.dart';
import 'package:omnis/core/play_history_store.dart';
import 'package:omnis/core/plugin_context.dart';
import 'package:omnis/core/plugin_manager.dart';
import 'package:omnis/ui/home_dashboard_page.dart';
import 'package:omnis/ui/player_layouts/layout_manager.dart';
import 'package:omnis_plugins/favorites_plugin.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String tempDir;
  _FakePathProvider(this.tempDir);

  @override
  Future<String?> getApplicationDocumentsPath() async => tempDir;
}

/// Spies on setQueue/play — the rest is unused by HomeDashboardPage and
/// throws if ever called, same `noSuchMethod` pattern
/// mini_player_bar_test.dart uses.
class _FakeEngine implements AudioEngine {
  List<BaseTrack>? lastQueue;
  int? lastStartIndex;
  bool playCalled = false;

  final _trackController = StreamController<BaseTrack?>.broadcast();

  @override
  Stream<BaseTrack?> get trackStream => _trackController.stream;

  @override
  Future<void> setQueue(List<BaseTrack> tracks, {int startIndex = 0}) async {
    lastQueue = tracks;
    lastStartIndex = startIndex;
  }

  @override
  Future<void> play() async => playCalled = true;

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName} not stubbed');
}

/// pumpAndSettle() pumps frames back-to-back with no real time between
/// them, which never gives HomeDashboardPage's real (fake-path-provider-
/// backed) LibraryStore/PlayHistoryStore reads — real dart:io, real
/// isolates via compute() — a chance to actually finish, even inside
/// tester.runAsync(). An explicit real delay between two pumps does.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await Future<void>.delayed(const Duration(milliseconds: 300));
  await tester.pump();
}

BaseTrack _track(String id, {DateTime? dateAdded}) => BaseTrack(
      id: id,
      title: 'Track $id',
      artists: const ['Artist'],
      album: 'Album',
      duration: 200,
      type: TrackType.local,
      dateAdded: dateAdded,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    final tempDir = (await Directory.systemTemp.createTemp('omnis_test')).path;
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.initialize();
    // Both stores cache their resolved file path for the whole process
    // (see play_history_store_test.dart's setUp for the full reasoning);
    // clearing explicitly is what actually gives each test a clean slate.
    await LibraryStore.instance.clear();
    await PlayHistoryStore.instance.clear();
    await HomeLayoutStore.instance.clear();
    // HomeDashboardPage now reads through LibraryRepository, which caches
    // in memory after its first load() for the whole process (same
    // reasoning as the two stores above, one layer up) — resetting it
    // here is what makes each test's direct LibraryStore.instance.save()
    // fixture actually visible to the page instead of a previous test's
    // cached copy.
    LibraryRepository.instance.resetForTesting();
  });

  // Every test below wraps its body in tester.runAsync(): HomeDashboardPage
  // reads real (fake-path-provider-backed) LibraryStore/PlayHistoryStore
  // singletons from initState onward with no injection point, and
  // testWidgets() otherwise runs in a fake-async zone where a real
  // dart:io Future never resolves through the fake clock — pumpAndSettle
  // just times out waiting for a frame that never comes. runAsync lets
  // real async work actually complete while pumping still works normally.

  testWidgets('shows the empty state when there is no library and no '
      'history', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(
        home: HomeDashboardPage(
            engine: _FakeEngine(), pluginManager: PluginManager()),
      ));
      await _settle(tester);

      expect(find.text('Play some music to see it here.'), findsOneWidget);
    });
  });

  testWidgets(
      'Recently Added renders from library dateAdded, newest first, and '
      'sections with no data are absent', (tester) async {
    await tester.runAsync(() async {
      await LibraryStore.instance.save([
        _track('old', dateAdded: DateTime(2024, 1, 1)),
        _track('new', dateAdded: DateTime(2025, 1, 1)),
      ]);

      await tester.pumpWidget(MaterialApp(
        home: HomeDashboardPage(
            engine: _FakeEngine(), pluginManager: PluginManager()),
      ));
      await _settle(tester);

      expect(find.text('Recently Added'), findsOneWidget);
      expect(find.text('Track new'), findsOneWidget);
      expect(find.text('Track old'), findsOneWidget);
      // Nothing has ever been played or favorited.
      expect(find.text('Recently Played'), findsNothing);
      expect(find.text('Most Played'), findsNothing);
      expect(find.text('Continue Listening'), findsNothing);
      expect(find.text('Favorites'), findsNothing);
      expect(find.text('Most Skipped'), findsNothing);
    });
  });

  testWidgets('Recently Played/Most Played/Continue Listening populate '
      'from PlayHistoryStore joined against the library', (tester) async {
    await tester.runAsync(() async {
      await LibraryStore.instance.save([_track('a'), _track('b')]);
      await PlayHistoryStore.instance.recordPlay(_track('a'));
      await PlayHistoryStore.instance.recordPosition(
          'a', const Duration(seconds: 100), const Duration(seconds: 200));

      await tester.pumpWidget(MaterialApp(
        home: HomeDashboardPage(
            engine: _FakeEngine(), pluginManager: PluginManager()),
      ));
      await _settle(tester);

      expect(find.text('Recently Played'), findsOneWidget);
      expect(find.text('Most Played'), findsOneWidget);
      expect(find.text('Continue Listening'), findsOneWidget);
      // 'b' was never played — must not appear as a card anywhere.
      expect(find.text('Track b'), findsNothing);
    });
  });

  testWidgets('Most Skipped populates from PlayHistoryStore.mostSkipped '
      'joined against the library (item 16, §37 skip tracking)',
      (tester) async {
    await tester.runAsync(() async {
      await LibraryStore.instance.save([_track('a')]);
      for (var i = 0; i < 3; i++) {
        await PlayHistoryStore.instance.recordPlay(_track('a'));
        await PlayHistoryStore.instance.recordTrackEnd('a',
            const Duration(seconds: 5), const Duration(seconds: 200));
      }

      await tester.pumpWidget(MaterialApp(
        home: HomeDashboardPage(
            engine: _FakeEngine(), pluginManager: PluginManager()),
      ));
      await _settle(tester);

      expect(find.text('Most Skipped'), findsOneWidget);
      final skippedCards = find.descendant(
        of: find.byKey(const ValueKey('home_section_Most Skipped')),
        matching: find.text('Track a'),
      );
      expect(skippedCards, findsOneWidget);
    });
  });

  testWidgets('a played track that is not in the scanned library (a '
      'radio station, or anything from a streaming/server plugin) still '
      'shows up in Recently Played/Most Played via its recorded '
      'snapshot — item 41\'s "recorded but never rendered" gap',
      (tester) async {
    await tester.runAsync(() async {
      // Deliberately no LibraryStore.save() at all — the whole point is
      // that this track was never scanned/imported, only played.
      final station = BaseTrack(
        id: 'station-1',
        title: 'MANGORADIO',
        artists: const ['Radio Browser'],
        album: '',
        duration: 0,
        type: TrackType.radio,
        streamUrl: 'https://stream.example/station-1',
      );
      await PlayHistoryStore.instance.recordPlay(station);

      await tester.pumpWidget(MaterialApp(
        home: HomeDashboardPage(
            engine: _FakeEngine(), pluginManager: PluginManager()),
      ));
      await _settle(tester);

      expect(find.text('Recently Played'), findsOneWidget);
      expect(find.text('Most Played'), findsOneWidget);
      expect(find.text('MANGORADIO'), findsWidgets);
    });
  });

  testWidgets('Favorites only appears once FavoritesPlugin is registered '
      'and has a favorite — and picks it up live via FavoriteChangedEvent, '
      'not just on the page\'s first load', (tester) async {
    await tester.runAsync(() async {
      await LibraryStore.instance.save([_track('a')]);
      final engine = _FakeEngine();
      final pluginManager = PluginManager();
      // Real context wiring (matching main_core.dart's), so setFavorite
      // below actually emits FavoriteChangedEvent instead of it being a
      // silent no-op against a plugin with no attached context.
      pluginManager.attachContext(OmnisPluginContext(
        audioEngine: engine,
        services: pluginManager.services,
        events: pluginManager.events,
      ));

      await tester.pumpWidget(MaterialApp(
        home: HomeDashboardPage(engine: engine, pluginManager: pluginManager),
      ));
      await _settle(tester);
      expect(find.text('Favorites'), findsNothing);

      final favorites = FavoritesPlugin();
      pluginManager.register(favorites);
      await favorites.setFavorite('a', true);

      // No second pumpWidget — HomeDashboardPage's State is preserved
      // across HomePage's IndexedStack the same way in the real app, so
      // this exercises the actual live-refresh path (FavoriteChangedEvent
      // -> _load()), not a fresh initState.
      await _settle(tester);
      expect(find.text('Favorites'), findsOneWidget);
    });
  });

  testWidgets(
      'tapping a card sets the queue starting at that track and pushes '
      'Now Playing', (tester) async {
    // NowPlayingPage (what a card push lands on) reads GetIt singletons —
    // same bootstrap approach mini_player_bar_test.dart uses, and for the
    // same reason: MainCore()/LayoutManager()'s bare constructors do no
    // I/O of their own.
    final core = MainCore();
    final layoutManager = LayoutManager();
    locator.registerSingleton<MainCore>(core);
    locator.registerSingleton<AudioEngine>(core.audioEngine);
    locator.registerSingleton<LayoutManager>(layoutManager);
    addTearDown(() async {
      await locator.unregister<AudioEngine>();
      await locator.unregister<MainCore>();
      await locator.unregister<LayoutManager>();
      await layoutManager.dispose();
    });

    await tester.runAsync(() async {
      await LibraryStore.instance.save([_track('a'), _track('b')]);
      await PlayHistoryStore.instance.recordPlay(_track('a'));
      await PlayHistoryStore.instance.recordPlay(_track('b'));
      await PlayHistoryStore.instance.recordPlay(_track('b'));

      final engine = _FakeEngine();
      await tester.pumpWidget(MaterialApp(
        home: HomeDashboardPage(
            engine: engine, pluginManager: PluginManager()),
      ));
      await _settle(tester);

      // Most Played is sorted ['b' (2 plays), 'a' (1 play)] — tap the
      // second card ('a') and confirm the start index matches its
      // position in that section's own list, not just "some track."
      final mostPlayedCards = find.descendant(
        of: find.byKey(const ValueKey('home_section_Most Played')),
        matching: find.byType(InkWell),
      );
      await tester.tap(mostPlayedCards.at(1));
      await _settle(tester);

      expect(engine.lastQueue?.map((t) => t.id).toList(), ['b', 'a']);
      expect(engine.lastStartIndex, 1);
      expect(engine.playCalled, isTrue);
      expect(find.text('Nothing playing — pick a track from the Library.'),
          findsOneWidget);
    });
  });

  group('Customize (item 45)', () {
    testWidgets('the Customize sheet lists every known section, checked '
        'by default when nothing has been saved yet', (tester) async {
      await tester.runAsync(() async {
        await LibraryStore.instance.save([_track('a', dateAdded: DateTime(2025))]);

        await tester.pumpWidget(MaterialApp(
          home: HomeDashboardPage(
              engine: _FakeEngine(), pluginManager: PluginManager()),
        ));
        await _settle(tester);

        await tester.tap(find.byTooltip('Customize'));
        await _settle(tester);

        expect(find.text('Customize Home'), findsOneWidget);
        for (final label in homeSectionCatalog.values) {
          final tile = tester.widget<CheckboxListTile>(
              find.widgetWithText(CheckboxListTile, label));
          expect(tile.value, isTrue, reason: '$label should default to visible');
        }
      });
    });

    testWidgets('unchecking a section and tapping Done hides it on the '
        'dashboard, and the choice survives a reload', (tester) async {
      await tester.runAsync(() async {
        await LibraryStore.instance
            .save([_track('a', dateAdded: DateTime(2025))]);

        await tester.pumpWidget(MaterialApp(
          home: HomeDashboardPage(
              engine: _FakeEngine(), pluginManager: PluginManager()),
        ));
        await _settle(tester);
        expect(find.text('Recently Added'), findsOneWidget);

        await tester.tap(find.byTooltip('Customize'));
        await _settle(tester);
        await tester.pumpAndSettle();
        final recentlyAddedTile =
            find.widgetWithText(CheckboxListTile, 'Recently Added');
        await tester.ensureVisible(recentlyAddedTile);
        await tester.tap(recentlyAddedTile);
        await tester.pump();
        expect(tester.widget<CheckboxListTile>(recentlyAddedTile).value, isFalse,
            reason: 'the checkbox itself should already be unchecked before '
                'Done is even tapped');
        await tester.ensureVisible(find.text('Done'));
        await tester.tap(find.text('Done'));
        await _settle(tester);
        // The sheet's own dismiss animation isn't necessarily complete
        // after just _settle's single pump — while it's still mid-exit,
        // its own "Recently Added" checkbox label would also match the
        // finder below, producing a false pass/fail unrelated to the
        // dashboard's real state.
        await tester.pumpAndSettle();

        expect(find.text('Recently Added'), findsNothing);

        // Confirms this is real persistence, not just in-memory sheet
        // state — a saved layout survives an unrelated reload trigger.
        final saved = await HomeLayoutStore.instance.load();
        expect(
          saved
              .firstWhere((p) => p.sectionId == 'recently_added')
              .visible,
          isFalse,
        );
      });
    });

    testWidgets('"Reset" clears any customization back to the default '
        'order/visibility', (tester) async {
      await tester.runAsync(() async {
        await LibraryStore.instance
            .save([_track('a', dateAdded: DateTime(2025))]);
        await HomeLayoutStore.instance.save(const [
          HomeSectionPreference(sectionId: 'recently_added', visible: false),
        ]);

        await tester.pumpWidget(MaterialApp(
          home: HomeDashboardPage(
              engine: _FakeEngine(), pluginManager: PluginManager()),
        ));
        await _settle(tester);
        expect(find.text('Recently Added'), findsNothing);

        await tester.tap(find.byTooltip('Customize'));
        await _settle(tester);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Reset'));
        await tester.tap(find.text('Reset'));
        await _settle(tester);
        await tester.pumpAndSettle();

        expect(find.text('Recently Added'), findsOneWidget);
        expect(await HomeLayoutStore.instance.load(), isEmpty);
      });
    });

    testWidgets('closing the sheet with no changes made (Done with '
        'nothing toggled) does not write a new save', (tester) async {
      await tester.runAsync(() async {
        await LibraryStore.instance
            .save([_track('a', dateAdded: DateTime(2025))]);

        await tester.pumpWidget(MaterialApp(
          home: HomeDashboardPage(
              engine: _FakeEngine(), pluginManager: PluginManager()),
        ));
        await _settle(tester);

        await tester.tap(find.byTooltip('Customize'));
        await _settle(tester);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Done'));
        await tester.tap(find.text('Done'));
        await _settle(tester);

        expect(await HomeLayoutStore.instance.load(), isEmpty);
      });
    });
  });
}
