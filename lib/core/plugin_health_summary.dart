import 'package:omnis/core/sandbox.dart';

/// How concerning a plugin's recent failures are — mirrors
/// `PluginManager`'s own auto-disable threshold (5 failures within 5
/// minutes triggers auto-disable) so a summary reader sees the exact
/// same signal that decides whether the app will step in on its own,
/// not a second, differently-tuned notion of "bad."
enum PluginHealthSeverity {
  /// At least one recorded failure, but below the auto-disable threshold.
  degraded,

  /// At or above the auto-disable threshold — this plugin either has
  /// already been auto-disabled, or is about to be on its next failure.
  critical,
}

/// One plugin's health, rolled up from its individual
/// [PluginHealthRecord]s — item 28's "no dedicated health-center page"
/// gap needs something coarser than the raw record list `plugins_page.dart`
/// already renders inline, one card per plugin rather than one per
/// failure.
class PluginHealthSummary {
  final String pluginId;
  final String pluginName;

  /// Every failure for this plugin in the records passed to
  /// [summarizeHealth], not just the ones inside the auto-disable window.
  final int failureCount;

  /// Failures within the auto-disable window — the same count
  /// `PluginManager._checkAutoDisable` itself computes.
  final int recentFailureCount;

  final DateTime mostRecentFailureAt;
  final String mostRecentReason;
  final PluginHealthSeverity severity;

  /// Whether the most recent record is a heartbeat timeout/failure
  /// (item 28's heartbeat gap) rather than a real hook — a plugin that's
  /// silently hung reads very differently to a user than one that's
  /// erroring on every track, even though both produce ordinary
  /// [PluginHealthRecord]s under the hood.
  final bool isUnresponsive;

  const PluginHealthSummary({
    required this.pluginId,
    required this.pluginName,
    required this.failureCount,
    required this.recentFailureCount,
    required this.mostRecentFailureAt,
    required this.mostRecentReason,
    required this.severity,
    required this.isUnresponsive,
  });
}

/// Groups [records] by plugin into one [PluginHealthSummary] each,
/// sorted worst-first (critical before degraded; within a tier, more
/// recent-window failures first; ties broken by the most recent failure
/// timestamp). Pure — no `PluginSandbox`/`PluginManager` dependency, so
/// it's fully unit-testable with a plain record list.
///
/// [window]/[criticalThreshold] default to the exact values
/// `PluginManager._autoDisableWindow`/`_autoDisableFailureThreshold`
/// use — duplicated rather than cross-imported (this file has no
/// dependency on `plugin_manager.dart` today), the same "small, stable
/// value, not worth a cross-file coupling" reasoning this codebase
/// already applies elsewhere (`library_cleanup_analyzer.dart`'s own
/// duplicated `_lossyCodecs`/`_fullyParsedExtensions`).
List<PluginHealthSummary> summarizeHealth(
  List<PluginHealthRecord> records, {
  DateTime? now,
  Duration window = const Duration(minutes: 5),
  int criticalThreshold = 5,
}) {
  final effectiveNow = now ?? DateTime.now();
  final byPlugin = <String, List<PluginHealthRecord>>{};
  for (final record in records) {
    byPlugin.putIfAbsent(record.pluginId, () => []).add(record);
  }

  final summaries = <PluginHealthSummary>[];
  for (final entry in byPlugin.entries) {
    final pluginRecords = List<PluginHealthRecord>.of(entry.value)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final mostRecent = pluginRecords.first;
    final recentCount = pluginRecords
        .where((r) => effectiveNow.difference(r.timestamp) <= window)
        .length;
    summaries.add(PluginHealthSummary(
      pluginId: entry.key,
      pluginName: mostRecent.pluginName,
      failureCount: pluginRecords.length,
      recentFailureCount: recentCount,
      mostRecentFailureAt: mostRecent.timestamp,
      mostRecentReason: mostRecent.reason,
      severity: recentCount >= criticalThreshold
          ? PluginHealthSeverity.critical
          : PluginHealthSeverity.degraded,
      isUnresponsive: mostRecent.hook == 'heartbeat',
    ));
  }

  summaries.sort((a, b) {
    if (a.severity != b.severity) {
      return a.severity == PluginHealthSeverity.critical ? -1 : 1;
    }
    final byRecentCount = b.recentFailureCount.compareTo(a.recentFailureCount);
    if (byRecentCount != 0) return byRecentCount;
    return b.mostRecentFailureAt.compareTo(a.mostRecentFailureAt);
  });
  return summaries;
}
