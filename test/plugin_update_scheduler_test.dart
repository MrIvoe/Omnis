import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/plugin_update_scheduler.dart';

void main() {
  final now = DateTime(2026, 8, 16);

  group('isDue', () {
    test('null lastCheckAt is always due, regardless of interval', () {
      expect(
        PluginUpdateScheduler.isDue(null, const Duration(days: 365), now),
        isTrue,
      );
    });

    test('a check older than the interval is due', () {
      final last = now.subtract(const Duration(days: 4));
      expect(
        PluginUpdateScheduler.isDue(last, const Duration(days: 3), now),
        isTrue,
      );
    });

    test('a check within the interval is not due', () {
      final last = now.subtract(const Duration(days: 1));
      expect(
        PluginUpdateScheduler.isDue(last, const Duration(days: 3), now),
        isFalse,
      );
    });

    test('exactly at the interval boundary is due — >=, not >', () {
      final last = now.subtract(const Duration(days: 3));
      expect(
        PluginUpdateScheduler.isDue(last, const Duration(days: 3), now),
        isTrue,
      );
    });

    test('a check timestamp in the future (clock skew) is not due', () {
      final last = now.add(const Duration(days: 1));
      expect(
        PluginUpdateScheduler.isDue(last, const Duration(days: 3), now),
        isFalse,
      );
    });
  });
}
