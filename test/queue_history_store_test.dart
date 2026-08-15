import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/queue_history_store.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String tempDir;
  _FakePathProvider(this.tempDir);

  @override
  Future<String?> getApplicationDocumentsPath() async => tempDir;
}

BaseTrack _track(String id, {String title = 'Title', TrackType type = TrackType.local}) =>
    BaseTrack(
      id: id,
      title: title,
      artists: const ['Artist'],
      album: 'Album',
      duration: 180,
      type: type,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late String tempDir;

  setUpAll(() async {
    tempDir =
        (await Directory.systemTemp.createTemp('omnis_queue_history_test'))
            .path;
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
  });

  tearDown(() async {
    await QueueHistoryStore.instance.save([]);
  });

  test('load() returns empty when nothing has ever been saved', () async {
    expect(await QueueHistoryStore.instance.load(), isEmpty);
  });

  test('recordAutoHistory adds a new entry with the real tracks, newest '
      'first', () async {
    await QueueHistoryStore.instance
        .recordAutoHistory([_track('a'), _track('b')]);

    final loaded = await QueueHistoryStore.instance.load();

    expect(loaded, hasLength(1));
    expect(loaded.first.isSnapshot, isFalse);
    expect(loaded.first.tracks.map((t) => t.id), ['a', 'b']);
  });

  test('recordAutoHistory on an empty queue is a no-op', () async {
    await QueueHistoryStore.instance.recordAutoHistory(const []);

    expect(await QueueHistoryStore.instance.load(), isEmpty);
  });

  test('recordAutoHistory does not create a duplicate entry for the same '
      'queue recorded twice in a row (e.g. a reorder round-tripping '
      'through setQueue)', () async {
    await QueueHistoryStore.instance
        .recordAutoHistory([_track('a'), _track('b')]);
    await QueueHistoryStore.instance
        .recordAutoHistory([_track('a'), _track('b')]);

    expect(await QueueHistoryStore.instance.load(), hasLength(1));
  });

  test('recordAutoHistory treats a reordered queue as genuinely '
      'different, not a duplicate', () async {
    await QueueHistoryStore.instance
        .recordAutoHistory([_track('a'), _track('b')]);
    await QueueHistoryStore.instance
        .recordAutoHistory([_track('b'), _track('a')]);

    expect(await QueueHistoryStore.instance.load(), hasLength(2));
  });

  test('auto-history entries are capped at maxAutoHistoryEntries, oldest '
      'evicted first', () async {
    for (var i = 0; i < QueueHistoryStore.maxAutoHistoryEntries + 5; i++) {
      await QueueHistoryStore.instance.recordAutoHistory([_track('t$i')]);
    }

    final loaded = await QueueHistoryStore.instance.load();
    final autos = loaded.where((e) => !e.isSnapshot).toList();

    expect(autos, hasLength(QueueHistoryStore.maxAutoHistoryEntries));
    // The very first recorded queue (t0) should have been evicted.
    expect(autos.any((e) => e.tracks.single.id == 't0'), isFalse);
    // The most recently recorded queue must still be present.
    expect(
        autos.any((e) =>
            e.tracks.single.id == 't${QueueHistoryStore.maxAutoHistoryEntries + 4}'),
        isTrue);
  });

  test('saveSnapshot adds a permanently-named entry that auto-history '
      "eviction never touches", () async {
    await QueueHistoryStore.instance
        .saveSnapshot('Road Trip Mix', [_track('a'), _track('b')]);

    for (var i = 0; i < QueueHistoryStore.maxAutoHistoryEntries + 5; i++) {
      await QueueHistoryStore.instance.recordAutoHistory([_track('t$i')]);
    }

    final loaded = await QueueHistoryStore.instance.load();
    final snapshots = loaded.where((e) => e.isSnapshot).toList();

    expect(snapshots, hasLength(1));
    expect(snapshots.single.name, 'Road Trip Mix');
  });

  test('deleteEntry removes exactly the given entry, leaving the rest '
      'intact', () async {
    await QueueHistoryStore.instance.saveSnapshot('Keep Me', [_track('a')]);
    var entries =
        await QueueHistoryStore.instance.saveSnapshot('Delete Me', [_track('b')]);
    final toDelete = entries.firstWhere((e) => e.name == 'Delete Me');

    final result = await QueueHistoryStore.instance.deleteEntry(toDelete.id);

    expect(result.map((e) => e.name), ['Keep Me']);
  });

  test('a queue containing a non-local (e.g. radio) track round-trips '
      'through a full save/load — full track data is stored, not just '
      'an id that could fail to resolve later', () async {
    final radioTrack = _track('r1', title: 'Live Station', type: TrackType.radio);
    await QueueHistoryStore.instance.recordAutoHistory([radioTrack]);

    final loaded = await QueueHistoryStore.instance.load();

    expect(loaded.single.tracks.single.type, TrackType.radio);
    expect(loaded.single.tracks.single.title, 'Live Station');
  });

  test('tolerates corrupt JSON', () async {
    final f = File('$tempDir/omnis_queue_history.json');
    await f.writeAsString('not valid json {{{');

    expect(await QueueHistoryStore.instance.load(), isEmpty);
  });

  test('a single malformed entry among valid ones is skipped, not fatal '
      'to the rest', () async {
    final f = File('$tempDir/omnis_queue_history.json');
    await f.writeAsString(jsonEncode({
      'schemaVersion': 1,
      'data': [
        {
          'id': 'qh_1',
          'name': null,
          'createdAt': DateTime(2025).toIso8601String(),
          'tracks': [_track('a').toJson()],
        },
        <String, dynamic>{},
        {
          'id': 'qh_2',
          'name': null,
          'createdAt': DateTime(2025).toIso8601String(),
          'tracks': [_track('b').toJson()],
        },
      ],
    }));

    final loaded = await QueueHistoryStore.instance.load();

    expect(loaded.map((e) => e.id).toSet(), {'qh_1', 'qh_2'});
  });

  test('save() writes atomically — no leftover .tmp file', () async {
    await QueueHistoryStore.instance.recordAutoHistory([_track('a')]);

    final tmp = File('$tempDir/omnis_queue_history.json.tmp');
    expect(await tmp.exists(), isFalse);
    final real = File('$tempDir/omnis_queue_history.json');
    expect(await real.exists(), isTrue);
  });
}
