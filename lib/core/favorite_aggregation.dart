import 'package:omnis/core/base_track.dart';

/// A group (artist, album, or genre name) ranked by how many favorited
/// tracks belong to it — comparison doc "Statistics" → "Listening"'s
/// "Favorite artists"/"Favorite albums"/"Favorite genres", the slice of
/// that list that (unlike "streaks"/hourly histograms) needs no
/// per-play timestamp data, only [BaseTrack]s already loaded plus the
/// same `isFavorite` lookup `library_page.dart`'s `favorite:` search
/// qualifier already uses.
class FavoriteGroupCount {
  final String name;
  final int favoriteCount;

  const FavoriteGroupCount({required this.name, required this.favoriteCount});
}

enum FavoriteGroupBy { artist, album, genre }

/// Ranks [by] (artist/album/genre) by how many favorited tracks name
/// them, highest first, ties broken alphabetically for a deterministic
/// order. A track with multiple artists/genres contributes to each —
/// same "each value counts once toward its own group" stance
/// `library_search.dart`'s multi-valued-field qualifiers already take.
/// Blank names are skipped, the same defensive stance
/// `LibraryStatistics.compute` already takes for its own album/artist/
/// genre sets.
List<FavoriteGroupCount> topFavoriteGroups(
  List<BaseTrack> tracks,
  bool Function(String trackId) isFavorite, {
  required FavoriteGroupBy by,
  int limit = 10,
}) {
  final counts = <String, int>{};
  for (final track in tracks) {
    if (!isFavorite(track.id)) continue;
    final names = switch (by) {
      FavoriteGroupBy.artist => track.artists,
      FavoriteGroupBy.album => [track.album],
      FavoriteGroupBy.genre => track.genres,
    };
    for (final name in names) {
      final trimmed = name.trim();
      if (trimmed.isEmpty) continue;
      counts[trimmed] = (counts[trimmed] ?? 0) + 1;
    }
  }

  final result = counts.entries
      .map((e) => FavoriteGroupCount(name: e.key, favoriteCount: e.value))
      .toList()
    ..sort((a, b) {
      final byCount = b.favoriteCount.compareTo(a.favoriteCount);
      return byCount != 0 ? byCount : a.name.compareTo(b.name);
    });
  return result.take(limit).toList();
}

/// The highest-rated tracks, highest first, ties broken by title for a
/// deterministic order. Unrated tracks (`rating == 0`, the same
/// convention [averageRating] uses) are excluded — a 0-star tie-break
/// against real ratings would misrepresent "never rated" as "rated
/// worst."
List<BaseTrack> topRatedTracks(
  List<BaseTrack> tracks,
  int Function(String trackId) ratingOf, {
  int limit = 10,
}) {
  final rated = tracks.where((t) => ratingOf(t.id) > 0).toList()
    ..sort((a, b) {
      final byRating = ratingOf(b.id).compareTo(ratingOf(a.id));
      return byRating != 0 ? byRating : a.title.compareTo(b.title);
    });
  return rated.take(limit).toList();
}
