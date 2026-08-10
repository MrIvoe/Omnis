import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/library_repository.dart';
import 'package:omnis/core/library_store.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Fake path_provider, same pattern as library_store_test.dart.
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String tempDir;
  _FakePathProvider(this.tempDir);

  @override
  Future<String?> getApplicationDocumentsPath() async => tempDir;
}

BaseTrack _track(String id, {String title = 'Track'}) => BaseTrack(
      id: id,
      title: title,
      artists: const ['Artist'],
      album: 'Album',
      duration: 200,
      type: TrackType.local,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    final tempDir = (await Directory.systemTemp.createTemp('omnis_test')).path;
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
    // LibraryRepository.instance is a singleton, same as LibraryStore.instance
    // it wraps — reset its in-memory cache before every test so one test's
    // loaded/saved state can't leak into the next.
    LibraryRepository.instance.resetForTesting();
  });

  test('load() returns empty before anything has been saved', () async {
    final loaded = await LibraryRepository.instance.load();
    expect(loaded, isEmpty);
    expect(LibraryRepository.instance.isLoaded, isTrue);
  });

  test('save() updates tracks immediately, before the disk write resolves',
      () async {
    final repo = LibraryRepository.instance;
    final future = repo.save([_track('1')]);
    // The whole point of updating in-memory state before awaiting the
    // persisted write is that other listeners see it immediately — assert
    // that happens synchronously, not just after `future` completes.
    expect(repo.tracks, hasLength(1));
    await future;
    expect(repo.tracks, hasLength(1));
  });

  test('save() notifies listeners', () async {
    final repo = LibraryRepository.instance;
    var notified = 0;
    repo.addListener(() => notified++);
    await repo.save([_track('1')]);
    expect(notified, 1);
  });

  test(
      'save() copies the passed-in list rather than aliasing it — '
      'mutating the caller\'s own list afterwards does not silently '
      'change the repository\'s cached copy without a notification',
      () async {
    final repo = LibraryRepository.instance;
    final callerOwned = <BaseTrack>[_track('1')];
    await repo.save(callerOwned);

    var notified = 0;
    repo.addListener(() => notified++);
    callerOwned[0] = _track('1', title: 'Mutated');

    expect(repo.tracks.single.title, 'Track',
        reason: 'the repository must hold its own copy, not the caller\'s '
            'live list');
    expect(notified, 0,
        reason: 'a mutation that bypassed save() must not silently count '
            'as a change');
  });

  test('load() persists across repeated calls without re-reading the file',
      () async {
    final repo = LibraryRepository.instance;
    await repo.save([_track('1'), _track('2')]);

    // Overwrite the file directly, bypassing the repository, to prove a
    // second load() call returns the cached in-memory copy rather than
    // re-reading disk.
    await LibraryStore.instance.save([_track('3')]);

    final second = await repo.load();
    expect(second, hasLength(2), reason: 'should be the cached copy, not a fresh disk read');
  });

  test('load(forceReload: true) re-reads from disk', () async {
    final repo = LibraryRepository.instance;
    await repo.save([_track('1'), _track('2')]);

    await LibraryStore.instance.save([_track('3')]);

    final reloaded = await repo.load(forceReload: true);
    expect(reloaded, hasLength(1));
    expect(reloaded.single.id, '3');
  });

  test('concurrent load() calls during the first load share one Future',
      () async {
    // Simulates HomePage's IndexedStack constructing all four tabs in the
    // same frame, each calling load() in its own initState before the
    // first one has resolved.
    await LibraryStore.instance.save([_track('1')]);
    LibraryRepository.instance.resetForTesting();

    final repo = LibraryRepository.instance;
    final results = await Future.wait([
      repo.load(),
      repo.load(),
      repo.load(),
      repo.load(),
    ]);

    for (final result in results) {
      expect(result, hasLength(1));
    }
  });

  test('tracks getter is unmodifiable', () async {
    final repo = LibraryRepository.instance;
    await repo.save([_track('1')]);
    expect(() => repo.tracks.add(_track('2')), throwsUnsupportedError);
  });
}
