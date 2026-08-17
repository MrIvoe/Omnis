import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/core/omnis_version.dart';
import 'package:omnis/core/semver.dart';

/// Pure due logic for automatic app-update checks — the About page's
/// "auto updater" toggle. Same shape as `PluginUpdateScheduler.isDue`/
/// `BackupScheduler.isDue`, kept as its own independent class rather
/// than sharing one of those directly — this codebase's established
/// convention is one small scheduler per concern.
class AppUpdateScheduler {
  const AppUpdateScheduler._();

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

/// Picks the newest real app-release version out of a GitHub "list tags"
/// API response (`decoded` is that endpoint's already-JSON-decoded
/// body — a list of `{"name": "v1.2.3", ...}` objects). Only tags
/// shaped exactly `vMAJOR.MINOR.PATCH` count as an app release — this
/// repo also hosts `plugin-api-vX.Y.Z` tags (the shared package
/// contract) and `Omnis-Plugins` has its own `vX.Y.Z` tags in a
/// *different* repository entirely, so a plain `v`-prefix check alone
/// would risk picking up something that isn't an Omnis app release at
/// all were this ever pointed at the wrong endpoint. Returns the
/// version string without its leading `v` (matching [omnisCoreVersion]'s
/// own bare format), or `null` if nothing in [decoded] matches — a
/// malformed/empty response degrades to "no update found," never a
/// crash or a false positive.
///
/// Pure — no network dependency, so it's fully unit-testable with a
/// plain decoded JSON value.
String? latestAppVersionFromTags(dynamic decoded) {
  if (decoded is! List) return null;
  final versionTag = RegExp(r'^v(\d+\.\d+\.\d+)$');
  String? best;
  for (final entry in decoded) {
    if (entry is! Map) continue;
    final name = entry['name'];
    if (name is! String) continue;
    final match = versionTag.firstMatch(name);
    if (match == null) continue;
    final version = match.group(1)!;
    if (best == null || compareVersions(version, best) > 0) {
      best = version;
    }
  }
  return best;
}

/// Checks GitHub for a newer Omnis app release than [omnisCoreVersion]
/// — the About page's "auto updater" gap: there was no mechanism at all
/// for the app to know a newer version of itself exists, only for
/// plugins (`PluginManager.checkForUpdates`). Same shape as
/// `PluginInstaller`: an injectable `http.Client` for testability, a
/// best-effort contract (network failure/non-200/malformed response all
/// degrade to "no update found," never a throw).
class AppUpdateService {
  AppUpdateService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _tagsUrl = 'https://api.github.com/repos/MrIvoe/Omnis/tags';
  static const _timeout = Duration(seconds: 10);

  /// The result of the most recent [checkForUpdate] call — a manual
  /// "Check for updates" tap or [maybeCheckForUpdateAutomatically] — so
  /// the About page can show the last-known answer immediately on open
  /// without re-fetching every time, the same "cache the last check"
  /// shape `PluginManager.lastKnownUpdates` already uses.
  String? lastKnownLatestVersion;

  /// Fetches the latest tagged app version and returns it only if it's
  /// genuinely newer than [omnisCoreVersion] — `null` otherwise (already
  /// up to date, or the check failed for any reason).
  Future<String?> checkForUpdate() async {
    try {
      final response =
          await _client.get(Uri.parse(_tagsUrl)).timeout(_timeout);
      if (response.statusCode != 200) return null;
      final latest = latestAppVersionFromTags(jsonDecode(response.body));
      if (latest == null) return null;
      return compareVersions(latest, omnisCoreVersion) > 0 ? latest : null;
    } catch (_) {
      return null;
    }
  }

  /// Runs [checkForUpdate] automatically if [settings] (defaults to
  /// [AppSettings.instance]) says it's enabled and due (via
  /// [AppUpdateScheduler.isDue]). A no-op when disabled or not yet due.
  /// On a real check, caches the result into [lastKnownLatestVersion]
  /// (also persisted to [AppSettings.lastKnownAppUpdateVersion] so the
  /// About page can show it immediately on a fresh launch, before this
  /// check has run again) and stamps
  /// [AppSettings.lastAppUpdateCheckAt] regardless of whether an update
  /// was actually found. Never throws — a failure here must never block
  /// startup, the same "denial degrades, never blocks boot" contract
  /// this app's other background tasks already follow.
  Future<void> maybeCheckForUpdateAutomatically({
    AppSettings? settings,
    DateTime? now,
  }) async {
    final appSettings = settings ?? AppSettings.instance;
    if (!appSettings.autoAppUpdateCheckEnabled) return;
    final effectiveNow = now ?? DateTime.now();
    final due = AppUpdateScheduler.isDue(
      appSettings.lastAppUpdateCheckAt,
      Duration(days: appSettings.autoAppUpdateCheckIntervalDays),
      effectiveNow,
    );
    if (!due) return;

    try {
      lastKnownLatestVersion = await checkForUpdate();
      appSettings.lastKnownAppUpdateVersion = lastKnownLatestVersion;
    } catch (_) {
      // Best-effort; a failed check must never crash the app.
    } finally {
      appSettings.lastAppUpdateCheckAt = effectiveNow;
    }
  }
}
