import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/play_history_store.dart';
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

BaseTrack _track(String id) => BaseTrack(
      id: id,
      title: 'Track $id',
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
    // PlayHistoryStore.instance caches its resolved file path for the
    // whole process (same as LibraryStore) — a fresh temp dir per test
    // only matters for the very first test to touch the singleton.
    // Explicitly clearing whatever file is already cached is what
    // actually gives each test a clean slate; the tests below rely on
    // merge (recordPlay/recordPosition read-modify-write), unlike
    // LibraryStore's tests, which only ever call the equivalent of a
    // full overwrite and so never surface this.
    await PlayHistoryStore.instance.clear();
  });

  test('recordPlay creates an entry with playCount 1, then increments on '
      'a repeat play', () async {
    final store = PlayHistoryStore.instance;
    await store.recordPlay(_track('a'));
    var mostPlayed = await store.mostPlayed();
    expect(mostPlayed.single.trackId, 'a');
    expect(mostPlayed.single.playCount, 1);

    await store.recordPlay(_track('a'));
    mostPlayed = await store.mostPlayed();
    expect(mostPlayed.single.playCount, 2);
  });

  test('concurrent recordPlay and recordPosition calls (e.g. a track '
      'change firing both at once) do not lose either update', () async {
    final store = PlayHistoryStore.instance;
    await store.recordPlay(_track('a'));

    // Deliberately not awaited individually — both start before either
    // finishes, the same shape as MainCore's trackStream/onTrackStarted
    // listeners both firing around a track change. Each does its own
    // load-mutate-save cycle; without serializing the whole cycle (not
    // just the final write), whichever save() finished last would
    // silently overwrite the other's update.
    final recordNewPlay = store.recordPlay(_track('b'));
    final recordOldPosition = store.recordPosition(
        'a', const Duration(seconds: 42), const Duration(seconds: 200));

    await Future.wait([recordNewPlay, recordOldPosition]);

    final stats = await store.mostPlayed();
    final byId = {for (final s in stats) s.trackId: s};
    expect(byId.containsKey('b'), isTrue,
        reason: 'recordPlay(b) must not be lost to a racing '
            'recordPosition(a) save');
    expect(byId['a']!.lastPositionSeconds, 42,
        reason: 'recordPosition(a) must not be lost to a racing '
            'recordPlay(b) save');
  });

  test('recordPosition updates an existing entry but is a no-op for a '
      'track never played', () async {
    final store = PlayHistoryStore.instance;
    await store.recordPlay(_track('a'));

    await store.recordPosition('a', const Duration(seconds: 90),
        const Duration(seconds: 200));
    var continueListening = await store.continueListening();
    expect(continueListening.single.trackId, 'a');
    expect(continueListening.single.lastPositionSeconds, 90);

    // 'b' was never recorded via recordPlay — recordPosition must not
    // fabricate a new entry for it.
    await store.recordPosition(
        'b', const Duration(seconds: 90), const Duration(seconds: 200));
    final mostPlayed = await store.mostPlayed();
    expect(mostPlayed.map((s) => s.trackId), ['a']);
  });

  test('recentlyPlayed sorts by lastPlayedAt, most recent first', () async {
    final store = PlayHistoryStore.instance;
    await store.recordPlay(_track('old'));
    await Future.delayed(const Duration(milliseconds: 5));
    await store.recordPlay(_track('new'));

    final recent = await store.recentlyPlayed();
    expect(recent.map((s) => s.trackId).toList(), ['new', 'old']);
  });

  test('mostPlayed sorts by playCount descending', () async {
    final store = PlayHistoryStore.instance;
    await store.recordPlay(_track('once'));
    await store.recordPlay(_track('thrice'));
    await store.recordPlay(_track('thrice'));
    await store.recordPlay(_track('thrice'));

    final most = await store.mostPlayed();
    expect(most.map((s) => s.trackId).toList(), ['thrice', 'once']);
  });

  test('mostPlayed/recentlyPlayed respect the limit parameter', () async {
    final store = PlayHistoryStore.instance;
    for (final id in ['a', 'b', 'c']) {
      await store.recordPlay(_track(id));
    }

    expect(await store.mostPlayed(limit: 2), hasLength(2));
    expect(await store.recentlyPlayed(limit: 1), hasLength(1));
  });

  test(
      'continueListening only includes tracks roughly 10%-90% through, '
      'excludes a track with no duration recorded yet', () async {
    final store = PlayHistoryStore.instance;
    await store.recordPlay(_track('barely_started'));
    await store.recordPosition('barely_started', const Duration(seconds: 5),
        const Duration(seconds: 200)); // 2.5%

    await store.recordPlay(_track('mid'));
    await store.recordPosition(
        'mid', const Duration(seconds: 100), const Duration(seconds: 200)); // 50%

    await store.recordPlay(_track('nearly_done'));
    await store.recordPosition('nearly_done', const Duration(seconds: 195),
        const Duration(seconds: 200)); // 97.5%

    await store.recordPlay(_track('no_position_yet'));
    // recordPosition never called for this one — durationSeconds stays 0.

    final continueListening = await store.continueListening();
    expect(continueListening.map((s) => s.trackId).toList(), ['mid']);
  });

  test('clear removes all persisted history', () async {
    final store = PlayHistoryStore.instance;
    await store.recordPlay(_track('a'));
    expect(await store.mostPlayed(), isNotEmpty);

    await store.clear();
    expect(await store.mostPlayed(), isEmpty);
  });

  test('save() writes atomically — no leftover .tmp file after '
      'recordPlay', () async {
    final store = PlayHistoryStore.instance;
    await store.recordPlay(_track('a'));

    final dir = await PathProviderPlatform.instance.getApplicationDocumentsPath();
    final tmp = File('$dir/omnis_play_history.json.tmp');
    expect(await tmp.exists(), isFalse,
        reason: 'the .tmp file must be renamed away, never left behind');
    final real = File('$dir/omnis_play_history.json');
    expect(await real.exists(), isTrue);
  });

  test('tolerates corrupt JSON on disk', () async {
    final store = PlayHistoryStore.instance;
    await store.recordPlay(_track('a'));
    // Corrupt the file this store actually wrote to, by pulling its path
    // the same way the store computes it.
    final dir = await PathProviderPlatform.instance.getApplicationDocumentsPath();
    final file = File('$dir/omnis_play_history.json');
    await file.writeAsString('not valid json {{{');

    expect(await store.mostPlayed(), isEmpty);
  });

  test('a single malformed stats record among many valid ones is '
      'skipped, not fatal to the rest of the history', () async {
    final dir = await PathProviderPlatform.instance.getApplicationDocumentsPath();
    final file = File('$dir/omnis_play_history.json');
    // TrackPlayStats.fromJson uses DateTime.parse (throws on a bad/absent
    // value) and hard-casts playCount.
    await file.writeAsString(jsonEncode({
      'good_one': {
        'trackId': 'good_one',
        'playCount': 3,
        'lastPlayedAt': DateTime(2024, 1, 1).toIso8601String(),
      },
      'bad': <String, dynamic>{},
      'good_two': {
        'trackId': 'good_two',
        'playCount': 5,
        'lastPlayedAt': DateTime(2024, 1, 2).toIso8601String(),
      },
    }));

    final mostPlayed = await PlayHistoryStore.instance.mostPlayed();

    expect(mostPlayed.map((s) => s.trackId).toSet(), {'good_one', 'good_two'},
        reason: 'the rest of the play history must not be lost over one '
            'bad record');
  });
}
