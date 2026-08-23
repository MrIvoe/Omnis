import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/plugin_runtime.dart';
import 'package:omnis/plugin_api/lyric_line.dart';
import 'package:omnis/plugin_api/play_record.dart';
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
/// Scoped to the interfaces whose results are transient/display-only —
/// [ILyricsProvider] (display text), [IQueueBuilder] (a list of tracks
/// to queue, never persisted by the act of building it), and, added in
/// this pass, [IPlayHistoryProvider] (read-only query results) and
/// [IArtistImageProvider] (a URL string, not fetched/decoded/persisted
/// by this adapter). `IFileTagWriter`/`IMetadataProvider`/
/// `IAudioAnalysisProvider` are deliberately still excluded — their
/// results get *applied back* into real library storage or written into
/// real audio files by the caller (`library_page.dart`'s
/// `_applyEnrichment`/`_applyAnalysis`, `TagEditorPlugin` writes), so a
/// misbehaving sandboxed provider there could corrupt persisted state at
/// scale, not just show a wrong string on screen for one call. That's a
/// materially different trust decision and stays deferred to its own
/// review, not folded into this pass. [IVisualizerProvider] is also
/// still excluded, for an unrelated reason: it needs a genuine live
/// `Stream`, which `PluginRuntime.callHook`'s simple request/response
/// shape can't cleanly bridge without a polling `Timer` and its own
/// disposal lifecycle none of these adapters currently need.
///
/// Every guest hook backing these adapters is called synchronously via
/// `PluginRuntime.callHook`, which itself never returns a `Future` — an
/// `async` guest hook would return a `Future` from `callHook`, which
/// fails the `is String`/`is List`/`is int` checks below and degrades to
/// the safe default, the same as any other unexpected/malformed hook
/// result. [IArtistImageProvider.imageUrlFor] being `Future<String?>` on
/// the *interface* doesn't change this — its adapter just wraps a
/// synchronous `callHook` result in `async`.

/// `provides:` catalog key → the fixed guest hook name(s) it requires.
/// Registration checks the runtime's own declared hooks (from
/// `createPlugin()`'s `hooks` list) against this, not just the manifest —
/// a manifest claiming a capability the plugin's own code never actually
/// implements is silently skipped, not registered half-broken.
const providedCapabilityHooks = {
  'lyrics': ['provideLyrics'],
  'queue_builder': ['queueBuilderSupportedQueries', 'buildQueueFor'],
  'play_history': [
    'playHistoryRecentlyPlayed',
    'playHistoryMostPlayedIds',
    'playHistoryPlayCountFor',
  ],
  'artist_image': ['artistImageUrlFor'],
  'favorites': [
    'favoritesIsFavorite',
    'favoritesFavoriteIds',
    'favoritesSetFavorite',
    'favoritesWithSnapshots',
  ],
  'ratings': ['ratingsRatingOf'],
  'thumbs': ['thumbsThumbOf'],
  'online_search': ['onlineSearchIsConfigured', 'onlineSearchSearch'],
};

class SandboxedLyricsProvider implements ILyricsProvider, ISyncedLyricsProvider {
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

  /// A sandboxed plugin has no dedicated "does this exist" hook — the
  /// only signal available is whether [currentLyricFor] returns
  /// something other than its own fallback message. Reusing that hook
  /// here (rather than adding a second guest-hook contract for a cheaper
  /// existence check) is a first cut, same as [syncedLyricsFor]'s own
  /// documented always-null shortcut immediately below — a dedicated
  /// `hasLyrics` guest hook is real, separate work if this ever needs to
  /// be cheaper than calling `provideLyrics` once.
  @override
  bool hasLyrics(BaseTrack track) {
    try {
      return currentLyricFor(track, Duration.zero) != _fallback;
    } catch (_) {
      return false;
    }
  }

  /// Always `null` — a first cut. This adapter's whole job (see the file
  /// doc above) is bridging one narrow, fixed, reviewed guest hook per
  /// interface; [currentLyricFor]'s `provideLyrics` hook is scoped to
  /// display text only (a single `String`, never a structured line list),
  /// and there is no second guest hook here for a full synced-line list.
  /// Bridging one would need its own reviewed `provides:`/hook contract
  /// the way `provideLyrics` already has, which is real, separate work,
  /// not attempted here. Always returning `null` is also already correct
  /// behavior, not just a stub: every caller of [ILyricsProvider] treats
  /// `null` as "fall back to [currentLyricFor]'s single-block rendering",
  /// which is exactly what a sandboxed plugin's lyrics have ever offered.
  @override
  List<LyricLine>? syncedLyricsFor(BaseTrack track) => null;
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

class SandboxedPlayHistoryProvider implements IPlayHistoryProvider {
  final PluginRuntime runtime;

  const SandboxedPlayHistoryProvider(this.runtime);

  @override
  List<PlayRecord> recentlyPlayed({int limit = 20}) {
    try {
      final result = runtime.callHook('playHistoryRecentlyPlayed', [limit]);
      if (result is List) {
        return result
            .whereType<Map>()
            .map((m) => PlayRecord.fromJson(Map<String, dynamic>.from(m)))
            .toList();
      }
    } catch (_) {
      // A throwing or misbehaving guest hook degrades to "no history
      // from this provider" — the same fail-soft contract every other
      // sandboxed adapter in this file uses.
    }
    return const [];
  }

  @override
  List<MapEntry<String, int>> mostPlayedIds({int limit = 20}) {
    try {
      final result = runtime.callHook('playHistoryMostPlayedIds', [limit]);
      if (result is List) {
        final entries = <MapEntry<String, int>>[];
        for (final item in result) {
          // Guest code can only return JSON-shaped values through
          // callHook, not a real Dart MapEntry — a two-element
          // [trackId, count] list is the natural JSON encoding of one.
          if (item is List && item.length == 2 && item[1] is int) {
            entries.add(MapEntry(item[0].toString(), item[1] as int));
          }
        }
        return entries;
      }
    } catch (_) {
      // Falls through to empty below.
    }
    return const [];
  }

  @override
  int playCountFor(String trackId) {
    try {
      final result = runtime.callHook('playHistoryPlayCountFor', [trackId]);
      if (result is int) return result;
    } catch (_) {
      // Falls through to 0 below.
    }
    return 0;
  }
}

class SandboxedArtistImageProvider implements IArtistImageProvider {
  final PluginRuntime runtime;

  const SandboxedArtistImageProvider(this.runtime);

  @override
  bool get isAvailable => true;

  @override
  Future<String?> imageUrlFor(String artistName) async {
    try {
      final result = runtime.callHook('artistImageUrlFor', [artistName]);
      if (result is String && result.isNotEmpty) return result;
    } catch (_) {
      // A throwing or misbehaving guest hook degrades to "no photo
      // found," the same as ArtistImageProvider's own documented
      // contract for a legitimate miss.
    }
    return null;
  }
}

class SandboxedFavoritesProvider implements IFavoritesProvider {
  final PluginRuntime runtime;

  const SandboxedFavoritesProvider(this.runtime);

  @override
  bool isFavorite(String trackId) {
    try {
      final result = runtime.callHook('favoritesIsFavorite', [trackId]);
      if (result is bool) return result;
    } catch (_) {
      // Degrades to "not favorited" — the same default an unregistered
      // provider's absence already implies.
    }
    return false;
  }

  @override
  List<String> favoriteIds() {
    try {
      final result = runtime.callHook('favoritesFavoriteIds', []);
      if (result is List) return result.map((e) => e.toString()).toList();
    } catch (_) {
      // Falls through to empty below.
    }
    return const [];
  }

  @override
  Future<void> setFavorite(String trackId, bool favorite,
      {BaseTrack? track}) async {
    try {
      runtime.callHook('favoritesSetFavorite',
          [trackId, favorite, track?.toJson()]);
    } catch (_) {
      // A throwing guest hook must never surface as a crash to whoever
      // tapped the favorite toggle — the same fail-soft stance every
      // other sandboxed adapter in this file takes; the UI simply won't
      // see the change reflected next read.
    }
  }

  @override
  List<BaseTrack> favoritesWithSnapshots(List<BaseTrack> localTracks) {
    try {
      final result = runtime.callHook('favoritesWithSnapshots',
          [localTracks.map((t) => t.toJson()).toList()]);
      if (result is List) {
        return result
            .whereType<Map>()
            .map((m) => BaseTrack.fromJson(Map<String, dynamic>.from(m)))
            .toList();
      }
    } catch (_) {
      // Falls through to empty below.
    }
    return const [];
  }
}

class SandboxedRatingsProvider implements IRatingsProvider {
  final PluginRuntime runtime;

  const SandboxedRatingsProvider(this.runtime);

  @override
  int ratingOf(String trackId) {
    try {
      final result = runtime.callHook('ratingsRatingOf', [trackId]);
      if (result is int) return result;
    } catch (_) {
      // Falls through to 0 (unrated) below — matches
      // `IRatingsProvider.ratingOf`'s own "0 means unrated" contract.
    }
    return 0;
  }

  /// No dedicated guest hook exists for a *precise* rating read today —
  /// [ratingOf]'s existing `ratingsRatingOf` hook only ever returns a
  /// rounded int. Reusing it here (rather than losing precision
  /// silently) is honest about what's actually available: a sandboxed
  /// plugin's rating is only ever whole-star today.
  @override
  double preciseRatingOf(String trackId) => ratingOf(trackId).toDouble();

  /// Always a no-op — a first cut, same as [SandboxedLyricsProvider
  /// .syncedLyricsFor]'s documented always-null shortcut. No guest-hook
  /// bridge exists yet for *writing* a rating from a sandboxed plugin;
  /// building one (a `setRating`-style bridge function on
  /// `PluginSandboxBridge`, permission-gated the same way the existing
  /// queue/volume/state bridge functions are) is real, separate work.
  /// Silently doing nothing rather than throwing matches every other
  /// interface here's "never throws" contract.
  @override
  Future<void> setPreciseRating(String trackId, double rating) async {}
}

class SandboxedThumbsProvider implements IThumbsProvider {
  final PluginRuntime runtime;

  const SandboxedThumbsProvider(this.runtime);

  @override
  ThumbState thumbOf(String trackId) {
    try {
      final result = runtime.callHook('thumbsThumbOf', [trackId]);
      if (result is String) {
        return ThumbState.values
                .where((s) => s.name == result)
                .cast<ThumbState?>()
                .firstWhere((_) => true, orElse: () => null) ??
            ThumbState.none;
      }
    } catch (_) {
      // Falls through to none below.
    }
    return ThumbState.none;
  }

  /// Always a no-op — same reasoning and same future-work pointer as
  /// [SandboxedRatingsProvider.setPreciseRating].
  @override
  Future<void> setThumb(String trackId, ThumbState state) async {}
}

/// Search results are inherently untrusted output from a sandboxed
/// plugin, but the interface's own contract already treats every
/// result as a directly playable [BaseTrack] — the same trust level a
/// bundled `IOnlineSearchProvider` result already gets, since both are
/// only ever data (a URL/title/duration), never executable. Malformed
/// entries are simply dropped, not surfaced as a partial error, matching
/// [IOnlineSearchProvider.search]'s own "never throws" contract.
class SandboxedOnlineSearchProvider implements IOnlineSearchProvider {
  final PluginRuntime runtime;

  const SandboxedOnlineSearchProvider(this.runtime);

  @override
  String get providerName => runtime.name;

  @override
  bool get isConfigured {
    try {
      final result = runtime.callHook('onlineSearchIsConfigured', []);
      if (result is bool) return result;
    } catch (_) {
      // An unconfigured/misbehaving provider is hidden from the "Online"
      // tab entirely — the same as `isConfigured` returning false for
      // any other reason.
    }
    return false;
  }

  @override
  Future<List<BaseTrack>> search(String query, {int limit = 25}) async {
    try {
      var result = runtime.callHook('onlineSearchSearch', [query, limit]);
      if (result is Future) result = await result;
      if (result is List) {
        return result
            .whereType<Map>()
            .map((m) => BaseTrack.fromJson(Map<String, dynamic>.from(m)))
            .toList();
      }
    } catch (_) {
      // A throwing, timing-out, or misbehaving guest hook degrades to
      // "nothing found" — the same fail-soft contract every other
      // sandboxed adapter in this file uses.
    }
    return const [];
  }
}
