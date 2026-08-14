import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:just_audio/just_audio.dart' show PlayerState;

import 'base_track.dart';
import 'home_widget_track_source.dart';

/// Bridges live playback state to the Android home-screen widget
/// (`OmnisWidgetProvider`, `android/app/src/main/kotlin/.../OmnisWidgetProvider.kt`)
/// — Phase 7 §49 "Widgets", scoped to a real interactive Android
/// home-screen widget: title/artist/play-state on the widget always
/// reflect what's actually playing, kept live via this listener rather
/// than a one-shot snapshot at add-time.
///
/// Play/Pause/Next/Previous on the widget do **not** round-trip through
/// this class or through Dart at all: they're wired directly, on the
/// native side, to `android.intent.action.MEDIA_BUTTON` broadcasts
/// targeted at the app's own package, which `audio_service`'s already
/// -registered `MediaButtonReceiver` (see AndroidManifest.xml) picks up
/// exactly the way a Bluetooth headset's hardware buttons or the lock
/// -screen notification's own controls already do. That is a deliberate
/// choice over a Flutter background-isolate callback (the pattern
/// `home_widget`'s own docs describe for interactive buttons): this
/// app's playback engine (`just_audio`) has no supported story for
/// running in a second, widget-triggered background isolate, so reusing
/// the real, already-working MediaSession plumbing is both simpler and
/// far more reliable than standing up a second one.
class HomeWidgetService {
  HomeWidgetService._();

  static final HomeWidgetService instance = HomeWidgetService._();

  /// Must match the `<receiver android:name="...">` in AndroidManifest.xml
  /// and the class name of `OmnisWidgetProvider.kt`.
  static const _androidWidgetName = 'OmnisWidgetProvider';

  StreamSubscription<BaseTrack?>? _trackSub;
  StreamSubscription<PlayerState>? _stateSub;

  BaseTrack? _lastTrack;
  bool _lastPlaying = false;

  /// Starts mirroring [audioEngine]'s current and future track/play-state
  /// into the widget's storage. Safe to call once at app startup; a
  /// missing/never-added widget just makes [HomeWidget.updateWidget] a
  /// harmless no-op (Android skips `onUpdate` when there are zero
  /// instances of the widget on any home screen).
  void initialize(HomeWidgetTrackSource audioEngine) {
    _lastTrack = audioEngine.currentTrack;
    _lastPlaying = audioEngine.isPlaying;
    // ignore: unawaited_futures
    _push();

    _trackSub = audioEngine.trackStream.listen((track) {
      _lastTrack = track;
      // ignore: unawaited_futures
      _push();
    });
    _stateSub = audioEngine.playerStateStream.listen((state) {
      _lastPlaying = state.playing;
      // ignore: unawaited_futures
      _push();
    });
  }

  bool _loggedUnavailable = false;

  /// Best-effort, like `OmnisPermissions`'s own "a denial degrades,
  /// never blocks boot" stance and the SMTC (Windows media controls)
  /// startup path: `home_widget` has no Windows/Linux implementation and
  /// isn't registered at all in a plain `flutter_test` environment, both
  /// of which throw a [MissingPluginException] here on every single
  /// track/play-state change if left uncaught — a platform gap, not an
  /// app bug, so it must never surface as a crash or a failing test.
  /// Logs once, not per change, since a platform without the widget will
  /// fail identically forever.
  Future<void> _push() async {
    final track = _lastTrack;
    try {
      await HomeWidget.saveWidgetData<String>(
          'title', track?.title ?? 'Not playing');
      await HomeWidget.saveWidgetData<String>(
          'artist', track == null ? '' : track.artists.join(', '));
      await HomeWidget.saveWidgetData<bool>('playing', _lastPlaying);
      await HomeWidget.updateWidget(androidName: _androidWidgetName);
    } catch (e) {
      if (!_loggedUnavailable) {
        _loggedUnavailable = true;
        debugPrint('Omnis: home-screen widget unavailable, continuing '
            'without it: $e');
      }
    }
  }

  Future<void> dispose() async {
    await _trackSub?.cancel();
    await _stateSub?.cancel();
    _trackSub = null;
    _stateSub = null;
  }
}
