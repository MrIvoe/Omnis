import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/library_store.dart';
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
    LibraryStore.instance.resetForTesting();
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

  test('a single malformed track record among many valid ones is skipped, '
      'not fatal to the whole library', () async {
    final store = LibraryStore.instance;
    final dir = Directory(tempDir);
    final f = File('${dir.path}/omnis_library.json');
    // Two well-formed tracks and one missing every required field
    // (BaseTrack.fromJson hard-casts id/title/duration/type and throws).
    await f.writeAsString(jsonEncode([
      {
        'id': '1',
        'title': 'Good One',
        'artists': ['A'],
        'album': 'Al',
        'duration': 10,
        'genres': [],
        'type': 'local',
      },
      <String, dynamic>{},
      {
        'id': '2',
        'title': 'Good Two',
        'artists': ['A'],
        'album': 'Al',
        'duration': 20,
        'genres': [],
        'type': 'local',
      },
    ]));

    final loaded = await store.load();

    expect(loaded.map((t) => t.title).toSet(), {'Good One', 'Good Two'},
        reason: 'the whole library must not revert to empty over one bad '
            'record');
  });

  test('save() writes atomically — no leftover .tmp file, and the real '
      'file is only ever the old or new complete content', () async {
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

    final tmp = File('$tempDir/omnis_library.json.tmp');
    expect(await tmp.exists(), isFalse,
        reason: 'the .tmp file must be renamed away, never left behind');
    final real = File('$tempDir/omnis_library.json');
    expect(await real.exists(), isTrue);
    expect(await store.load(), hasLength(1));
  });

  test(
      'save() debounces rapid successive calls into a single write of the '
      'latest tracks, and every caller\'s Future resolves once that '
      'write actually happens', () async {
    final store = LibraryStore.instance;
    BaseTrack track(String id) => BaseTrack(
          id: id,
          title: 'T$id',
          artists: const ['A'],
          album: 'Al',
          duration: 10,
          type: TrackType.local,
        );

    final first = store.save([track('1')]);
    final second = store.save([track('2')]);
    final third = store.save([track('3')]);

    // All three share one debounced write — none of them should resolve
    // (and nothing should be on disk yet) before that write actually runs.
    var firstResolved = false;
    unawaited(first.then((_) => firstResolved = true));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(firstResolved, isFalse,
        reason: 'the debounce window (500ms) has not elapsed yet');

    await Future.wait([first, second, third]);

    final loaded = await store.load();
    expect(loaded, hasLength(1),
        reason: 'only the latest snapshot is ever actually written, not '
            'all three');
    expect(loaded.single.id, '3');
  });
}
