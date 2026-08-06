import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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
