/// Pure due logic for automatic plugin-update checks (item 29's "no
/// automatic/background checking" gap). Kept free of `PluginManager`/
/// network I/O so it's fully unit-testable — `PluginManager.
/// maybeCheckForUpdatesAutomatically` is the thin I/O wrapper that
/// actually calls this. Same shape as `BackupScheduler.isDue`, kept as
/// its own independent class rather than sharing that one directly —
/// this codebase's established convention is one small scheduler per
/// concern, not a shared generic one.
class PluginUpdateScheduler {
  const PluginUpdateScheduler._();

  /// Whether an automatic update check should run now. `lastCheckAt ==
  /// null` (never checked before — a fresh install, or auto-check just
  /// enabled for the first time) is always due, rather than waiting a
  /// full [interval] for the first one.
  static bool isDue(
    DateTime? lastCheckAt,
    Duration interval,
    DateTime now,
  ) {
    if (lastCheckAt == null) return true;
    return now.difference(lastCheckAt) >= interval;
  }
}
