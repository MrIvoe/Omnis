import 'package:omnis/core/base_track.dart';

/// A read-only, *derived* rating for a group of tracks (an album, an
/// artist) — MusicBee-comparison §36's "distinction between a user
/// rating and a calculated one." [RatingsPlugin] only ever stores a
/// per-track rating; this is never itself persisted, always recomputed
/// from whatever the member tracks are currently rated.
class GroupRatingSummary {
  final double average;
  final int ratedCount;

  const GroupRatingSummary({required this.average, required this.ratedCount});
}

/// Averages [ratingOf] across [tracks], counting only tracks with a real
/// rating (`> 0` — 0 means unrated, the same convention
/// `RatingsPlugin.ratingOf`/`library_search.dart`'s `rating:0` qualifier
/// already use). Returns `null` when no track in the group has been
/// rated at all — an average of zero data points isn't a "0-star"
/// finding, it's "nothing to report," the same "don't manufacture a
/// claim the data can't support" stance `library_cleanup_analyzer.dart`/
/// `library_statistics.dart` already take for their own aggregate
/// stats.
GroupRatingSummary? averageRating(
  List<BaseTrack> tracks,
  int Function(String trackId) ratingOf,
) {
  var sum = 0;
  var count = 0;
  for (final track in tracks) {
    final rating = ratingOf(track.id);
    if (rating > 0) {
      sum += rating;
      count++;
    }
  }
  if (count == 0) return null;
  return GroupRatingSummary(average: sum / count, ratedCount: count);
}
