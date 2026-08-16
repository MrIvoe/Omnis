import 'package:omnis/core/base_track.dart';

/// "Similar Artist" — item 39's still-missing named recommendation
/// algorithm, the artist-level sibling of `track_similarity.dart`'s
/// "Similar Track" (item 40). Same honest scope: real distance over
/// discrete, already-populated `BaseTrack` fields (`genres`/`mood`/
/// `bpm`), aggregated per artist, not a real acoustic-fingerprint/
/// embedding system — that needs signal-processing infrastructure this
/// environment can't build, the same reasoning `track_similarity.dart`'s
/// own doc comment already gives.

/// One artist's aggregated profile across every track of theirs the
/// caller supplies — the union of genres (deliberate, opt-in metadata,
/// so any genre any of their tracks carries counts), the most frequent
/// mood (ties broken alphabetically, for determinism), and the average
/// BPM across tracks that have one. Any of [genres]/[dominantMood]/
/// [averageBpm] can be "nothing" (an empty set / `null`) when the
/// artist's tracks carry no data for that signal at all.
class ArtistProfile {
  final String artist;
  final Set<String> genres;
  final String? dominantMood;
  final double? averageBpm;

  const ArtistProfile({
    required this.artist,
    required this.genres,
    this.dominantMood,
    this.averageBpm,
  });
}

/// Builds [artist]'s profile from [tracks] — every one of their tracks
/// the caller has, not a re-derived lookup (this function is pure and
/// has no opinion on how "an artist's tracks" is defined, e.g. whether
/// `groupArtistsByAlbumArtist` is on).
ArtistProfile buildArtistProfile(String artist, List<BaseTrack> tracks) {
  final genres = <String>{};
  final moodCounts = <String, int>{};
  final bpms = <double>[];

  for (final track in tracks) {
    genres.addAll(track.genres
        .map((g) => g.trim().toLowerCase())
        .where((g) => g.isNotEmpty));
    final mood = track.mood?.trim().toLowerCase();
    if (mood != null && mood.isNotEmpty) {
      moodCounts[mood] = (moodCounts[mood] ?? 0) + 1;
    }
    if (track.bpm != null) bpms.add(track.bpm!);
  }

  String? dominantMood;
  if (moodCounts.isNotEmpty) {
    final ranked = moodCounts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : a.key.compareTo(b.key);
      });
    dominantMood = ranked.first.key;
  }

  final averageBpm =
      bpms.isEmpty ? null : bpms.reduce((a, b) => a + b) / bpms.length;

  return ArtistProfile(
    artist: artist,
    genres: genres,
    dominantMood: dominantMood,
    averageBpm: averageBpm,
  );
}

/// Relative importance of each signal — same reasoning
/// `track_similarity.dart`'s own weights document: genre is deliberate,
/// opt-in metadata, so it counts for the most; mood is the next most
/// specific signal an artist's tracks can collectively carry; average
/// BPM is real but the noisiest of the three at artist granularity (one
/// artist can span many tempos across their catalog), so it counts for
/// the least. No key signal here (unlike track-level similarity) — key
/// is a per-track property with no meaningful "artist average."
const double _artistGenreWeight = 0.5;
const double _artistMoodWeight = 0.3;
const double _artistBpmWeight = 0.2;

/// Average-BPM difference beyond which two artists score zero tempo
/// similarity — same 30 BPM width `track_similarity.dart` uses.
const double _artistBpmZeroScoreDelta = 30.0;

/// How similar [a] and [b] are, from `0.0` (nothing in common, or
/// nothing comparable at all) to `1.0`. Only signals present on
/// **both** profiles contribute, renormalized against just those
/// signals' combined weight — the same "don't penalize missing data,
/// judge on what's actually shared" contract
/// `track_similarity.dart`'s `similarityScore` already establishes.
double artistSimilarityScore(ArtistProfile a, ArtistProfile b) {
  double weightedSum = 0;
  double presentWeight = 0;

  if (a.genres.isNotEmpty && b.genres.isNotEmpty) {
    final union = a.genres.union(b.genres).length;
    final jaccard =
        union == 0 ? 0.0 : a.genres.intersection(b.genres).length / union;
    weightedSum += jaccard * _artistGenreWeight;
    presentWeight += _artistGenreWeight;
  }

  if (a.dominantMood != null && b.dominantMood != null) {
    weightedSum +=
        (a.dominantMood == b.dominantMood ? 1.0 : 0.0) * _artistMoodWeight;
    presentWeight += _artistMoodWeight;
  }

  final bpmA = a.averageBpm;
  final bpmB = b.averageBpm;
  if (bpmA != null && bpmB != null) {
    final bpmScore =
        (1 - (bpmA - bpmB).abs() / _artistBpmZeroScoreDelta).clamp(0.0, 1.0);
    weightedSum += bpmScore * _artistBpmWeight;
    presentWeight += _artistBpmWeight;
  }

  if (presentWeight == 0) return 0.0;
  return weightedSum / presentWeight;
}

/// Ranks every artist in [tracksByArtist] (each key an artist name,
/// mapped to their own tracks — the exact shape `library_page.dart`'s
/// Artists-view grouping already builds) by [artistSimilarityScore]
/// against [seedArtist], excluding the seed itself. Only artists that
/// scored above `0.0` — sharing at least one real comparable signal —
/// are ever returned, so a seed artist with no genre/mood/bpm data at
/// all yields an empty list rather than an arbitrary ranking of the
/// whole library. Returns an empty list immediately if [seedArtist]
/// isn't a key in [tracksByArtist] at all.
List<String> findSimilarArtists(
  String seedArtist,
  Map<String, List<BaseTrack>> tracksByArtist, {
  int limit = 10,
}) {
  final seedTracks = tracksByArtist[seedArtist];
  if (seedTracks == null || seedTracks.isEmpty) return const [];
  final seedProfile = buildArtistProfile(seedArtist, seedTracks);

  final scored = <MapEntry<String, double>>[];
  for (final entry in tracksByArtist.entries) {
    if (entry.key == seedArtist || entry.value.isEmpty) continue;
    final profile = buildArtistProfile(entry.key, entry.value);
    final score = artistSimilarityScore(seedProfile, profile);
    if (score > 0.0) {
      scored.add(MapEntry(entry.key, score));
    }
  }
  scored.sort((entryA, entryB) => entryB.value.compareTo(entryA.value));
  return scored.take(limit).map((entry) => entry.key).toList();
}
