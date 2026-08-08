import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnis_plugins/sleep_timer_plugin.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('sleep timer pauses playback after the selected duration, fade off',
      () async {
    var paused = false;
    final plugin = SleepTimerPlugin(onPause: () async => paused = true);
    await plugin.storage.initialize();
    await plugin.setFadeSeconds(0);

    fakeAsync((async) {
      plugin.startTimer(const Duration(seconds: 40));
      async.elapse(const Duration(seconds: 41));

      expect(plugin.isActive, isFalse);
      expect(paused, isTrue);
    });
  });

  test(
      'fades volume to zero across the final fadeSeconds before pausing, '
      'then restores the original volume', () async {
    var paused = false;
    final volumeLog = <double>[];
    final plugin = SleepTimerPlugin(
      onPause: () async => paused = true,
      onSetVolume: (v) async => volumeLog.add(v),
    );
    await plugin.storage.initialize();
    await plugin.setFadeSeconds(10);

    fakeAsync((async) {
      plugin.startTimer(const Duration(seconds: 30));

      // Nothing happens until just before the 20s mark (30s total - 10s
      // fade window) — the fade-start timer fires exactly at 20s, so
      // this checks the instant before that boundary.
      async.elapse(const Duration(seconds: 19, milliseconds: 999));
      expect(plugin.isFading, isFalse);
      expect(volumeLog, isEmpty);
      expect(paused, isFalse);

      // Crossing the 20s mark starts the fade, which runs across the
      // final 10 seconds, then pauses.
      async.elapse(const Duration(seconds: 10, milliseconds: 1));

      expect(paused, isTrue);
      expect(plugin.isActive, isFalse);
      expect(plugin.isFading, isFalse);
      expect(volumeLog, isNotEmpty);
      // Every step but the last must be a strictly decreasing volume
      // heading toward silence...
      for (var i = 1; i < volumeLog.length - 1; i++) {
        expect(volumeLog[i], lessThan(volumeLog[i - 1]));
      }
      // ...and the very last call is the restore back to the original
      // (unattached-context default) volume of 1.0 — never left silent.
      expect(volumeLog.last, 1.0);
    });
  });

  test('cancelling mid-fade restores the pre-fade volume immediately',
      () async {
    final volumeLog = <double>[];
    final plugin = SleepTimerPlugin(
      onPause: () async {},
      onSetVolume: (v) async => volumeLog.add(v),
    );
    await plugin.storage.initialize();
    await plugin.setFadeSeconds(10);

    fakeAsync((async) {
      plugin.startTimer(const Duration(seconds: 30));
      async.elapse(const Duration(seconds: 25)); // 5s into the 10s fade
      expect(plugin.isFading, isTrue);
      expect(volumeLog, isNotEmpty);
      expect(volumeLog.last, lessThan(1.0));

      plugin.stopTimer();
      async.flushMicrotasks();

      expect(plugin.isActive, isFalse);
      expect(plugin.isFading, isFalse);
      expect(volumeLog.last, 1.0,
          reason: 'cancelling mid-fade must not leave the volume stuck '
              'at a partially-faded level');
    });
  });

  test('a duration shorter than fadeSeconds fades across the whole timer',
      () async {
    var paused = false;
    final plugin = SleepTimerPlugin(onPause: () async => paused = true);
    await plugin.storage.initialize();
    await plugin.setFadeSeconds(20);

    fakeAsync((async) {
      plugin.startTimer(const Duration(seconds: 5));
      async.elapse(const Duration(seconds: 6));

      expect(paused, isTrue);
    });
  });

  test('restarting the timer while a fade is in progress restores volume '
      'before starting fresh', () async {
    final volumeLog = <double>[];
    final plugin = SleepTimerPlugin(
      onPause: () async {},
      onSetVolume: (v) async => volumeLog.add(v),
    );
    await plugin.storage.initialize();
    await plugin.setFadeSeconds(10);

    fakeAsync((async) {
      plugin.startTimer(const Duration(seconds: 20));
      async.elapse(const Duration(seconds: 15)); // 5s into the fade
      expect(plugin.isFading, isTrue);

      plugin.startTimer(const Duration(seconds: 30)); // restart
      async.flushMicrotasks();

      expect(volumeLog.last, 1.0,
          reason: 'restarting must restore the interrupted fade\'s volume, '
              'not leave it wherever the old fade had gotten to');
      expect(plugin.isFading, isFalse);
      expect(plugin.duration, const Duration(seconds: 30));
    });
  });

  test('setFadeSeconds clamps to a sane range', () async {
    final plugin = SleepTimerPlugin();
    await plugin.storage.initialize();

    await plugin.setFadeSeconds(-5);
    expect(plugin.fadeSeconds, 0);

    await plugin.setFadeSeconds(9999);
    expect(plugin.fadeSeconds, 300);
  });

  test('fadeSeconds defaults to 20 when nothing was persisted', () async {
    final plugin = SleepTimerPlugin();
    await plugin.storage.initialize();
    expect(plugin.fadeSeconds, 20);
  });
}
