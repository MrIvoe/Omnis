/// Pure mute/unmute toggle logic — MusicBee comparison §28's global-
/// shortcuts checklist names "mute" explicitly. [AudioEngine] itself has
/// no separate mute concept, only a continuous `volume`/`setVolume`, so
/// "mute" here means "temporarily drive volume to 0.0, remembering what
/// it was so unmuting restores the exact prior value" rather than a real
/// independent boolean flag — deliberately, since a bare flag could
/// drift out of sync with the live volume (e.g. the user drags the
/// volume slider while "muted"), where this toggle just reads whatever
/// the engine's volume genuinely is right now.
class MuteToggleResult {
  final double newVolume;
  final double? volumeToRemember;

  const MuteToggleResult({
    required this.newVolume,
    required this.volumeToRemember,
  });
}

/// [currentVolume] is the engine's live volume right now; [volumeBeforeMute]
/// is whatever a caller last remembered from this function's own
/// [MuteToggleResult.volumeToRemember] (`null` if never muted, or if the
/// most recent toggle was an unmute).
///
/// - Muting (`currentVolume > 0`): remembers [currentVolume], returns
///   `0.0` to apply.
/// - Unmuting (`currentVolume == 0`): restores [volumeBeforeMute], or
///   falls back to `1.0` when nothing real was ever remembered (e.g.
///   the engine started at 0 and this toggle has never actually muted
///   anything yet) — restoring to "nothing" would leave the user stuck
///   silent with no way to recover via this same shortcut.
MuteToggleResult toggleMute(double currentVolume, double? volumeBeforeMute) {
  if (currentVolume > 0) {
    return MuteToggleResult(newVolume: 0.0, volumeToRemember: currentVolume);
  }
  final restored =
      (volumeBeforeMute != null && volumeBeforeMute > 0) ? volumeBeforeMute : 1.0;
  return MuteToggleResult(newVolume: restored, volumeToRemember: null);
}
