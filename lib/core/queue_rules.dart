import 'package:omnis/core/base_track.dart';

/// Item 2 (Queue)'s "queue rules/exclusions" gap — the MusicBee-comparison
/// §23 ask "queue rules: 'don't repeat artist', 'don't repeat album',
/// energy/BPM progression". Scoped to the first two: energy/BPM
/// progression needs an ordering-algorithm/product decision (ramp up?
/// down? peak-then-taper?), the same reason item 39's "Energy Flow"
/// stayed open this session — left as this gap's documented remainder,
/// not attempted here.
///
/// `minArtistGap`/`minAlbumGap` of `0` disables that rule entirely — the
/// default, so nothing changes for anyone who never opens the new
/// setting. A positive value is "how many other tracks must separate two
/// tracks by the same artist/album" — `1` means "never adjacent", `2`
/// means "at least one track between repeats", and so on.
class QueueRuleConstraints {
  final int minArtistGap;
  final int minAlbumGap;

  const QueueRuleConstraints({this.minArtistGap = 0, this.minAlbumGap = 0});

  static const QueueRuleConstraints none = QueueRuleConstraints();

  bool get isActive => minArtistGap > 0 || minAlbumGap > 0;
}

String _artistKeyFor(BaseTrack track, bool groupByAlbumArtist) =>
    groupByAlbumArtist
        ? (track.albumArtist ??
            (track.artists.isNotEmpty ? track.artists.first : null) ??
            'Unknown Artist')
        : (track.artists.isNotEmpty ? track.artists.first : 'Unknown Artist');

/// `(album, albumArtist)` — comparing both, not just the album title,
/// avoids treating two different albums that happen to share a title (by
/// different artists) as the same album, the same disambiguation
/// `queue_continuation.dart`'s own `sameAlbum` branch already applies.
(String, String?) _albumKeyFor(BaseTrack track) =>
    (track.album.trim(), track.albumArtist);

/// The last [gap] tracks immediately preceding position [index] in
/// [result], counting backward — filled out with the tail of
/// [precedingContext] (e.g. the live queue's already-placed tracks) when
/// [index] is too close to the start of [result] to supply the full
/// window on its own.
List<BaseTrack> _precedingWindow(
  List<BaseTrack> result,
  List<BaseTrack> precedingContext,
  int index,
  int gap,
) {
  final fromResult = result.sublist(index - gap < 0 ? 0 : index - gap, index);
  final needed = gap - fromResult.length;
  if (needed <= 0) return fromResult;
  final fromContext = precedingContext.length <= needed
      ? precedingContext
      : precedingContext.sublist(precedingContext.length - needed);
  return [...fromContext, ...fromResult];
}

bool _conflictsAtIndex(
  List<BaseTrack> result,
  List<BaseTrack> precedingContext,
  int index,
  BaseTrack candidate,
  QueueRuleConstraints constraints,
  bool groupByAlbumArtist,
) {
  if (constraints.minArtistGap > 0) {
    final key = _artistKeyFor(candidate, groupByAlbumArtist);
    final window =
        _precedingWindow(result, precedingContext, index, constraints.minArtistGap);
    if (window.any((t) => _artistKeyFor(t, groupByAlbumArtist) == key)) {
      return true;
    }
  }
  if (constraints.minAlbumGap > 0) {
    final key = _albumKeyFor(candidate);
    final window =
        _precedingWindow(result, precedingContext, index, constraints.minAlbumGap);
    if (window.any((t) => _albumKeyFor(t) == key)) return true;
  }
  return false;
}

/// Best-effort repair pass over an already-ordered/shuffled [tracks] list:
/// for each position that violates [constraints] against what's already
/// placed before it (including [precedingContext] — e.g. the tail of the
/// live queue, so a continuation batch doesn't repeat what's already
/// about to finish playing), swaps forward to the nearest later position
/// that doesn't. Pure — doesn't shuffle or rank on its own, callers do
/// that first; this only repairs an existing order.
///
/// **Not guaranteed conflict-free** — e.g. a candidate pool dominated by
/// one artist can't satisfy the rule no matter the ordering. A violation
/// that can't be resolved by any later swap is left in place rather than
/// looping or throwing, the same "don't manufacture a claim the data
/// can't support" honesty stance `queue_continuation.dart` already takes
/// for its own empty-result cases.
///
/// Applies only to *automatic* queue population (shuffle-remaining,
/// continuation) — never to a manual "Play next"/"Add to queue" action,
/// which stays exactly as the user chose it.
List<BaseTrack> applyQueueRules(
  List<BaseTrack> tracks,
  QueueRuleConstraints constraints, {
  bool groupByAlbumArtist = false,
  List<BaseTrack> precedingContext = const [],
}) {
  if (!constraints.isActive || tracks.length <= 1) {
    return List<BaseTrack>.of(tracks);
  }
  final result = List<BaseTrack>.of(tracks);
  for (var i = 0; i < result.length; i++) {
    if (!_conflictsAtIndex(result, precedingContext, i, result[i], constraints,
        groupByAlbumArtist)) {
      continue;
    }
    var swapWith = -1;
    for (var j = i + 1; j < result.length; j++) {
      if (!_conflictsAtIndex(result, precedingContext, i, result[j],
          constraints, groupByAlbumArtist)) {
        swapWith = j;
        break;
      }
    }
    if (swapWith != -1) {
      final tmp = result[i];
      result[i] = result[swapWith];
      result[swapWith] = tmp;
    }
    // No later track avoids the conflict — leave it in place.
  }
  return result;
}
