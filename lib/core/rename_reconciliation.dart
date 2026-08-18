import 'package:omnis/core/base_track.dart';

/// Result of [reconcileRenamedTracks]: [renamed] tracks keep their
/// pre-rename id (so id-keyed history — favorites/ratings/play history/
/// playlist membership — stays attached), [trulyNew] tracks get their own
/// freshly-scanned id like any other newly-added track, and
/// [updatedFingerprints] is the fingerprint map the caller should persist
/// (a copy of the input map with matched-rename entries left alone,
/// newly-seen tracks added, and real-deletion entries pruned).
class RenameReconciliation {
  final List<BaseTrack> renamed;
  final List<BaseTrack> trulyNew;
  final Map<String, String> updatedFingerprints;

  const RenameReconciliation({
    required this.renamed,
    required this.trulyNew,
    required this.updatedFingerprints,
  });
}

/// Content-fingerprint-matches [candidateNewTracks] (files this scan
/// couldn't recognize by path) against [missingTracks] (previously known
/// local files that vanished from their old path this same scan) — item
/// 5's fix for a real bug: `MediaScanner` ids every local track as
/// `local:${file.path}` (see that class's own doc comment), so a plain
/// rename/move used to be indistinguishable from "the old file was
/// deleted and an unrelated new one was added," silently orphaning every
/// bit of history keyed by the old track id.
///
/// A pure function taking [fingerprints] (the already-loaded persisted
/// id-to-fingerprint map) and [computeFingerprint] (caller-supplied, the
/// same "pure function, caller does real I/O" shape
/// `smart_playlist_rule.dart`'s `RuleCondition.matches` and this app's own
/// `command_palette.dart`/`app_settings.dart` already established) rather
/// than reading `TrackFingerprintStore`/hashing files itself — lets this
/// get exercised by a plain unit test with a fake fingerprint function,
/// working around this codebase's documented `library_page.dart`-has-no-
/// widget-test-file gap (a real `AudioEngine` can't be safely constructed
/// inside `flutter test`, see `docs/OMNIS_2_0_MISSED_DEEP_PHASE.md`) —
/// this is the one piece of that page's logic important enough to need
/// real test coverage regardless.
///
/// Fingerprints have to already be on record for a match to work — a file
/// that's disappeared can't be re-read to fingerprint it retroactively —
/// so every genuinely new local track's fingerprint is recorded into
/// [RenameReconciliation.updatedFingerprints] here, keyed by its own id,
/// so a *future* rename of it can be recognized. A missing track whose
/// fingerprint was never recorded (added before this feature existed, or
/// non-local) can't be recognized as a rename source — it's treated as a
/// real deletion, the same as it always was, and its (nonexistent) entry
/// is simply absent, nothing to prune.
///
/// On a match: the renamed track keeps the OLD track's `id`/`dateAdded`
/// but takes every other field from the freshly-scanned data — the file
/// may have been re-tagged as part of the same move, so the new tags are
/// what's actually on disk now. Each missing track is matched to at most
/// one candidate, so two unrelated new files can't both claim the same
/// old identity.
Future<RenameReconciliation> reconcileRenamedTracks({
  required List<BaseTrack> missingTracks,
  required List<BaseTrack> candidateNewTracks,
  required Map<String, String> fingerprints,
  required Future<String?> Function(String path) computeFingerprint,
}) async {
  final updated = Map<String, String>.from(fingerprints);

  final missingByFingerprint = <String, BaseTrack>{};
  for (final track in missingTracks) {
    final fp = updated[track.id];
    if (fp != null) missingByFingerprint[fp] = track;
  }

  final renamed = <BaseTrack>[];
  final trulyNew = <BaseTrack>[];
  for (final candidate in candidateNewTracks) {
    final path = candidate.localPath;
    // Skip the per-file hashing pass entirely once there's nothing left
    // to match against.
    final fp = (path == null || missingByFingerprint.isEmpty)
        ? null
        : await computeFingerprint(path);
    final oldTrack = fp == null ? null : missingByFingerprint.remove(fp);
    if (oldTrack == null) {
      trulyNew.add(candidate);
      final newFp =
          fp ?? (path == null ? null : await computeFingerprint(path));
      if (newFp != null) updated[candidate.id] = newFp;
      continue;
    }
    renamed.add(candidate.copyWith(id: oldTrack.id, dateAdded: oldTrack.dateAdded));
    // The fingerprint already maps oldTrack.id -> fp; nothing to update
    // there since the id itself didn't change.
  }

  // Prune fingerprint entries for missing tracks that were NOT recognized
  // as a rename source — a real deletion, not a move, so this store
  // doesn't grow unboundedly across many scans over a library's life. A
  // missing track that *was* matched was already removed from
  // missingByFingerprint above, so it's simply absent from this set.
  for (final leftover in missingByFingerprint.values) {
    updated.remove(leftover.id);
  }

  return RenameReconciliation(
    renamed: renamed,
    trulyNew: trulyNew,
    updatedFingerprints: updated,
  );
}
