/// MusicBee comparison §36's "half stars" gap — half-star-precision
/// rating support shared by the star-picker UI and anything that needs
/// to render one. `RatingsPlugin.preciseRatingOf`/`setPreciseRating`
/// (`Omnis-Plugins`) are the storage side; this module is the pure,
/// dependency-free math both the picker widget and any future display
/// surface can share without duplicating it.
///
/// A single star's visual fill state within a 5-star half-precision
/// rating.
enum StarIconState { empty, half, full }

/// Clamps [raw] to `0-5` and rounds to the nearest `0.5` step — the
/// exact precision `RatingsPlugin.setPreciseRating` persists, so a
/// picker's raw pointer-position input always lands on a value the
/// store will actually accept rather than being silently rejected.
double snapToHalfStep(double raw) {
  final clamped = raw < 0 ? 0.0 : (raw > 5 ? 5.0 : raw);
  return (clamped * 2).round() / 2;
}

/// Whether [rating] is a valid half-star rating: `0` (unrated) or a
/// `0.5`-`5.0` value in exact half-steps. Mirrors the exact boundary
/// `RatingsPlugin._isValidRating` enforces on the storage side — kept
/// here too so the UI can reject/clamp before ever calling the store,
/// not just rely on a thrown `ArgumentError` after the fact.
bool isValidHalfStarRating(double rating) {
  if (rating == 0) return true;
  if (rating < 0.5 || rating > 5) return false;
  return (rating * 2) == (rating * 2).roundToDouble();
}

/// The fill state star [starIndex] (1-5) should render for an overall
/// [rating] — full once [rating] reaches this star's whole value, half
/// at exactly `starIndex - 0.5`, empty otherwise. E.g. for `rating =
/// 3.5`: stars 1-3 are full, star 4 is half, star 5 is empty.
StarIconState iconStateFor(int starIndex, double rating) {
  if (rating >= starIndex) return StarIconState.full;
  if (rating >= starIndex - 0.5) return StarIconState.half;
  return StarIconState.empty;
}
