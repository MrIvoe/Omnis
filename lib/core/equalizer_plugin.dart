import 'dart:math' as math;

import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/plugin_interface.dart';

/// A bundled equalizer plugin with a few preset bands.
class EqualizerPlugin extends MusicPlugin {
  final Map<String, double> _bands = {
    'bass': 0.0,
    'mid': 0.0,
    'treble': 0.0,
  };

  double getBand(String key) => _bands[key] ?? 0.0;

  void setBand(String key, double value) {
    _bands[key] = value.clamp(-12.0, 12.0);
  }

  @override
  String get id => 'equalizer';

  @override
  String get name => 'Equalizer';

  @override
  String get description => 'Provides simple preset-based audio shaping.';

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
  dynamic uiSlot(String locationID) => null;

  @override
  Future<void> dispose() async {}

  double applyGain(double input) {
    final bassBoost = getBand('bass') / 24.0;
    final midBoost = getBand('mid') / 24.0;
    final trebleBoost = getBand('treble') / 24.0;
    return (input * (1.0 + bassBoost * 0.6 + midBoost * 0.4 + trebleBoost * 0.3)).clamp(0.0, 1.0);
  }
}
