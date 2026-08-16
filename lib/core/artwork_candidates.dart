import 'package:omnis/core/base_track.dart';

/// Item 12/spec §47's "no bulk 'look up artwork for the whole library'
/// action" gap — the candidate-filtering half. A local track with no
/// [BaseTrack.coverArt] set is worth looking up; anything else (a
/// non-local track with nothing to write to, a local track missing a
/// path, or one that already has artwork) isn't, the same "don't
/// manufacture/attempt work that isn't needed" filtering style
/// `library_cleanup_analyzer.dart`'s own categories already use.
List<BaseTrack> tracksNeedingArtwork(List<BaseTrack> tracks) => tracks
    .where((t) =>
        t.type == TrackType.local &&
        t.localPath != null &&
        (t.coverArt == null || t.coverArt!.trim().isEmpty))
    .toList();
