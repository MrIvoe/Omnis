/// Pure due/prune logic for automatic scheduled backups (item 4/50's
/// "automatic scheduled backups" gap). Kept free of `dart:io`/
/// `BackupService` so it's fully unit-testable — `BackupService.
/// maybeRunAutomaticBackup` is the thin I/O wrapper that actually calls
/// these.
class BackupScheduler {
  const BackupScheduler._();

  /// Whether an automatic backup should run now. `lastBackupAt == null`
  /// (never run before — a fresh install, or auto-backup just enabled
  /// for the first time) is always due, rather than waiting a full
  /// [interval] for the first one.
  static bool isDue(
    DateTime? lastBackupAt,
    Duration interval,
    DateTime now,
  ) {
    if (lastBackupAt == null) return true;
    return now.difference(lastBackupAt) >= interval;
  }

  /// Which of [existing] backup files to delete so only the [keepCount]
  /// most recent remain — [existing] is assumed already sorted, and is
  /// re-sorted defensively here newest-first by [createdAt] before
  /// slicing, so a caller doesn't need to pre-sort. Returns the files to
  /// delete, not the files to keep.
  static List<T> filesToPrune<T>(
    List<T> existing,
    int keepCount,
    DateTime Function(T) createdAt,
  ) {
    if (keepCount < 0) keepCount = 0;
    if (existing.length <= keepCount) return const [];
    final sorted = List<T>.of(existing)
      ..sort((a, b) => createdAt(b).compareTo(createdAt(a)));
    return sorted.sublist(keepCount);
  }
}
