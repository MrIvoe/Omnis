import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/plugin_runtime.dart';
import 'package:omnis/plugin_api/service_interfaces.dart';

/// Host-authored adapters that let an external (sandboxed) plugin register
/// as a real `ServiceRegistry` provider — without ever giving sandboxed
/// code the raw `services.register<T>()` call itself.
///
/// `ServiceRegistry.register`/`get<T>()`/`getAll<T>()` key off the
/// *compile-time* generic `T`, not a runtime `Type` value, so a sandboxed
/// guest could never call `services.register<T>()` generically even if it
/// were bridged — there is no way to hand it a `Type` and have it satisfy
/// a later `get<ILyricsProvider>()` lookup. Rather than work around that,
/// `PluginManager` (trusted host code) registers one of these small, fixed,
/// reviewed adapters on the plugin's behalf instead — each one forwards to
/// exactly one guest hook with a narrow, single-purpose contract it cannot
/// exceed, gated by the plugin declaring the matching capability in its
/// manifest's `provides:` list (shown to the user before install, the same
/// way `permissions:` already is).
///
/// Scoped to the two safest, most naturally value-returning interfaces for
/// a first cut — [ILyricsProvider] (returns display text only) and
/// [IQueueBuilder] (returns a list of tracks to queue). `IFileTagWriter`/
/// `IMetadataProvider`/`IAudioAnalysisProvider` — whose results get
/// applied back into real library storage or real files — are explicitly
/// deferred to a future pass with its own review.
///
/// Both interfaces' methods are synchronous, so the guest hook backing
/// them must be too — an `async` guest hook returns a `Future` from
/// `PluginRuntime.callHook`, which fails the `is String`/`is List` checks
/// below and degrades to the safe default, the same as any other
/// unexpected/malformed hook result.

/// `provides:` catalog key → the fixed guest hook name(s) it requires.
/// Registration checks the runtime's own declared hooks (from
/// `createPlugin()`'s `hooks` list) against this, not just the manifest —
/// a manifest claiming a capability the plugin's own code never actually
/// implements is silently skipped, not registered half-broken.
const providedCapabilityHooks = {
  'lyrics': ['provideLyrics'],
  'queue_builder': ['queueBuilderSupportedQueries', 'buildQueueFor'],
};

class SandboxedLyricsProvider implements ILyricsProvider {
  final PluginRuntime runtime;

  const SandboxedLyricsProvider(this.runtime);

  static const _fallback = 'No lyrics added for this track yet.';

  @override
  String currentLyricFor(BaseTrack track, Duration position) {
    try {
      final result = runtime.callHook('provideLyrics', [
        track.toJson(),
        position.inMilliseconds,
      ]);
      if (result is String && result.isNotEmpty) return result;
    } catch (_) {
      // A throwing or misbehaving guest hook must never break the lyrics
      // display — degrade to the same fallback message an unregistered
      // provider's absence already shows.
    }
    return _fallback;
  }
}

class SandboxedQueueBuilder implements IQueueBuilder {
  final PluginRuntime runtime;
  @override
  final List<String> supportedQueries;

  const SandboxedQueueBuilder(this.runtime, this.supportedQueries);

  /// Fetches [supportedQueries] once, at registration time — see
  /// `PluginManager`'s registration site. Not re-queried per access: the
  /// set of queries a plugin understands isn't expected to change during
  /// a session, and re-entering the sandbox on every `getter` read would
  /// be wasteful for no real benefit.
  static List<String> fetchSupportedQueries(PluginRuntime runtime) {
    try {
      final result = runtime.callHook('queueBuilderSupportedQueries', []);
      if (result is List) return result.whereType<String>().toList();
    } catch (_) {
      // Falls through to empty below.
    }
    return const [];
  }

  @override
  List<BaseTrack> buildQueueFor(List<BaseTrack> tracks, String query) {
    try {
      final result = runtime.callHook('buildQueueFor', [
        tracks.map((t) => t.toJson()).toList(),
        query,
      ]);
      if (result is List) {
        return result
            .whereType<Map>()
            .map((m) => BaseTrack.fromJson(Map<String, dynamic>.from(m)))
            .toList();
      }
    } catch (_) {
      // A throwing or misbehaving guest hook degrades to "nothing for
      // this query" — the same contract IQueueBuilder already documents
      // for a provider that legitimately has nothing to offer.
    }
    return const [];
  }
}
