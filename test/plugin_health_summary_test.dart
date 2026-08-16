import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/plugin_health_summary.dart';
import 'package:omnis/core/sandbox.dart';

PluginHealthRecord _record({
  required String pluginId,
  String pluginName = 'Plugin',
  DateTime? timestamp,
  String reason = 'It failed.',
}) =>
    PluginHealthRecord(
      pluginId: pluginId,
      pluginName: pluginName,
      hook: 'onTrackStart',
      message: 'boom',
      timestamp: timestamp ?? DateTime(2026, 8, 16, 12, 0),
      reason: reason,
    );

void main() {
  final now = DateTime(2026, 8, 16, 12, 0);

  test('an empty record list summarizes to nothing', () {
    expect(summarizeHealth(const [], now: now), isEmpty);
  });

  test('groups records by plugin id into one summary each', () {
    final records = [
      _record(pluginId: 'a', timestamp: now),
      _record(pluginId: 'a', timestamp: now),
      _record(pluginId: 'b', timestamp: now),
    ];

    final summaries = summarizeHealth(records, now: now);

    expect(summaries.map((s) => s.pluginId).toSet(), {'a', 'b'});
    final a = summaries.firstWhere((s) => s.pluginId == 'a');
    expect(a.failureCount, 2);
    final b = summaries.firstWhere((s) => s.pluginId == 'b');
    expect(b.failureCount, 1);
  });

  test('a summary carries the most recent record\'s name/reason', () {
    final records = [
      _record(pluginId: 'a', timestamp: now.subtract(const Duration(minutes: 2)),
          reason: 'Old reason'),
      _record(pluginId: 'a', timestamp: now, reason: 'Latest reason'),
    ];

    final summary = summarizeHealth(records, now: now).single;

    expect(summary.mostRecentReason, 'Latest reason');
    expect(summary.mostRecentFailureAt, now);
  });

  test('recentFailureCount only counts records within the window, '
      'failureCount counts all of them', () {
    final records = [
      _record(pluginId: 'a', timestamp: now.subtract(const Duration(minutes: 1))),
      _record(pluginId: 'a', timestamp: now.subtract(const Duration(minutes: 10))),
    ];

    final summary = summarizeHealth(records,
            now: now, window: const Duration(minutes: 5))
        .single;

    expect(summary.failureCount, 2);
    expect(summary.recentFailureCount, 1);
  });

  test('severity is critical at/above the threshold, degraded below it',
      () {
    final belowThreshold = List.generate(
      4,
      (_) => _record(pluginId: 'a', timestamp: now),
    );
    expect(
      summarizeHealth(belowThreshold, now: now, criticalThreshold: 5)
          .single
          .severity,
      PluginHealthSeverity.degraded,
    );

    final atThreshold = List.generate(
      5,
      (_) => _record(pluginId: 'a', timestamp: now),
    );
    expect(
      summarizeHealth(atThreshold, now: now, criticalThreshold: 5)
          .single
          .severity,
      PluginHealthSeverity.critical,
    );
  });

  test('sorts critical plugins before degraded ones', () {
    final records = [
      _record(pluginId: 'degraded', timestamp: now),
      ...List.generate(
          5, (_) => _record(pluginId: 'critical', timestamp: now)),
    ];

    final summaries =
        summarizeHealth(records, now: now, criticalThreshold: 5);

    expect(summaries.first.pluginId, 'critical');
    expect(summaries.last.pluginId, 'degraded');
  });

  test('within the same severity tier, more recent-window failures sort '
      'first', () {
    final records = [
      _record(pluginId: 'fewer', timestamp: now),
      _record(pluginId: 'more', timestamp: now),
      _record(pluginId: 'more', timestamp: now),
    ];

    final summaries = summarizeHealth(records, now: now);

    expect(summaries.first.pluginId, 'more');
  });

  test('an unrelated plugin\'s records never affect another plugin\'s '
      'summary', () {
    final records = [
      ...List.generate(5, (_) => _record(pluginId: 'noisy', timestamp: now)),
      _record(pluginId: 'quiet', timestamp: now),
    ];

    final quiet = summarizeHealth(records, now: now)
        .firstWhere((s) => s.pluginId == 'quiet');

    expect(quiet.failureCount, 1);
    expect(quiet.severity, PluginHealthSeverity.degraded);
  });
}
