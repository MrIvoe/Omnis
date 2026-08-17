/// Pure due logic for background plugin heartbeat checks — item 28's "no
/// heartbeat for a silently-hung plugin" gap. Kept free of `PluginManager`/
/// sandbox I/O so it's fully unit-testable — `PluginManager.
/// maybeRunHeartbeatsAutomatically` is the thin I/O wrapper that actually
/// calls this. Same shape as `PluginUpdateScheduler.isDue`/
/// `BackupScheduler.isDue`, kept as its own independent class rather than
/// sharing one of those directly — this codebase's established convention
/// is one small scheduler per concern, not a shared generic one.
class PluginHeartbeatScheduler {
  const PluginHeartbeatScheduler._();

  /// Whether an automatic heartbeat check should run now. `lastCheckAt ==
  /// null` (never checked before — a fresh install, or heartbeat
  /// monitoring just enabled for the first time) is always due, rather
  /// than waiting a full [interval] for the first one.
  static bool isDue(
    DateTime? lastCheckAt,
    Duration interval,
    DateTime now,
  ) {
    if (lastCheckAt == null) return true;
    return now.difference(lastCheckAt) >= interval;
  }
}
