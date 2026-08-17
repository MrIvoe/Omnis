import 'dart:math';

import 'package:omnis/core/artist_similarity.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/track_similarity.dart';

/// Item 2 (Queue)'s "smart/rule-based continuation" gap: when the queue
/// naturally runs out, extend it automatically with more tracks chosen by
/// one of these rules instead of just stopping. Reuses the real similarity
/// scoring `track_similarity.dart` (item 40) and `artist_similarity.dart`
/// (item 39) already built for the "Similar Track"/"Similar Artist"
/// recommendation algorithms — this is mostly wiring, not new scoring.
enum QueueContinuationMode {
  off,
  similarTrack,
  similarArtist,
  sameGenre,
  sameMood,
  sameAlbum,
}

/// How many tracks one continuation event appends — a batch, not the rest
/// of a session. If the appended batch itself runs out, the same mechanism
/// fires again for another batch.
const int defaultContinuationLimit = 10;

/// How many similar artists' pooled tracks to draw from for
/// [QueueContinuationMode.similarArtist] — several artists, not just the
/// closest one, so there's enough of a pool to shuffle from.
const int _similarArtistPoolSize = 5;

List<BaseTrack> _shuffledMatches(
  List<BaseTrack> matches,
  int limit,
  Random? random,
) {
  final shuffled = List<BaseTrack>.from(matches)..shuffle(random);
  return shuffled.take(limit).toList();
}

/// Picks up to [limit] tracks from [library] to extend the queue after
/// [seed] finishes playing, according to [mode]. [excludeIds] is typically
/// the current queue's own track ids, so a long auto-continued session
/// never re-queues a track it already picked.
///
/// Every branch returns an empty list rather than falling back to an
/// arbitrary whole-library shuffle when [mode] has nothing real to base a
/// pick on (e.g. [seed] has no genre/mood data) — the same "don't
/// manufacture a claim the data can't support" stance
/// `track_similarity.dart`/`QueuePresetPlugin` already take. The caller is
/// expected to simply let the queue end as it does today when this returns
/// empty.
List<BaseTrack> continuationTracks({
  required BaseTrack seed,
  required List<BaseTrack> library,
  required QueueContinuationMode mode,
  Set<String> excludeIds = const {},
  int limit = defaultContinuationLimit,
  bool groupByAlbumArtist = false,
  Random? random,
}) {
  if (mode == QueueContinuationMode.off) return const [];

  final pool = library
      .where((track) => track.id != seed.id && !excludeIds.contains(track.id))
      .toList();
  if (pool.isEmpty) return const [];

  switch (mode) {
    case QueueContinuationMode.off:
      return const [];

    case QueueContinuationMode.similarTrack:
      return findSimilarTracks(seed, pool, limit: limit);

    case QueueContinuationMode.similarArtist:
      final seedArtist = groupByAlbumArtist
          ? (seed.albumArtist ??
              (seed.artists.isNotEmpty ? seed.artists.first : null) ??
              'Unknown Artist')
          : (seed.artists.isNotEmpty ? seed.artists.first : 'Unknown Artist');
      final byArtist = <String, List<BaseTrack>>{};
      for (final track in library) {
        final artist = groupByAlbumArtist
            ? (track.albumArtist ??
                (track.artists.isNotEmpty ? track.artists.first : null) ??
                'Unknown Artist')
            : (track.artists.isNotEmpty
                ? track.artists.first
                : 'Unknown Artist');
        byArtist.putIfAbsent(artist, () => []).add(track);
      }
      final similarArtists = findSimilarArtists(
        seedArtist,
        byArtist,
        limit: _similarArtistPoolSize,
      );
      if (similarArtists.isEmpty) return const [];
      final matches = <BaseTrack>[];
      for (final artist in similarArtists) {
        for (final track in byArtist[artist] ?? const <BaseTrack>[]) {
          if (track.id != seed.id && !excludeIds.contains(track.id)) {
            matches.add(track);
          }
        }
      }
      return _shuffledMatches(matches, limit, random);

    case QueueContinuationMode.sameGenre:
      final seedGenres = seed.genres
          .map((g) => g.trim().toLowerCase())
          .where((g) => g.isNotEmpty)
          .toSet();
      if (seedGenres.isEmpty) return const [];
      final matches = pool.where((track) {
        final genres = track.genres
            .map((g) => g.trim().toLowerCase())
            .where((g) => g.isNotEmpty)
            .toSet();
        return genres.intersection(seedGenres).isNotEmpty;
      }).toList();
      return _shuffledMatches(matches, limit, random);

    case QueueContinuationMode.sameMood:
      final seedMood = seed.mood?.trim().toLowerCase();
      if (seedMood == null || seedMood.isEmpty) return const [];
      final matches = pool
          .where((track) => track.mood?.trim().toLowerCase() == seedMood)
          .toList();
      return _shuffledMatches(matches, limit, random);

    case QueueContinuationMode.sameAlbum:
      final seedAlbum = seed.album.trim();
      if (seedAlbum.isEmpty) return const [];
      final matches = pool
          .where((track) =>
              track.album.trim() == seedAlbum &&
              track.albumArtist == seed.albumArtist)
          .toList();
      return _shuffledMatches(matches, limit, random);
  }
}
