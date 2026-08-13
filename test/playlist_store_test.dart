import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/playlist_store.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Fake path_provider that returns a temp directory, same pattern as
/// library_store_test.dart.
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late String tempDir;

  // PlaylistStore.instance caches its resolved file path for the whole
  // process after the first load()/save() call — same as LibraryStore.
  // Resolving path_provider once in setUpAll (not per-test) keeps every
  // test in this file pointed at the one real file/directory the cache
  // will actually use; tearDown resets its content between tests instead
  // of relying on a fresh tempDir each test would need but the cache
  // wouldn't pick up.
  setUpAll(() async {
    tempDir =
        (await Directory.systemTemp.createTemp('omnis_playlist_test')).path;
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
  });

  tearDown(() async {
    await PlaylistStore.instance.save([]);
  });

  test('PlaylistStore saves and reloads playlists, preserving track order', () async {
    final store = PlaylistStore.instance;

    expect(await store.load(), isEmpty);

    final playlists = [
      Playlist(
        id: 'p1',
        name: 'Road Trip',
        trackIds: const ['t3', 't1', 't2'],
        createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
      ),
      Playlist(
        id: 'p2',
        name: 'Chill',
        trackIds: const [],
        createdAt: DateTime.fromMillisecondsSinceEpoch(2000),
      ),
    ];

    await store.save(playlists);

    final loaded = await store.load();
    expect(loaded, hasLength(2));
    expect(loaded[0].name, 'Road Trip');
    expect(loaded[0].trackIds, ['t3', 't1', 't2']);
    expect(loaded[1].trackIds, isEmpty);
  });

  test('PlaylistStore tolerates corrupt JSON', () async {
    final f = File('$tempDir/omnis_playlists.json');
    await f.writeAsString('not valid json {{{');

    expect(await PlaylistStore.instance.load(), isEmpty);
  });

  test('save() writes atomically — no leftover .tmp file, and the real '
      'file always has the latest complete content', () async {
    await PlaylistStore.instance.save([
      Playlist(
        id: 'p1',
        name: 'Road Trip',
        trackIds: const ['t1'],
        createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
      ),
    ]);

    final tmp = File('$tempDir/omnis_playlists.json.tmp');
    expect(await tmp.exists(), isFalse,
        reason: 'the .tmp file must be renamed away, never left behind');
    final real = File('$tempDir/omnis_playlists.json');
    expect(await real.exists(), isTrue);
    expect(await PlaylistStore.instance.load(), hasLength(1));
  });

  group('M3U export/import', () {
    BaseTrack track(String id,
            {String artist = 'Artist',
            String title = 'Title',
            bool local = true}) =>
        BaseTrack(
          id: id,
          title: title,
          artists: [artist],
          album: 'Album',
          duration: 200,
          type: local ? TrackType.local : TrackType.youtube,
          localPath: local ? '/music/${id}_file.mp3' : null,
        );

    test('exportM3U writes local tracks and skips the rest', () {
      final tracks = [
        track('a', artist: 'Ava', title: 'Sunrise'),
        track('b', local: false),
        track('c', artist: 'Bo', title: 'Dusk'),
      ];
      final playlist = Playlist(
        id: 'p1',
        name: 'Mix',
        trackIds: const ['a', 'b', 'c', 'missing'],
        createdAt: DateTime.now(),
      );

      final result = PlaylistStore.instance.exportM3U(playlist, tracks);

      expect(result.writtenCount, 2);
      expect(result.skippedCount, 2);
      expect(result.content, startsWith('#EXTM3U\n'));
      expect(result.content, contains('#EXTINF:200,Ava - Sunrise'));
      expect(result.content, contains('/music/a_file.mp3'));
      expect(result.content, contains('#EXTINF:200,Bo - Dusk'));
      expect(result.content, contains('/music/c_file.mp3'));
      expect(result.content, isNot(contains('b_file')));
    });

    test('importM3U matches by exact path, then by filename fallback',
        () async {
      final tracks = [
        track('a'), // localPath: /music/a_file.mp3
        track('b'), // localPath: /music/b_file.mp3
      ];
      const content = '''
#EXTM3U
#EXTINF:200,Artist - Title
/music/a_file.mp3
#EXTINF:200,Artist - Title
/some/other/machine/path/b_file.mp3
/does/not/exist.mp3
''';

      final result = PlaylistStore.instance
          .importM3U(content, tracks, name: 'Imported');

      expect(result.matchedCount, 2);
      expect(result.skippedCount, 1);
      expect(result.playlist.name, 'Imported');
      expect(result.playlist.trackIds, ['a', 'b']);
    });

    test('importM3U ignores comments and blank lines', () async {
      final tracks = [track('a')];
      const content = '#EXTM3U\n\n# a comment\n\n/music/a_file.mp3\n';

      final result =
          PlaylistStore.instance.importM3U(content, tracks, name: 'X');

      expect(result.matchedCount, 1);
      expect(result.playlist.trackIds, ['a']);
    });

    test('a round trip through export then import recovers the same tracks',
        () async {
      final tracks = [
        track('a', artist: 'Ava', title: 'Sunrise'),
        track('c', artist: 'Bo', title: 'Dusk'),
      ];
      final original = Playlist(
        id: 'p1',
        name: 'Mix',
        trackIds: const ['a', 'c'],
        createdAt: DateTime.now(),
      );

      final exported = PlaylistStore.instance.exportM3U(original, tracks);
      final imported = PlaylistStore.instance
          .importM3U(exported.content, tracks, name: 'Mix (imported)');

      expect(imported.matchedCount, 2);
      expect(imported.skippedCount, 0);
      expect(imported.playlist.trackIds, ['a', 'c']);
    });
  });

  test('Playlist.copyWith replaces only the given fields', () {
    final playlist = Playlist(
      id: 'p1',
      name: 'Original',
      trackIds: const ['a'],
      createdAt: DateTime.fromMillisecondsSinceEpoch(0),
    );

    final renamed = playlist.copyWith(name: 'Renamed');
    expect(renamed.name, 'Renamed');
    expect(renamed.trackIds, ['a']);
    expect(renamed.id, 'p1');

    final reordered = playlist.copyWith(trackIds: ['b', 'a']);
    expect(reordered.name, 'Original');
    expect(reordered.trackIds, ['b', 'a']);
  });
}
