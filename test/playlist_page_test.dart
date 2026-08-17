import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/audio_engine.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/library_repository.dart';
import 'package:omnis/core/library_store.dart';
import 'package:omnis/core/playlist_folder_store.dart';
import 'package:omnis/core/playlist_store.dart';
import 'package:omnis/core/plugin_manager.dart';
import 'package:omnis/core/queue_operations.dart';
import 'package:omnis/core/queue_rules.dart';
import 'package:omnis/ui/playlist_page.dart';
import 'package:omnis_plugins/smart_playlist_plugin.dart';
import 'package:omnis_plugins/smart_playlist_rule.dart';
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

/// Spies on nothing PlaylistPage's folder features actually need — just
/// enough of the surface it touches in `initState`/`_buildIndex` (the
/// live queue) to not throw, same `noSuchMethod` pattern
/// home_dashboard_page_test.dart's own `_FakeEngine` uses.
class _FakeEngine implements AudioEngine {
  final _trackController = StreamController<BaseTrack?>.broadcast();
  final _queueController = StreamController<List<BaseTrack>>.broadcast();

  List<BaseTrack>? lastQueue;
  bool playCalled = false;

  /// Backs `queue`/`currentIndex` for the queue-reordering tests — a
  /// plain field a test can set directly before pumping, defaulting to
  /// empty/-1 so every pre-existing (non-queue) test is unaffected.
  List<BaseTrack> fakeQueue = const [];
  int fakeCurrentIndex = -1;

  @override
  Stream<BaseTrack?> get trackStream => _trackController.stream;

  @override
  Stream<List<BaseTrack>> get queueStream => _queueController.stream;

  @override
  List<BaseTrack> get queue => fakeQueue;

  @override
  int get currentIndex => fakeCurrentIndex;

  @override
  BaseTrack? get currentTrack =>
      (fakeCurrentIndex >= 0 && fakeCurrentIndex < fakeQueue.length)
          ? fakeQueue[fakeCurrentIndex]
          : null;

  @override
  Future<void> setQueue(List<BaseTrack> tracks, {int startIndex = 0}) async {
    lastQueue = tracks;
  }

  @override
  Future<void> play() async => playCalled = true;

  @override
  Future<void> playAt(int index) async {
    if (index < 0 || index >= fakeQueue.length) return;
    fakeCurrentIndex = index;
  }

  @override
  Future<void> removeTrack(int index) async {
    if (index < 0 || index >= fakeQueue.length) return;
    final wasCurrent = index == fakeCurrentIndex;
    fakeQueue = List.of(fakeQueue)..removeAt(index);
    if (fakeCurrentIndex > index) {
      fakeCurrentIndex--;
    } else if (wasCurrent && fakeCurrentIndex >= fakeQueue.length) {
      fakeCurrentIndex = fakeQueue.length - 1;
    }
  }

  @override
  Future<void> moveTrack(int from, int to) async {
    final (newQueue, newCurrentIndex) =
        QueueOperations.reorder(fakeQueue, fakeCurrentIndex, from, to);
    fakeQueue = newQueue;
    fakeCurrentIndex = newCurrentIndex;
  }

  @override
  Future<void> shuffleRemaining({
    QueueRuleConstraints constraints = QueueRuleConstraints.none,
    bool groupByAlbumArtist = false,
  }) async {
    fakeQueue = QueueOperations.shuffledRemaining(fakeQueue, fakeCurrentIndex,
        constraints: constraints, groupByAlbumArtist: groupByAlbumArtist);
  }

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName} not stubbed');
}

/// Same reasoning as home_dashboard_page_test.dart's `_settle`:
/// PlaylistPage reads real (fake-path-provider-backed) PlaylistStore/
/// PlaylistFolderStore/LibraryRepository singletons from `initState`
/// onward — real dart:io — so a plain `pumpAndSettle()` inside the fake-
/// async test zone never gives that a chance to actually finish.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await Future<void>.delayed(const Duration(milliseconds: 300));
  await tester.pump();
  // Finishes any still-running route transition (a popup menu's open/
  // close scale-fade, a dialog's) — pumpAndSettle advances the fake
  // clock's own frame scheduling, independent of the real-I/O wait
  // above, and without it a tap immediately following one of these
  // opens can land on the barrier behind a not-yet-fully-open menu
  // instead of the menu item itself.
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    final tempDir =
        (await Directory.systemTemp.createTemp('omnis_playlist_page_test'))
            .path;
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
    SharedPreferences.setMockInitialValues({});
    await LibraryStore.instance.clear();
    await PlaylistStore.instance.save([]);
    await PlaylistFolderStore.instance.save(PlaylistFolderData.empty);
    LibraryRepository.instance.resetForTesting();
  });

  Future<void> pumpPage(WidgetTester tester,
      {PluginManager? pluginManager, AudioEngine? engine}) async {
    await tester.pumpWidget(MaterialApp(
      home: PlaylistPage(
        engine: engine ?? _FakeEngine(),
        pluginManager: pluginManager ?? PluginManager(),
      ),
    ));
    await _settle(tester);
  }

  group('Playlist folders (item 13)', () {
    testWidgets(
        'a freshly created playlist shows flat, with no folder section — '
        'zero visual change before any folder exists', (tester) async {
      await tester.runAsync(() async {
        await PlaylistStore.instance.save([
          Playlist(
              id: 'p1',
              name: 'Road Trip',
              trackIds: const [],
              createdAt: DateTime(2025)),
        ]);

        await pumpPage(tester);

        expect(find.text('Road Trip'), findsOneWidget);
        expect(find.text('Unsorted'), findsNothing);
        expect(find.byIcon(Icons.folder_outlined), findsNothing);
      });
    });

    testWidgets('creating a folder and moving a playlist into it groups '
        'the playlist under that folder', (tester) async {
      // A taller-than-default viewport: the default 800x600 test size
      // puts a playlist tile's popup-menu anchor close enough to the
      // bottom edge that the opened menu's own items can render past
      // it — the same sliver-cache-extent-adjacent bug class hit
      // repeatedly elsewhere this session, fixed here by giving the
      // page enough room instead of scrolling around a too-short one.
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        await PlaylistStore.instance.save([
          Playlist(
              id: 'p1',
              name: 'Road Trip',
              trackIds: const [],
              createdAt: DateTime(2025)),
        ]);

        await pumpPage(tester);

        await tester.tap(find.byTooltip('New folder'));
        await _settle(tester);
        await tester.enterText(find.byType(TextField), 'Driving');
        await tester.tap(find.text('Create'));
        await _settle(tester);

        expect(find.textContaining('Driving'), findsOneWidget);
        // Not yet assigned, so still under Unsorted.
        expect(find.text('Unsorted'), findsOneWidget);

        await tester.tap(find.byType(PopupMenuButton<String>).last);
        await _settle(tester);
        await tester.tap(find.text('Move to folder…'));
        await _settle(tester);
        await tester.tap(find.text('Driving'));
        await _settle(tester);

        expect(find.text('Unsorted'), findsNothing,
            reason: 'the only playlist is now inside a folder');
        expect(find.textContaining('Driving (1)'), findsOneWidget);

        final saved = await PlaylistFolderStore.instance.load();
        expect(saved.assignments['p1'], saved.folders.single.id);
      });
    });

    testWidgets('renaming a folder updates its displayed name',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        await PlaylistFolderStore.instance.save(const PlaylistFolderData(
          folders: [PlaylistFolder(id: 'f1', name: 'Old Name')],
          assignments: {},
        ));

        await pumpPage(tester);
        expect(find.textContaining('Old Name'), findsOneWidget);

        await tester.tap(find.byTooltip('Folder options'));
        await _settle(tester);
        await tester.tap(find.text('Rename folder'));
        await _settle(tester);
        await tester.enterText(find.byType(TextField), 'New Name');
        await tester.tap(find.text('Save'));
        await _settle(tester);

        expect(find.textContaining('New Name'), findsOneWidget);
        expect(find.textContaining('Old Name'), findsNothing);

        final saved = await PlaylistFolderStore.instance.load();
        expect(saved.folders.single.name, 'New Name');
      });
    });

    testWidgets(
        'deleting a folder un-assigns its playlists instead of deleting '
        'them', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        await PlaylistStore.instance.save([
          Playlist(
              id: 'p1',
              name: 'Road Trip',
              trackIds: const [],
              createdAt: DateTime(2025)),
        ]);
        await PlaylistFolderStore.instance.save(const PlaylistFolderData(
          folders: [PlaylistFolder(id: 'f1', name: 'Driving')],
          assignments: {'p1': 'f1'},
        ));

        await pumpPage(tester);
        expect(find.text('Road Trip'), findsOneWidget);
        expect(find.textContaining('Driving'), findsOneWidget);

        await tester.tap(find.byTooltip('Folder options'));
        await _settle(tester);
        await tester.tap(find.text('Delete folder'));
        await _settle(tester);
        await tester.tap(find.text('Delete'));
        await _settle(tester);

        expect(find.textContaining('Driving'), findsNothing);
        expect(find.text('Road Trip'), findsOneWidget,
            reason: 'the playlist itself must survive a folder deletion');

        final saved = await PlaylistFolderStore.instance.load();
        expect(saved.folders, isEmpty);
        expect(saved.assignments, isEmpty);
      });
    });

    testWidgets(
        'deleting a playlist that was in a folder cleans up its folder '
        'assignment', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        await PlaylistStore.instance.save([
          Playlist(
              id: 'p1',
              name: 'Road Trip',
              trackIds: const [],
              createdAt: DateTime(2025)),
        ]);
        await PlaylistFolderStore.instance.save(const PlaylistFolderData(
          folders: [PlaylistFolder(id: 'f1', name: 'Driving')],
          assignments: {'p1': 'f1'},
        ));

        await pumpPage(tester);

        await tester.tap(find.byType(PopupMenuButton<String>).last);
        await _settle(tester);
        await tester.tap(find.text('Delete'));
        await _settle(tester);
        await tester.tap(find.text('Delete').last);
        await _settle(tester);

        expect(find.text('Road Trip'), findsNothing);

        final savedFolders = await PlaylistFolderStore.instance.load();
        expect(savedFolders.assignments, isEmpty,
            reason: 'no dangling reference to a now-deleted playlist id');
        expect(savedFolders.folders, hasLength(1),
            reason: 'the folder itself is untouched, just now empty');
      });
    });

    testWidgets('moving a playlist back to "No folder" returns it to '
        'Unsorted', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        await PlaylistStore.instance.save([
          Playlist(
              id: 'p1',
              name: 'Road Trip',
              trackIds: const [],
              createdAt: DateTime(2025)),
        ]);
        await PlaylistFolderStore.instance.save(const PlaylistFolderData(
          folders: [PlaylistFolder(id: 'f1', name: 'Driving')],
          assignments: {'p1': 'f1'},
        ));

        await pumpPage(tester);
        expect(find.text('Unsorted'), findsNothing);

        await tester.tap(find.byType(PopupMenuButton<String>).last);
        await _settle(tester);
        await tester.tap(find.text('Move to folder…'));
        await _settle(tester);
        await tester.tap(find.text('No folder'));
        await _settle(tester);

        expect(find.text('Unsorted'), findsOneWidget);
        expect(find.textContaining('Driving (0)'), findsOneWidget);

        final saved = await PlaylistFolderStore.instance.load();
        expect(saved.assignments, isEmpty);
      });
    });
  });

  group('Smart playlists on the Playlists page (item 42)', () {
    testWidgets(
        'no section appears when the Smart Playlists plugin is not '
        'registered', (tester) async {
      await tester.runAsync(() async {
        final manager = PluginManager();
        await pumpPage(tester, pluginManager: manager);

        expect(find.text('Smart playlists'), findsNothing);
      });
    });

    testWidgets(
        'shows an empty-state message when the plugin is registered but '
        'has no saved rules', (tester) async {
      await tester.runAsync(() async {
        final manager = PluginManager();
        manager.register(SmartPlaylistPlugin());
        await pumpPage(tester, pluginManager: manager);

        expect(find.text('Smart playlists'), findsOneWidget);
        expect(find.textContaining('No smart playlists yet'), findsOneWidget);
      });
    });

    testWidgets('lists a saved rule by name with its match-type/condition '
        'summary', (tester) async {
      await tester.runAsync(() async {
        final plugin = SmartPlaylistPlugin();
        await plugin.saveRule(const SmartPlaylistRule(
          id: 'r1',
          name: 'Rock Favorites',
          matchType: RuleMatchType.all,
          conditions: [
            RuleCondition(
                field: RuleField.genre,
                operator: RuleOperator.equals,
                value: 'rock'),
          ],
        ));
        final manager = PluginManager();
        manager.register(plugin);
        await pumpPage(tester, pluginManager: manager);

        expect(find.text('Rock Favorites'), findsOneWidget);
        expect(find.text('ALL of 1 condition'), findsOneWidget);
      });
    });

    testWidgets(
        'tapping a rule builds its queue from the current library and '
        'plays it', (tester) async {
      await tester.runAsync(() async {
        await LibraryStore.instance.save([
          BaseTrack(
            id: 't1',
            title: 'Song',
            artists: const ['Artist'],
            album: 'Album',
            duration: 180,
            genres: const ['rock'],
            type: TrackType.local,
          ),
        ]);
        LibraryRepository.instance.resetForTesting();

        final plugin = SmartPlaylistPlugin();
        await plugin.saveRule(const SmartPlaylistRule(
          id: 'r1',
          name: 'Rock Favorites',
          matchType: RuleMatchType.all,
          conditions: [
            RuleCondition(
                field: RuleField.genre,
                operator: RuleOperator.equals,
                value: 'rock'),
          ],
        ));
        final manager = PluginManager();
        manager.register(plugin);
        final engine = _FakeEngine();
        await pumpPage(tester, pluginManager: manager, engine: engine);

        await tester.tap(find.text('Rock Favorites'));
        await _settle(tester);

        expect(engine.lastQueue?.map((t) => t.id), ['t1']);
        expect(engine.playCalled, isTrue);
      });
    });

    testWidgets('deleting a rule removes it from the list and from the '
        'plugin\'s own persistence', (tester) async {
      await tester.runAsync(() async {
        final plugin = SmartPlaylistPlugin();
        await plugin.saveRule(const SmartPlaylistRule(
          id: 'r1',
          name: 'Rock Favorites',
          matchType: RuleMatchType.all,
          conditions: [
            RuleCondition(
                field: RuleField.genre,
                operator: RuleOperator.equals,
                value: 'rock'),
          ],
        ));
        final manager = PluginManager();
        manager.register(plugin);
        await pumpPage(tester, pluginManager: manager);
        expect(find.text('Rock Favorites'), findsOneWidget);

        await tester.tap(find.byTooltip('Delete'));
        await _settle(tester);

        expect(find.text('Rock Favorites'), findsNothing);
        expect(plugin.savedRules, isEmpty);
      });
    });
  });

  group('Queue actions (item 2)', () {
    BaseTrack track(String id) => BaseTrack(
          id: id,
          title: 'Song $id',
          artists: const ['Artist'],
          album: 'Album',
          duration: 180,
          type: TrackType.local,
        );

    testWidgets('the queue-actions menu offers all four actions',
        (tester) async {
      await tester.runAsync(() async {
        final engine = _FakeEngine()
          ..fakeQueue = [track('a'), track('b')]
          ..fakeCurrentIndex = 0;
        await pumpPage(tester, engine: engine);

        await tester.tap(find.text('Current queue'));
        await _settle(tester);
        await tester.tap(find.byTooltip('Queue actions'));
        await _settle(tester);

        expect(find.text('Save as snapshot'), findsOneWidget);
        expect(find.text('Save as playlist'), findsOneWidget);
        expect(find.text('Remove duplicates'), findsOneWidget);
        expect(find.text('Clear played'), findsOneWidget);
        expect(find.text('Shuffle remaining'), findsOneWidget);
      });
    });

    testWidgets('"Remove duplicates" drops the later occurrence and keeps '
        'the currently-playing track', (tester) async {
      await tester.runAsync(() async {
        final engine = _FakeEngine()
          ..fakeQueue = [track('a'), track('b'), track('a')]
          ..fakeCurrentIndex = 0;
        await pumpPage(tester, engine: engine);

        await tester.tap(find.text('Current queue'));
        await _settle(tester);
        await tester.tap(find.byTooltip('Queue actions'));
        await _settle(tester);
        await tester.tap(find.text('Remove duplicates'));
        await _settle(tester);

        expect(engine.queue.map((t) => t.id), ['a', 'b']);
      });
    });

    testWidgets('"Clear played" removes everything before the current '
        'track', (tester) async {
      await tester.runAsync(() async {
        final engine = _FakeEngine()
          ..fakeQueue = [track('a'), track('b'), track('c')]
          ..fakeCurrentIndex = 2;
        await pumpPage(tester, engine: engine);

        await tester.tap(find.text('Current queue'));
        await _settle(tester);
        await tester.tap(find.byTooltip('Queue actions'));
        await _settle(tester);
        await tester.tap(find.text('Clear played'));
        await _settle(tester);

        expect(engine.queue.map((t) => t.id), ['c']);
      });
    });

    testWidgets('"Save as playlist" persists the live queue as a real '
        'Playlist via PlaylistStore', (tester) async {
      await tester.runAsync(() async {
        final engine = _FakeEngine()..fakeQueue = [track('a'), track('b')];
        await pumpPage(tester, engine: engine);

        await tester.tap(find.text('Current queue'));
        await _settle(tester);
        await tester.tap(find.byTooltip('Queue actions'));
        await _settle(tester);
        await tester.tap(find.text('Save as playlist'));
        await _settle(tester);
        await tester.enterText(find.byType(TextField), 'From Queue');
        await tester.tap(find.text('Save'));
        await _settle(tester);

        final saved = await PlaylistStore.instance.load();
        expect(saved.single.name, 'From Queue');
        expect(saved.single.trackIds, ['a', 'b']);
      });
    });

    testWidgets('"Shuffle remaining" leaves the current track\'s position '
        'and identity untouched', (tester) async {
      await tester.runAsync(() async {
        final engine = _FakeEngine()
          ..fakeQueue = [track('a'), track('b'), track('c')]
          ..fakeCurrentIndex = 0;
        await pumpPage(tester, engine: engine);

        await tester.tap(find.text('Current queue'));
        await _settle(tester);
        await tester.tap(find.byTooltip('Queue actions'));
        await _settle(tester);
        await tester.tap(find.text('Shuffle remaining'));
        await _settle(tester);

        expect(engine.queue.first.id, 'a');
        expect(engine.queue.map((t) => t.id).toSet(), {'a', 'b', 'c'});
      });
    });

    testWidgets('"Move to top" on a non-first track reorders the live '
        'queue via AudioEngine.moveTrack', (tester) async {
      await tester.runAsync(() async {
        final engine = _FakeEngine()
          ..fakeQueue = [track('a'), track('b'), track('c')]
          ..fakeCurrentIndex = 0;
        await pumpPage(tester, engine: engine);

        await tester.tap(find.text('Current queue'));
        await _settle(tester);
        await tester.tap(find.byTooltip('Move to top').last);
        await _settle(tester);

        expect(engine.queue.map((t) => t.id).first, isNot('a'));
        expect(engine.queue.map((t) => t.id).toSet(), {'a', 'b', 'c'});
      });
    });

    testWidgets('the currently-playing track has no "Move to top" action, '
        'since it is meaningless at any real position other than the '
        'front', (tester) async {
      await tester.runAsync(() async {
        final engine = _FakeEngine()
          ..fakeQueue = [track('a'), track('b')]
          ..fakeCurrentIndex = 0;
        await pumpPage(tester, engine: engine);

        await tester.tap(find.text('Current queue'));
        await _settle(tester);

        expect(find.byTooltip('Move to top'), findsOneWidget,
            reason: 'only the second (non-front) track gets the action');
      });
    });
  });

  group('CSV/JSON playlist export (item 13, §46)', () {
    testWidgets('the playlist row menu offers Export as CSV/JSON alongside '
        'the existing M3U/PLS/XSPF entries', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        await PlaylistStore.instance.save([
          Playlist(
              id: 'p1',
              name: 'Road Trip',
              trackIds: const [],
              createdAt: DateTime(2025)),
        ]);

        await pumpPage(tester);
        await tester.tap(find.byType(PopupMenuButton<String>).last);
        await _settle(tester);

        expect(find.text('Export as CSV'), findsOneWidget);
        expect(find.text('Export as JSON'), findsOneWidget);
        // The three pre-existing formats are still there, unreplaced.
        expect(find.text('Export as M3U'), findsOneWidget);
        expect(find.text('Export as PLS'), findsOneWidget);
        expect(find.text('Export as XSPF'), findsOneWidget);
      });
    });

    testWidgets('the playlist detail view\'s AppBar menu also offers '
        'Export as CSV/JSON', (tester) async {
      await tester.runAsync(() async {
        await PlaylistStore.instance.save([
          Playlist(
              id: 'p1',
              name: 'Road Trip',
              trackIds: const [],
              createdAt: DateTime(2025)),
        ]);

        await pumpPage(tester);
        await tester.tap(find.text('Road Trip'));
        await _settle(tester);
        await tester.tap(find.byType(PopupMenuButton<String>).last);
        await _settle(tester);

        expect(find.text('Export as CSV'), findsOneWidget);
        expect(find.text('Export as JSON'), findsOneWidget);
      });
    });
  });
}
