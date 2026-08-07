import 'package:flutter/foundation.dart';

/// A single adjustable band on the platform's native equalizer.
///
/// Deliberately just_audio-agnostic in its public surface — no
/// `AndroidEqualizerBand` type leaks out — so a plugin that wants real
/// per-band control depends only on this, not on the audio backend.
///
/// Lives here rather than in `AudioEngine` (where it originated) so
/// `EqualizerPlugin` can name the type without depending on the app's
/// audio engine — the concrete engine is still the only thing that ever
/// constructs a real instance (via [HardwareEqBand.fromPlatform]; a
/// plugin only ever reads instances handed to it through
/// `PluginContext.hardwareEqBands`).
class HardwareEqBand {
  /// Index of this band on the native equalizer.
  final int index;

  /// Approximate center frequency in Hz, as reported by the platform.
  final double centerFrequencyHz;

  /// Minimum gain the platform accepts, in decibels.
  final double minDecibels;

  /// Maximum gain the platform accepts, in decibels.
  final double maxDecibels;

  final Future<void> Function(double gain) _applyGain;
  double _gain;

  /// Constructed by `AudioEngine` from real platform state — not a
  /// private constructor (Dart's `_`-privacy is file-scoped, and this
  /// type now lives in a different package/file than `AudioEngine`), but
  /// a plugin should never call this directly; only read instances via
  /// `PluginContext.hardwareEqBands`.
  HardwareEqBand.fromPlatform({
    required this.index,
    required this.centerFrequencyHz,
    required this.minDecibels,
    required this.maxDecibels,
    required double initialGain,
    required Future<void> Function(double gain) applyGain,
  })  : _gain = initialGain,
        _applyGain = applyGain;

  /// Test-only constructor — production bands only come from
  /// `AudioEngine.hardwareEqBands`, which reads real platform state.
  @visibleForTesting
  factory HardwareEqBand.forTesting({
    required int index,
    required double centerFrequencyHz,
    double minDecibels = -15,
    double maxDecibels = 15,
    double initialGain = 0,
    Future<void> Function(double gain)? applyGain,
  }) {
    return HardwareEqBand.fromPlatform(
      index: index,
      centerFrequencyHz: centerFrequencyHz,
      minDecibels: minDecibels,
      maxDecibels: maxDecibels,
      initialGain: initialGain,
      applyGain: applyGain ?? (_) async {},
    );
  }

  /// Current gain in decibels.
  double get gain => _gain;

  /// Set this band's gain, clamped to the platform's supported range.
  Future<void> setGain(double decibels) async {
    final clamped = decibels.clamp(minDecibels, maxDecibels);
    _gain = clamped;
    await _applyGain(clamped);
  }
}
