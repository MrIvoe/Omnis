import 'package:just_audio/just_audio.dart' show PlayerState;

import 'base_track.dart';

/// The narrow slice of `AudioEngine`'s public API [HomeWidgetService]
/// needs — the same "small, purpose-specific seam" pattern
/// `PlaybackEngine` already establishes for `PlaybackWatchdog`/
/// `PlaybackRecovery`, kept as its own interface (rather than folded
/// into `PlaybackEngine`) since it serves a different concern — what to
/// *display*, not how to *drive* transport — and in its own file so
/// `audio_engine.dart` (which implements it) and `home_widget_service.dart`
/// (which consumes it) don't have to import each other. Lets a test
/// substitute a plain in-memory fake instead of a real just_audio player.
abstract class HomeWidgetTrackSource {
  BaseTrack? get currentTrack;
  bool get isPlaying;
  Stream<BaseTrack?> get trackStream;
  Stream<PlayerState> get playerStateStream;
}
