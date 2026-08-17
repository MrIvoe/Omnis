import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/playback_schedule.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String tempDir;
  _FakePathProvider(this.tempDir);

  @override
  Future<String?> getApplicationDocumentsPath() async => tempDir;
}

PlaybackSchedule _schedule(String id, {String name = 'Morning'}) =>
    PlaybackSchedule(
      id: id,
      name: name,
      minuteOfDay: 450,
      weekdays: const {1, 2, 3, 4, 5},
      enabled: true,
      createdAt: DateTime(2026, 1, 1),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late String tempDir;

  setUpAll(() async {
    tempDir = (await Directory.systemTemp.createTemp('omnis_schedule_test'))
        .path;
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
  });

  tearDown(() async {
    await PlaybackScheduleStore.instance.save([]);
  });

  test('load() returns empty when nothing has ever been saved', () async {
    expect(await PlaybackScheduleStore.instance.load(), isEmpty);
  });

  test('add() persists a new schedule and returns the updated list',
      () async {
    final result = await PlaybackScheduleStore.instance.add(_schedule('s1'));

    expect(result, hasLength(1));
    expect(result.single.name, 'Morning');
    expect(result.single.minuteOfDay, 450);
    expect(result.single.weekdays, {1, 2, 3, 4, 5});

    final loaded = await PlaybackScheduleStore.instance.load();
    expect(loaded, hasLength(1));
  });

  test('adding a second schedule preserves the first, in order', () async {
    await PlaybackScheduleStore.instance.add(_schedule('a', name: 'First'));
    final result =
        await PlaybackScheduleStore.instance.add(_schedule('b', name: 'Second'));

    expect(result.map((s) => s.name), ['First', 'Second']);
  });

  test('update() replaces the schedule with matching id, leaving the '
      'rest untouched', () async {
    await PlaybackScheduleStore.instance.add(_schedule('a', name: 'Keep'));
    await PlaybackScheduleStore.instance.add(_schedule('b', name: 'Old Name'));

    final updated = _schedule('b', name: 'New Name').copyWith(enabled: false);
    final result = await PlaybackScheduleStore.instance.update(updated);

    expect(result.map((s) => s.name), ['Keep', 'New Name']);
    expect(result.firstWhere((s) => s.id == 'b').enabled, isFalse);
  });

  test('update() for an unknown id is a harmless no-op', () async {
    await PlaybackScheduleStore.instance.add(_schedule('a'));

    final result = await PlaybackScheduleStore.instance
        .update(_schedule('does-not-exist'));

    expect(result, hasLength(1));
  });

  test('delete() removes exactly the given schedule, leaving the rest',
      () async {
    await PlaybackScheduleStore.instance.add(_schedule('a', name: 'Keep Me'));
    await PlaybackScheduleStore.instance.add(_schedule('b', name: 'Delete Me'));

    final result = await PlaybackScheduleStore.instance.delete('b');

    expect(result.map((s) => s.name), ['Keep Me']);
  });

  test('delete() for an unknown id is a harmless no-op', () async {
    await PlaybackScheduleStore.instance.add(_schedule('a'));

    final result = await PlaybackScheduleStore.instance.delete('nope');

    expect(result, hasLength(1));
  });

  test('tolerates corrupt JSON', () async {
    final f = File('$tempDir/omnis_playback_schedules.json');
    await f.writeAsString('not valid json {{{');

    expect(await PlaybackScheduleStore.instance.load(), isEmpty);
  });

  test('a single malformed record among many valid ones is skipped, not '
      'fatal to the rest', () async {
    final f = File('$tempDir/omnis_playback_schedules.json');
    await f.writeAsString(jsonEncode({
      'schemaVersion': 1,
      'data': [
        {
          'id': 's1',
          'name': 'Good One',
          'minuteOfDay': 450,
          'weekdays': [1, 2, 3],
          'enabled': true,
          'createdAt': DateTime(2025).toIso8601String(),
        },
        <String, dynamic>{},
        {
          'id': 's2',
          'name': 'Good Two',
          'minuteOfDay': 600,
          'weekdays': [6, 7],
          'enabled': false,
          'createdAt': DateTime(2025).toIso8601String(),
        },
      ],
    }));

    final loaded = await PlaybackScheduleStore.instance.load();

    expect(loaded.map((s) => s.name).toSet(), {'Good One', 'Good Two'});
  });

  test('save() writes atomically — no leftover .tmp file', () async {
    await PlaybackScheduleStore.instance.add(_schedule('a'));

    final tmp = File('$tempDir/omnis_playback_schedules.json.tmp');
    expect(await tmp.exists(), isFalse);
    final real = File('$tempDir/omnis_playback_schedules.json');
    expect(await real.exists(), isTrue);
  });

  test('playlistId round-trips when set, and is omitted (not written as '
      'null) when absent', () async {
    final withPlaylist =
        _schedule('a').copyWith(playlistId: 'playlist_1');
    await PlaybackScheduleStore.instance.add(withPlaylist);
    await PlaybackScheduleStore.instance.add(_schedule('b'));

    final loaded = await PlaybackScheduleStore.instance.load();

    expect(loaded.firstWhere((s) => s.id == 'a').playlistId, 'playlist_1');
    expect(loaded.firstWhere((s) => s.id == 'b').playlistId, isNull);
  });

  test('copyWith clearPlaylistId actually clears it, distinct from '
      'passing null (which keeps the existing value)', () async {
    final schedule = _schedule('a').copyWith(playlistId: 'playlist_1');

    final unchanged = schedule.copyWith();
    final cleared = schedule.copyWith(clearPlaylistId: true);

    expect(unchanged.playlistId, 'playlist_1');
    expect(cleared.playlistId, isNull);
  });

  group('radioStationId (item 50, "scheduled radio")', () {
    test('round-trips when set, and is omitted (not written as null) '
        'when absent', () async {
      final withStation =
          _schedule('a').copyWith(radioStationId: 'station_1');
      await PlaybackScheduleStore.instance.add(withStation);
      await PlaybackScheduleStore.instance.add(_schedule('b'));

      final loaded = await PlaybackScheduleStore.instance.load();

      expect(
          loaded.firstWhere((s) => s.id == 'a').radioStationId, 'station_1');
      expect(loaded.firstWhere((s) => s.id == 'b').radioStationId, isNull);
    });

    test('a legacy record persisted before this field existed decodes as '
        'null, not a throw — additive field, not a breaking one',
        () async {
      final file = File('$tempDir/omnis_playback_schedules.json');
      await file.writeAsString(jsonEncode({
        'schemaVersion': 1,
        'data': [
          {
            'id': 'legacy',
            'name': 'Legacy',
            'minuteOfDay': 450,
            'weekdays': [1, 2, 3, 4, 5],
            'enabled': true,
            'createdAt': DateTime(2024, 1, 1).toIso8601String(),
          },
        ],
      }));

      final loaded = await PlaybackScheduleStore.instance.load();

      expect(loaded.single.radioStationId, isNull);
    });

    test('copyWith clearRadioStationId actually clears it, distinct from '
        'passing null (which keeps the existing value)', () async {
      final schedule = _schedule('a').copyWith(radioStationId: 'station_1');

      final unchanged = schedule.copyWith();
      final cleared = schedule.copyWith(clearRadioStationId: true);

      expect(unchanged.radioStationId, 'station_1');
      expect(cleared.radioStationId, isNull);
    });

    test('a hand-constructed record with both playlistId and '
        'radioStationId set round-trips both faithfully — the model '
        'itself stays permissive, precedence is a MainCore concern, not '
        'a model-level one', () async {
      final schedule = _schedule('a')
          .copyWith(playlistId: 'playlist_1', radioStationId: 'station_1');
      await PlaybackScheduleStore.instance.add(schedule);

      final loaded = await PlaybackScheduleStore.instance.load();

      expect(loaded.single.playlistId, 'playlist_1');
      expect(loaded.single.radioStationId, 'station_1');
    });
  });

  group('PlaybackScheduleAction (item 50, "stop playback at a time")', () {
    test('a fresh PlaybackSchedule defaults to action: play', () {
      expect(_schedule('a').action, PlaybackScheduleAction.play);
    });

    test('action round-trips through toJson/fromJson for both values',
        () async {
      await PlaybackScheduleStore.instance
          .add(_schedule('a').copyWith(action: PlaybackScheduleAction.stop));
      await PlaybackScheduleStore.instance
          .add(_schedule('b').copyWith(action: PlaybackScheduleAction.play));

      final loaded = await PlaybackScheduleStore.instance.load();

      expect(loaded.firstWhere((s) => s.id == 'a').action,
          PlaybackScheduleAction.stop);
      expect(loaded.firstWhere((s) => s.id == 'b').action,
          PlaybackScheduleAction.play);
    });

    test('a legacy record persisted before the action field existed '
        'decodes as play, not a throw — additive field, not a breaking '
        'one', () async {
      final file = File('$tempDir/omnis_playback_schedules.json');
      await file.writeAsString(jsonEncode({
        'schemaVersion': 1,
        'data': [
          {
            'id': 'legacy',
            'name': 'Legacy',
            'minuteOfDay': 450,
            'weekdays': [1, 2, 3, 4, 5],
            'enabled': true,
            'createdAt': DateTime(2024, 1, 1).toIso8601String(),
          },
        ],
      }));

      final loaded = await PlaybackScheduleStore.instance.load();

      expect(loaded.single.action, PlaybackScheduleAction.play);
    });

    test('copyWith(action: ...) updates only the action, leaving every '
        'other field untouched', () {
      final schedule = _schedule('a').copyWith(playlistId: 'playlist_1');
      final stopped = schedule.copyWith(action: PlaybackScheduleAction.stop);

      expect(stopped.action, PlaybackScheduleAction.stop);
      expect(stopped.name, schedule.name);
      expect(stopped.minuteOfDay, schedule.minuteOfDay);
      expect(stopped.playlistId, schedule.playlistId);
    });
  });
}
