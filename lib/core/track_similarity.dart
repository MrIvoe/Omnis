import 'package:omnis/core/base_track.dart';

/// Real "sounds like this" computation over `BaseTrack`'s own already-
/// populated fields (`genres`/`mood`/`bpm`/`key` — filled in by
/// `AudioAnalysisPlugin`'s Essentia analysis, `MetadataEnrichmentPlugin`'s
/// Last.fm/Discogs tags, or manual tagging) — item 40's "no embedding/
/// fingerprint and no similarity/distance computation anywhere" gap, and
/// item 39's still-missing "Similar Track" named recommendation algorithm.
///
/// Deliberately not a real acoustic-fingerprint/embedding system — that
/// would need actual signal-processing infrastructure this environment
/// can't build (the same reasoning `metadata_enrichment_plugin.dart`'s own
/// doc comment gives for not attempting a real Essentia integration
/// itself). This is a genuinely useful, honestly-scoped smaller piece:
/// distance over the discrete features already on every analyzed/enriched
/// track, not a claim of real audio-content matching.

/// Relative importance of each signal in [similarityScore]. A shared
/// genre is deliberate, opt-in metadata (a human or a real classifier
/// picked it), so it counts for the most; an exact mood match is the next
/// most specific signal a track can carry. BPM is real but noisy — a
/// whole album often shares one tempo regardless of how the individual
/// tracks actually sound — so it counts for less. Exact key match is the
/// weakest signal on its own (many completely dissimilar tracks share a
/// key), included mainly as a tie-breaker among otherwise-close matches.
const double _genreWeight = 0.35;
const double _moodWeight = 0.30;
const double _bpmWeight = 0.20;
const double _keyWeight = 0.15;

/// BPM difference beyond which two tracks score zero tempo similarity —
/// wide enough that genuinely different tempos (a 90 BPM ballad vs. a
/// 140 BPM dance track) don't score as remotely close, narrow enough that
/// two tracks a few BPM apart (the same song at slightly different
/// masters, or just genuinely similar energy) still register as close.
const double _bpmZeroScoreDelta = 30.0;

/// How similar [a] and [b] are, from `0.0` (nothing in common, or nothing
/// comparable at all) to `1.0` (identical on every signal both tracks
/// have data for).
///
/// Only signals present on **both** tracks contribute — the weighted sum
/// is renormalized against the weight of just those present signals, so a
/// track missing e.g. BPM data isn't unfairly penalized relative to one
/// that has it; it's simply judged on whatever data both sides share.
/// When neither track has *any* comparable signal, this returns `0.0`
/// rather than an undefined/NaN "similarity" — an honest "nothing to
/// compare," the same "don't manufacture a claim the data can't support"
/// stance `QueuePresetPlugin`'s "Forgotten Favorites"/"Rediscover"
/// presets already take for missing history/ratings data.
double similarityScore(BaseTrack a, BaseTrack b) {
  double weightedSum = 0;
  double presentWeight = 0;

  final genresA = a.genres.map((g) => g.trim().toLowerCase()).where((g) => g.isNotEmpty).toSet();
  final genresB = b.genres.map((g) => g.trim().toLowerCase()).where((g) => g.isNotEmpty).toSet();
  if (genresA.isNotEmpty && genresB.isNotEmpty) {
    final union = genresA.union(genresB).length;
    final jaccard = union == 0 ? 0.0 : genresA.intersection(genresB).length / union;
    weightedSum += jaccard * _genreWeight;
    presentWeight += _genreWeight;
  }

  final moodA = a.mood?.trim().toLowerCase();
  final moodB = b.mood?.trim().toLowerCase();
  if (moodA != null && moodA.isNotEmpty && moodB != null && moodB.isNotEmpty) {
    weightedSum += (moodA == moodB ? 1.0 : 0.0) * _moodWeight;
    presentWeight += _moodWeight;
  }

  final bpmA = a.bpm;
  final bpmB = b.bpm;
  if (bpmA != null && bpmB != null) {
    final bpmScore = (1 - (bpmA - bpmB).abs() / _bpmZeroScoreDelta).clamp(0.0, 1.0);
    weightedSum += bpmScore * _bpmWeight;
    presentWeight += _bpmWeight;
  }

  final keyA = a.key?.trim().toLowerCase();
  final keyB = b.key?.trim().toLowerCase();
  if (keyA != null && keyA.isNotEmpty && keyB != null && keyB.isNotEmpty) {
    weightedSum += (keyA == keyB ? 1.0 : 0.0) * _keyWeight;
    presentWeight += _keyWeight;
  }

  if (presentWeight == 0) return 0.0;
  return weightedSum / presentWeight;
}

/// Ranks [library] by [similarityScore] against [seed] (excluding [seed]
/// itself, matched by id) and returns the top [limit], most similar
/// first. Only tracks that scored above `0.0` — i.e. share at least one
/// real comparable signal with [seed] — are ever returned, so a track
/// with no genre/mood/bpm/key data at all yields an empty list rather
/// than an arbitrary/misleading ranking of the whole library.
List<BaseTrack> findSimilarTracks(
  BaseTrack seed,
  List<BaseTrack> library, {
  int limit = 25,
}) {
  final scored = <MapEntry<BaseTrack, double>>[];
  for (final candidate in library) {
    if (candidate.id == seed.id) continue;
    final score = similarityScore(seed, candidate);
    if (score > 0.0) {
      scored.add(MapEntry(candidate, score));
    }
  }
  scored.sort((entryA, entryB) => entryB.value.compareTo(entryA.value));
  return scored.take(limit).map((entry) => entry.key).toList();
}
