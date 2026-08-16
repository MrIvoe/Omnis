/// Ratio of [positionSeconds] through [durationSeconds] a listen
/// reached, clamped to the `[0.0, 1.0]` range (a track can genuinely
/// report a position slightly past its own duration near the very end
/// of playback). `null` when [durationSeconds] is unknown or
/// non-positive — a completion ratio needs a real denominator, the same
/// "don't manufacture a claim the data can't support" stance every
/// other derived stat in this app already takes (e.g.
/// `library_statistics.dart`'s average bitrate skipping unknown
/// values).
double? completionRatio(int positionSeconds, int durationSeconds) {
  if (durationSeconds <= 0) return null;
  final ratio = positionSeconds / durationSeconds;
  if (ratio < 0) return 0.0;
  if (ratio > 1) return 1.0;
  return ratio;
}

/// A listen counts as a skip when it never reached [threshold] through
/// the track — "played less than half" is the same convention MusicBee/
/// Spotify-style players use to distinguish an abandoned listen from a
/// genuine one. [ratio] is expected to already be a clamped `[0.0, 1.0]`
/// value, the shape [completionRatio] returns.
bool isSkip(double ratio, {double threshold = 0.5}) => ratio < threshold;
