import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/sleep_timer_plugin.dart';

void main() {
  test('sleep timer pauses playback after the selected duration', () async {
    var paused = false;
    final plugin = SleepTimerPlugin(onPause: () async {
      paused = true;
    });

    plugin.startTimer(const Duration(milliseconds: 40));
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(plugin.isActive, isFalse);
    expect(paused, isTrue);
  });
}
