import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/library_store.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Fake path_provider that returns a temp directory so LibraryStore can
/// write/read its JSON file in tests.
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

  setUp(() async {
    tempDir = (await Directory.systemTemp.createTemp('omnis_test')).path;
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
  });

  test('LibraryStore saves and reloads tracks', () async {
    final store = LibraryStore.instance;

    // Initially empty.
    expect(await store.load(), isEmpty);

    final tracks = [
      BaseTrack(
        id: 'local:/music/song1.mp3',
        title: 'Song One',
        artists: const ['Artist A'],
        album: 'Album X',
        duration: 180,
        type: TrackType.local,
        localPath: '/music/song1.mp3',
      ),
      BaseTrack(
        id: 'youtube:abc123',
        title: 'Stream Song',
        artists: const ['Artist B'],
        album: 'Album Y',
        duration: 240,
        type: TrackType.youtube,
        streamUrl: 'https://example.com/stream',
      ),
    ];

    await store.save(tracks);

    final loaded = await store.load();
    expect(loaded, hasLength(2));
    expect(loaded[0].title, 'Song One');
    expect(loaded[0].localPath, '/music/song1.mp3');
    expect(loaded[1].type, TrackType.youtube);
    expect(loaded[1].streamUrl, 'https://example.com/stream');
  });

  test('LibraryStore clear removes persisted tracks', () async {
    final store = LibraryStore.instance;
    await store.save([
      BaseTrack(
        id: '1',
        title: 'T',
        artists: const ['A'],
        album: 'Al',
        duration: 10,
        type: TrackType.local,
      ),
    ]);
    expect(await store.load(), hasLength(1));

    await store.clear();
    expect(await store.load(), isEmpty);
  });

  test('LibraryStore tolerates corrupt JSON', () async {
    final store = LibraryStore.instance;
    // Write garbage to the file directly.
    final dir = Directory(tempDir);
    final f = File('${dir.path}/omnis_library.json');
    await f.writeAsString('not valid json {{{');

    expect(await store.load(), isEmpty);
  });
}
