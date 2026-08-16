import 'package:omnis/core/playback_schedule.dart';

/// Pure due-schedule logic for scheduled playback (MusicBee comparison
/// §43). Kept free of `AudioEngine`/`dart:async` so it's fully unit-
/// testable without the deferred injectable-player test seam (item 9)
/// — the caller (`MainCore`'s periodic check) is the thin wrapper that
/// actually starts playback for whatever this returns.
class PlaybackScheduler {
  const PlaybackScheduler._();

  /// Which of [schedules] should fire at [now] — enabled, whose
  /// [PlaybackSchedule.weekdays] includes `now.weekday`, and whose
  /// [PlaybackSchedule.minuteOfDay] exactly matches `now`'s hour/minute.
  ///
  /// [lastFiredAt] (schedule id -> the `DateTime` it last fired) is how a
  /// caller dedups: a schedule that already fired earlier *today* is
  /// skipped even if this is called again within the same matching
  /// minute (e.g. a periodic timer ticking more than once inside it) —
  /// without this, a schedule could fire repeatedly for as long as the
  /// clock sits on its trigger minute.
  static List<PlaybackSchedule> dueSchedules(
    List<PlaybackSchedule> schedules,
    DateTime now,
    Map<String, DateTime> lastFiredAt,
  ) {
    final nowMinuteOfDay = now.hour * 60 + now.minute;
    final due = <PlaybackSchedule>[];
    for (final schedule in schedules) {
      if (!schedule.enabled) continue;
      if (!schedule.weekdays.contains(now.weekday)) continue;
      if (schedule.minuteOfDay != nowMinuteOfDay) continue;
      final lastFired = lastFiredAt[schedule.id];
      if (lastFired != null && _isSameDate(lastFired, now)) continue;
      due.add(schedule);
    }
    return due;
  }

  static bool _isSameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
