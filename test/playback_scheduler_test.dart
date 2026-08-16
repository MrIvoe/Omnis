import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/playback_schedule.dart';
import 'package:omnis/core/playback_scheduler.dart';

PlaybackSchedule _schedule({
  String id = 's1',
  String name = 'Morning',
  int minuteOfDay = 450,
  Set<int> weekdays = const {1, 2, 3, 4, 5},
  bool enabled = true,
  String? playlistId,
}) =>
    PlaybackSchedule(
      id: id,
      name: name,
      minuteOfDay: minuteOfDay,
      weekdays: weekdays,
      enabled: enabled,
      playlistId: playlistId,
      createdAt: DateTime(2026, 1, 1),
    );

void main() {
  group('dueSchedules', () {
    test('fires when weekday and exact minute match', () {
      // 2026-08-17 is a Monday.
      final now = DateTime(2026, 8, 17, 7, 30);
      final schedules = [_schedule(minuteOfDay: 450, weekdays: const {1})];

      final due = PlaybackScheduler.dueSchedules(schedules, now, {});

      expect(due.map((s) => s.id), ['s1']);
    });

    test('does not fire on a day not in weekdays', () {
      // 2026-08-18 is a Tuesday.
      final now = DateTime(2026, 8, 18, 7, 30);
      final schedules = [_schedule(minuteOfDay: 450, weekdays: const {1})];

      expect(PlaybackScheduler.dueSchedules(schedules, now, {}), isEmpty);
    });

    test('does not fire a minute early or a minute late', () {
      final schedules = [_schedule(minuteOfDay: 450, weekdays: const {1})];

      expect(
          PlaybackScheduler.dueSchedules(
              schedules, DateTime(2026, 8, 17, 7, 29), {}),
          isEmpty);
      expect(
          PlaybackScheduler.dueSchedules(
              schedules, DateTime(2026, 8, 17, 7, 31), {}),
          isEmpty);
    });

    test('a disabled schedule never fires', () {
      final now = DateTime(2026, 8, 17, 7, 30);
      final schedules = [
        _schedule(minuteOfDay: 450, weekdays: const {1}, enabled: false)
      ];

      expect(PlaybackScheduler.dueSchedules(schedules, now, {}), isEmpty);
    });

    test('an empty weekdays set never fires — explicit opt-in, not '
        '"every day"', () {
      final now = DateTime(2026, 8, 17, 7, 30);
      final schedules = [_schedule(minuteOfDay: 450, weekdays: const {})];

      expect(PlaybackScheduler.dueSchedules(schedules, now, {}), isEmpty);
    });

    test('a schedule that already fired earlier today does not fire '
        'again, even at the same matching minute', () {
      final now = DateTime(2026, 8, 17, 7, 30);
      final schedules = [_schedule(minuteOfDay: 450, weekdays: const {1})];
      final lastFiredAt = {'s1': DateTime(2026, 8, 17, 7, 30)};

      expect(PlaybackScheduler.dueSchedules(schedules, now, lastFiredAt),
          isEmpty);
    });

    test('a schedule that fired on a previous day fires again today', () {
      final now = DateTime(2026, 8, 17, 7, 30);
      final schedules = [
        _schedule(minuteOfDay: 450, weekdays: const {1, 2, 3, 4, 5, 6, 7})
      ];
      final lastFiredAt = {'s1': DateTime(2026, 8, 10, 7, 30)};

      expect(PlaybackScheduler.dueSchedules(schedules, now, lastFiredAt)
          .map((s) => s.id), ['s1']);
    });

    test('multiple schedules due at once are all returned', () {
      final now = DateTime(2026, 8, 17, 7, 30);
      final schedules = [
        _schedule(id: 'a', minuteOfDay: 450, weekdays: const {1}),
        _schedule(id: 'b', minuteOfDay: 450, weekdays: const {1}),
        _schedule(id: 'c', minuteOfDay: 600, weekdays: const {1}),
      ];

      final due = PlaybackScheduler.dueSchedules(schedules, now, {});

      expect(due.map((s) => s.id).toSet(), {'a', 'b'});
    });

    test('midnight (minuteOfDay 0) is matched correctly', () {
      final now = DateTime(2026, 8, 17, 0, 0);
      final schedules = [_schedule(minuteOfDay: 0, weekdays: const {1})];

      expect(PlaybackScheduler.dueSchedules(schedules, now, {})
          .map((s) => s.id), ['s1']);
    });

    test('an empty schedule list returns empty', () {
      expect(
          PlaybackScheduler.dueSchedules(const [], DateTime(2026, 8, 17), {}),
          isEmpty);
    });
  });
}
