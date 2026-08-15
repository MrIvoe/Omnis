import 'dart:convert';
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

  test('a single malformed playlist record among many valid ones is '
      'skipped, not fatal to every other playlist', () async {
    final f = File('$tempDir/omnis_playlists.json');
    // Playlist.fromJson hard-casts id/name and throws when missing.
    await f.writeAsString(jsonEncode([
      {
        'id': 'p1',
        'name': 'Good One',
        'trackIds': <String>[],
        'createdAt': 1000,
      },
      <String, dynamic>{},
      {
        'id': 'p2',
        'name': 'Good Two',
        'trackIds': <String>[],
        'createdAt': 2000,
      },
    ]));

    final loaded = await PlaylistStore.instance.load();

    expect(loaded.map((p) => p.name).toSet(), {'Good One', 'Good Two'},
        reason: 'every other playlist must not be lost over one bad '
            'record');
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

  group('PLS export/import (item 13)', () {
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

    test('exportPLS writes local tracks and skips the rest, with the '
        'standard [playlist]/File/Title/Length/NumberOfEntries/Version '
        'shape', () {
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

      final result = PlaylistStore.instance.exportPLS(playlist, tracks);

      expect(result.writtenCount, 2);
      expect(result.skippedCount, 2);
      expect(result.content, startsWith('[playlist]\n'));
      expect(result.content, contains('File1=/music/a_file.mp3'));
      expect(result.content, contains('Title1=Ava - Sunrise'));
      expect(result.content, contains('Length1=200'));
      expect(result.content, contains('File2=/music/c_file.mp3'));
      expect(result.content, contains('Title2=Bo - Dusk'));
      expect(result.content, contains('NumberOfEntries=2'));
      expect(result.content, contains('Version=2'));
      expect(result.content, isNot(contains('b_file')));
    });

    test('importPLS matches by exact path, then by filename fallback',
        () async {
      final tracks = [
        track('a'), // localPath: /music/a_file.mp3
        track('b'), // localPath: /music/b_file.mp3
      ];
      const content = '''
[playlist]
File1=/music/a_file.mp3
Title1=Artist - Title
Length1=200
File2=/some/other/machine/path/b_file.mp3
Title2=Artist - Title
Length2=200
File3=/does/not/exist.mp3
Title3=Artist - Title
Length3=200
NumberOfEntries=3
Version=2
''';

      final result = PlaylistStore.instance
          .importPLS(content, tracks, name: 'Imported');

      expect(result.matchedCount, 2);
      expect(result.skippedCount, 1);
      expect(result.playlist.name, 'Imported');
      expect(result.playlist.trackIds, ['a', 'b']);
    });

    test('importPLS ignores Title/Length/NumberOfEntries/Version lines, '
        'the [playlist] header, and blank lines — only File lines are '
        'read', () async {
      final tracks = [track('a')];
      const content = '''
[playlist]
File1=/music/a_file.mp3
Title1=Should not be read as a file
Length1=200

NumberOfEntries=1
Version=2
''';

      final result =
          PlaylistStore.instance.importPLS(content, tracks, name: 'X');

      expect(result.matchedCount, 1);
      expect(result.playlist.trackIds, ['a']);
    });

    test('importPLS is case-insensitive on the File keyword — real-world '
        'PLS files aren\'t perfectly consistent about capitalization',
        () async {
      final tracks = [track('a')];
      const content = 'file1=/music/a_file.mp3\n';

      final result =
          PlaylistStore.instance.importPLS(content, tracks, name: 'X');

      expect(result.matchedCount, 1);
    });

    test('malformed lines are skipped, not fatal', () async {
      final tracks = [track('a')];
      const content = '''
[playlist]
not a valid PLS line at all
File1=/music/a_file.mp3
=missing key
NumberOfEntries=1
''';

      final result =
          PlaylistStore.instance.importPLS(content, tracks, name: 'X');

      expect(result.matchedCount, 1);
      expect(result.playlist.trackIds, ['a']);
    });

    test('a round trip through export then import recovers the same '
        'tracks', () async {
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

      final exported = PlaylistStore.instance.exportPLS(original, tracks);
      final imported = PlaylistStore.instance
          .importPLS(exported.content, tracks, name: 'Mix (imported)');

      expect(imported.matchedCount, 2);
      expect(imported.skippedCount, 0);
      expect(imported.playlist.trackIds, ['a', 'c']);
    });
  });

  group('XSPF export/import (item 13)', () {
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

    test('exportXSPF writes local tracks and skips the rest, with the '
        'standard XSPF playlist/trackList/track shape (duration in '
        'milliseconds)', () {
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

      final result = PlaylistStore.instance.exportXSPF(playlist, tracks);

      expect(result.writtenCount, 2);
      expect(result.skippedCount, 2);
      expect(result.content, contains('<playlist version="1"'));
      expect(result.content, contains('<trackList>'));
      expect(result.content, contains('<location>file:///music/a_file.mp3</location>'));
      expect(result.content, contains('<title>Sunrise</title>'));
      expect(result.content, contains('<creator>Ava</creator>'));
      expect(result.content, contains('<duration>200000</duration>'));
      expect(result.content, contains('file:///music/c_file.mp3'));
      expect(result.content, isNot(contains('b_file')));
    });

    test('exportXSPF escapes XML-significant characters in title/creator',
        () {
      final tracks = [track('a', artist: 'AT&T <Band>', title: 'Rock & "Roll"')];
      final playlist = Playlist(
        id: 'p1',
        name: 'Mix',
        trackIds: const ['a'],
        createdAt: DateTime.now(),
      );

      final result = PlaylistStore.instance.exportXSPF(playlist, tracks);

      expect(result.content, contains('<title>Rock &amp; &quot;Roll&quot;</title>'));
      expect(result.content, contains('<creator>AT&amp;T &lt;Band&gt;</creator>'));
    });

    test('importXSPF resolves <location> file:// URIs back to a matching '
        'track', () async {
      final tracks = [track('a')]; // localPath: /music/a_file.mp3
      const content = '''
<?xml version="1.0" encoding="UTF-8"?>
<playlist version="1" xmlns="http://xspf.org/ns/0/">
  <trackList>
    <track>
      <location>file:///music/a_file.mp3</location>
      <title>Title</title>
      <creator>Artist</creator>
      <duration>200000</duration>
    </track>
  </trackList>
</playlist>
''';

      final result = PlaylistStore.instance
          .importXSPF(content, tracks, name: 'Imported');

      expect(result.matchedCount, 1);
      expect(result.skippedCount, 0);
      expect(result.playlist.name, 'Imported');
      expect(result.playlist.trackIds, ['a']);
    });

    test('importXSPF falls back to filename matching for a location that '
        "doesn't line up exactly, and skips one that matches nothing at "
        'all', () async {
      final tracks = [
        track('a'), // localPath: /music/a_file.mp3
        track('b'), // localPath: /music/b_file.mp3
      ];
      const content = '''
<playlist version="1" xmlns="http://xspf.org/ns/0/">
  <trackList>
    <track><location>file:///music/a_file.mp3</location></track>
    <track><location>file:///some/other/machine/path/b_file.mp3</location></track>
    <track><location>file:///does/not/exist.mp3</location></track>
  </trackList>
</playlist>
''';

      final result = PlaylistStore.instance
          .importXSPF(content, tracks, name: 'Imported');

      expect(result.matchedCount, 2);
      expect(result.skippedCount, 1);
      expect(result.playlist.trackIds, ['a', 'b']);
    });

    test('importXSPF also accepts a bare (non-URI) path in <location>, not '
        'just a real file:// URI', () async {
      final tracks = [track('a')];
      const content = '<playlist><trackList><track>'
          '<location>/music/a_file.mp3</location>'
          '</track></trackList></playlist>';

      final result =
          PlaylistStore.instance.importXSPF(content, tracks, name: 'X');

      expect(result.matchedCount, 1);
    });

    test('importXSPF unescapes XML entities in <location> before matching',
        () async {
      final tracks = [
        BaseTrack(
          id: 'a',
          title: 'T',
          artists: const ['Artist'],
          album: 'Album',
          duration: 200,
          type: TrackType.local,
          localPath: '/music/a & b.mp3',
        ),
      ];
      const content = '<playlist><trackList><track>'
          '<location>file:///music/a%20&amp;%20b.mp3</location>'
          '</track></trackList></playlist>';

      final result =
          PlaylistStore.instance.importXSPF(content, tracks, name: 'X');

      expect(result.matchedCount, 1);
    });

    test('malformed/incomplete XML around a <location> element does not '
        'prevent finding the ones that are well-formed', () async {
      final tracks = [track('a')];
      const content = '<playlist><trackList>'
          '<track><unclosed-tag<location>file:///music/a_file.mp3</location></track>'
          '</trackList></playlist>';

      final result =
          PlaylistStore.instance.importXSPF(content, tracks, name: 'X');

      expect(result.matchedCount, 1);
    });

    test('a round trip through export then import recovers the same '
        'tracks', () async {
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

      final exported = PlaylistStore.instance.exportXSPF(original, tracks);
      final imported = PlaylistStore.instance
          .importXSPF(exported.content, tracks, name: 'Mix (imported)');

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

  group('schema versioning (item 4)', () {
    test('a legacy pre-versioning file (a bare JSON array) still loads '
        'correctly', () async {
      final store = PlaylistStore.instance;
      final f = File('$tempDir/omnis_playlists.json');
      await f.writeAsString(jsonEncode([
        {
          'id': 'legacy',
          'name': 'Legacy Playlist',
          'trackIds': ['t1'],
          'createdAt':
              DateTime.fromMillisecondsSinceEpoch(0).toIso8601String(),
        },
      ]));

      final loaded = await store.load();

      expect(loaded.single.name, 'Legacy Playlist');
    });

    test('save() writes the new versioned envelope shape, not a bare '
        'array', () async {
      final store = PlaylistStore.instance;
      await store.save([
        Playlist(
          id: 'p1',
          name: 'Versioned',
          trackIds: const ['a'],
          createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        ),
      ]);

      final raw = await File('$tempDir/omnis_playlists.json').readAsString();
      final decoded = jsonDecode(raw);

      expect(decoded, isA<Map>());
      expect(decoded['schemaVersion'], isA<int>());
      expect(decoded['data'], isA<List>());
    });
  });
}
