import 'package:omnis/core/base_track.dart';

/// Pure due logic for periodic/scheduled background library rescans —
/// item 5's "no scheduled scans" gap, distinct from item 5's already-
/// closed filesystem watcher (live change detection while the app is
/// open, desktop-only) and distinct from item 50's playback scheduling.
/// Kept free of `MediaScanner`/`dart:io` so it's fully unit-testable —
/// `MainCore._maybeRunScheduledScan` is the thin I/O wrapper that
/// actually calls this. Same shape as `BackupScheduler.isDue`/
/// `PluginUpdateScheduler.isDue`, kept as its own independent class per
/// this codebase's established "one small scheduler per concern"
/// convention.
class LibraryScanScheduler {
  const LibraryScanScheduler._();

  /// Whether a scheduled scan should run now. `lastScanAt == null`
  /// (never run before — a fresh install, or auto-scan just enabled for
  /// the first time) is always due, rather than waiting a full
  /// [interval] for the first one.
  static bool isDue(
    DateTime? lastScanAt,
    Duration interval,
    DateTime now,
  ) {
    if (lastScanAt == null) return true;
    return now.difference(lastScanAt) >= interval;
  }
}

/// Which tracks from a fresh [scanned] result are genuinely new relative
/// to [current] — the pure half of the merge `MainCore` performs after
/// any scan (scheduled or filesystem-watcher-triggered); the other half
/// (pruning a local track whose file has since disappeared) needs real
/// file-existence I/O and stays in that caller. A track the scanner
/// didn't report a `dateAdded` for is stamped with [now] — the same
/// "just showed up, so 'added' means right now" convention the manual
/// "Add audio files" flow in `library_page.dart` already uses.
List<BaseTrack> newTracksFromScan(
  List<BaseTrack> current,
  List<BaseTrack> scanned, {
  DateTime Function() now = DateTime.now,
}) {
  final existingIds = current.map((t) => t.id).toSet();
  return scanned
      .where((t) => !existingIds.contains(t.id))
      .map((t) => t.dateAdded == null ? t.copyWith(dateAdded: now()) : t)
      .toList();
}
