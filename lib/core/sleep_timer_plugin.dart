import 'dart:async';

import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/plugin_interface.dart';

/// A bundled Namida-inspired plugin that pauses playback after a chosen delay.
class SleepTimerPlugin extends MusicPlugin {
  final Future<void> Function()? onPause;
  Timer? _timer;
  bool _active = false;

  SleepTimerPlugin({this.onPause});

  bool get isActive => _active;

  void startTimer(Duration duration) {
    stopTimer();
    _active = true;
    _timer = Timer(duration, () async {
      _active = false;
      await onPause?.call();
    });
  }

  void stopTimer() {
    _timer?.cancel();
    _timer = null;
    _active = false;
  }

  @override
  String get id => 'sleep_timer';

  @override
  String get name => 'Sleep Timer';

  @override
  String get description => 'Pause playback after a chosen duration.';

  @override
  String get version => '1.0.0';

  @override
  String get author => 'Omnis Team';

  @override
  Future<void> initialize() async {}

  @override
  Future<void> onTrackStart(BaseTrack track) async {}

  @override
  Future<void> onLibraryScan(String file) async {}

  @override
  dynamic uiSlot(String locationID) {
    if (locationID == 'now_playing_bottom') {
      return null;
    }
    return null;
  }

  @override
  Future<void> dispose() async {
    stopTimer();
  }
}
