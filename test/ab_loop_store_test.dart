import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/ab_loop_store.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String tempDir;
  _FakePathProvider(this.tempDir);

  @override
  Future<String?> getApplicationDocumentsPath() async => tempDir;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late String tempDir;

  setUpAll(() async {
    tempDir =
        (await Directory.systemTemp.createTemp('omnis_ab_loop_test')).path;
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
  });

  tearDown(() async {
    await AbLoopStore.instance.save([]);
  });

  test('load() returns empty when nothing has ever been saved', () async {
    expect(await AbLoopStore.instance.load(), isEmpty);
  });

  test('add() persists a new loop and returns the updated list', () async {
    final result = await AbLoopStore.instance.add(
      't1',
      'Chorus',
      const Duration(seconds: 30),
      const Duration(seconds: 45),
    );

    expect(result, hasLength(1));
    expect(result.single.trackId, 't1');
    expect(result.single.name, 'Chorus');
    expect(result.single.start, const Duration(seconds: 30));
    expect(result.single.end, const Duration(seconds: 45));

    final loaded = await AbLoopStore.instance.load();
    expect(loaded, hasLength(1));
    expect(loaded.single.name, 'Chorus');
  });

  test('adding a second loop preserves the first, in order', () async {
    await AbLoopStore.instance.add(
        't1', 'First', const Duration(seconds: 0), const Duration(seconds: 10));
    final result = await AbLoopStore.instance.add('t1', 'Second',
        const Duration(seconds: 20), const Duration(seconds: 30));

    expect(result.map((l) => l.name), ['First', 'Second']);
  });

  test('loopsForTrack returns only loops for that track, in order', () async {
    await AbLoopStore.instance.add('t1', 'A loop', const Duration(seconds: 0),
        const Duration(seconds: 10));
    await AbLoopStore.instance.add('t2', 'B loop', const Duration(seconds: 0),
        const Duration(seconds: 10));
    await AbLoopStore.instance.add('t1', 'Another A loop',
        const Duration(seconds: 20), const Duration(seconds: 30));

    final loops = await AbLoopStore.instance.loopsForTrack('t1');

    expect(loops.map((l) => l.name), ['A loop', 'Another A loop']);
  });

  test('loopsForTrack for a track with no saved loops returns empty', () async {
    await AbLoopStore.instance.add('t1', 'A loop', const Duration(seconds: 0),
        const Duration(seconds: 10));

    expect(await AbLoopStore.instance.loopsForTrack('other'), isEmpty);
  });

  test('delete() removes exactly the given loop, leaving the rest', () async {
    await AbLoopStore.instance.add('t1', 'Keep Me', const Duration(seconds: 0),
        const Duration(seconds: 10));
    final entries = await AbLoopStore.instance.add('t1', 'Delete Me',
        const Duration(seconds: 20), const Duration(seconds: 30));
    final toDelete = entries.firstWhere((l) => l.name == 'Delete Me');

    final result = await AbLoopStore.instance.delete(toDelete.id);

    expect(result.map((l) => l.name), ['Keep Me']);
  });

  test('delete() for an unknown id is a harmless no-op', () async {
    await AbLoopStore.instance.add('t1', 'Keep Me', const Duration(seconds: 0),
        const Duration(seconds: 10));

    final result = await AbLoopStore.instance.delete('does-not-exist');

    expect(result, hasLength(1));
  });

  test('tolerates corrupt JSON', () async {
    final f = File('$tempDir/omnis_ab_loops.json');
    await f.writeAsString('not valid json {{{');

    expect(await AbLoopStore.instance.load(), isEmpty);
  });

  test(
      'a single malformed record among many valid ones is skipped, not '
      'fatal to the rest', () async {
    final f = File('$tempDir/omnis_ab_loops.json');
    await f.writeAsString(jsonEncode({
      'schemaVersion': 1,
      'data': [
        {
          'id': 'ab_loop_1',
          'trackId': 't1',
          'name': 'Good One',
          'startMs': 1000,
          'endMs': 2000,
          'createdAt': DateTime(2025).toIso8601String(),
        },
        <String, dynamic>{},
        {
          'id': 'ab_loop_2',
          'trackId': 't1',
          'name': 'Good Two',
          'startMs': 3000,
          'endMs': 4000,
          'createdAt': DateTime(2025).toIso8601String(),
        },
      ],
    }));

    final loaded = await AbLoopStore.instance.load();

    expect(loaded.map((l) => l.name).toSet(), {'Good One', 'Good Two'});
  });

  test('save() writes atomically — no leftover .tmp file', () async {
    await AbLoopStore.instance.add('t1', 'My Loop', const Duration(seconds: 0),
        const Duration(seconds: 10));

    final tmp = File('$tempDir/omnis_ab_loops.json.tmp');
    expect(await tmp.exists(), isFalse);
    final real = File('$tempDir/omnis_ab_loops.json');
    expect(await real.exists(), isTrue);
  });

  test(
      'start/end durations round-trip exactly through millisecond '
      'JSON encoding', () async {
    await AbLoopStore.instance.add(
      't1',
      'Precise',
      const Duration(minutes: 1, seconds: 23, milliseconds: 456),
      const Duration(minutes: 1, seconds: 45, milliseconds: 789),
    );

    final loaded = await AbLoopStore.instance.load();

    expect(loaded.single.start,
        const Duration(minutes: 1, seconds: 23, milliseconds: 456));
    expect(loaded.single.end,
        const Duration(minutes: 1, seconds: 45, milliseconds: 789));
  });
}
