import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/plugin_interface.dart';

/// A bundled plugin that applies a simple loudness normalization multiplier.
class ReplayGainPlugin extends MusicPlugin {
  double _multiplier = 1.0;

  double get multiplier => _multiplier;

  void setReplayGain(BaseTrack track) {
    final gain = track.replayGain?.trackGain;
    if (gain != null && gain.isFinite) {
      _multiplier = (gain >= 0 ? 1.0 : 1.0 + (-gain / 20.0)).clamp(0.5, 1.5);
    } else {
      _multiplier = 1.0;
    }
  }

  @override
  String get id => 'replay_gain';

  @override
  String get name => 'Replay Gain';

  @override
  String get description => 'Normalizes track loudness using ReplayGain-style metadata.';

  @override
  String get version => '1.0.0';

  @override
  String get author => 'Omnis Team';

  @override
  Future<void> initialize() async {}

  @override
  Future<void> onTrackStart(BaseTrack track) async {
    setReplayGain(track);
  }

  @override
  Future<void> onLibraryScan(String file) async {}

  @override
  dynamic uiSlot(String locationID) => null;

  @override
  Future<void> dispose() async {}
}
