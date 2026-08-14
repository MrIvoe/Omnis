import 'dart:async';

import 'package:just_audio/just_audio.dart'
    show PlayerState, ProcessingState;
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/home_widget_track_source.dart';

/// A controllable in-memory [HomeWidgetTrackSource] double for testing
/// [HomeWidgetService] without a real just_audio player — see
/// [FakePlaybackEngine]'s doc for why this seam-and-fake pattern exists.
class FakeHomeWidgetTrackSource implements HomeWidgetTrackSource {
  final _trackController = StreamController<BaseTrack?>.broadcast();
  final _playerStateController = StreamController<PlayerState>.broadcast();

  @override
  BaseTrack? currentTrack;

  @override
  bool isPlaying = false;

  @override
  Stream<BaseTrack?> get trackStream => _trackController.stream;

  @override
  Stream<PlayerState> get playerStateStream => _playerStateController.stream;

  void emitTrack(BaseTrack? track) {
    currentTrack = track;
    _trackController.add(track);
  }

  void emitPlaying(bool playing) {
    isPlaying = playing;
    _playerStateController.add(PlayerState(playing, ProcessingState.ready));
  }

  Future<void> dispose() async {
    await _trackController.close();
    await _playerStateController.close();
  }
}
