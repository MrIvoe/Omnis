import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/plugin_heartbeat_scheduler.dart';

void main() {
  final now = DateTime(2026, 8, 16);

  group('isDue', () {
    test('null lastCheckAt is always due, regardless of interval', () {
      expect(
        PluginHeartbeatScheduler.isDue(
            null, const Duration(minutes: 15), now),
        isTrue,
      );
    });

    test('a check older than the interval is due', () {
      final last = now.subtract(const Duration(minutes: 20));
      expect(
        PluginHeartbeatScheduler.isDue(
            last, const Duration(minutes: 15), now),
        isTrue,
      );
    });

    test('a check within the interval is not due', () {
      final last = now.subtract(const Duration(minutes: 5));
      expect(
        PluginHeartbeatScheduler.isDue(
            last, const Duration(minutes: 15), now),
        isFalse,
      );
    });

    test('exactly at the interval boundary is due — >=, not >', () {
      final last = now.subtract(const Duration(minutes: 15));
      expect(
        PluginHeartbeatScheduler.isDue(
            last, const Duration(minutes: 15), now),
        isTrue,
      );
    });

    test('a check timestamp in the future (clock skew) is not due', () {
      final last = now.add(const Duration(minutes: 1));
      expect(
        PluginHeartbeatScheduler.isDue(
            last, const Duration(minutes: 15), now),
        isFalse,
      );
    });
  });
}
