import 'package:omnis_plugin_api/audio_analysis_result.dart';
import 'package:omnis_plugin_api/base_track.dart';
import 'package:omnis_plugin_api/enrichment_result.dart';
import 'package:omnis_plugin_api/play_record.dart';

/// Capability contracts a plugin registers against on `ServiceRegistry`
/// (via `PluginContext.services`) instead of a caller depending on a
/// concrete plugin type. `ServiceRegistry` and `EventBus` are the generic
/// *mechanism* for registering/calling a capability, and that mechanism
/// is genuinely stable: it hasn't changed once across six interfaces
/// added so far, and has no reason to change for a seventh. The
/// interfaces themselves (`ILyricsProvider`, `IQueueBuilder`, ...) are
/// *not* that — they're capability-specific knowledge that keeps growing
/// as the plugin ecosystem grows. A plugin implements an interface from
/// here; a caller — UI code, another plugin — imports it from here too.
///
/// This file only names interfaces; it never names an implementation —
/// `LyricsPlugin` and `ScrobblePlugin` are today's only implementations of
/// two of these, but neither is referenced here.

/// Supplies lyric text for a track at a playback position.
///
/// Registered under this interface rather than looked up as a concrete
/// `LyricsPlugin` so a future alternate/additional source (LRCLIB,
/// embedded LRC, synced TTML) could register alongside or in place of it
/// without any caller — `NowPlayingPage`, a layout, another plugin —
/// changing.
abstract class ILyricsProvider {
  /// The lyric line/block to show for [track] at [position]. Returns a
  /// non-null, user-facing message even when nothing is stored yet (e.g.
  /// "No lyrics added for this track yet."), never `null` — so callers
  /// never need to special-case "no provider" vs. "provider has nothing"
  /// beyond checking whether a provider is registered at all.
  String currentLyricFor(BaseTrack track, Duration position);
}

/// Records and queries real play history — "recently played," "most
/// played."
///
/// Registered under this interface so a future alternate history source
/// (e.g. imported from a Last.fm account) could implement it too, and
/// anything reading history — the Playlists page's smart lists, a future
/// statistics dashboard — asks for the interface, not `ScrobblePlugin`
/// specifically.
abstract class IPlayHistoryProvider {
  /// Most recently played tracks, newest first, deduped to one entry per
  /// track.
  List<PlayRecord> recentlyPlayed({int limit});

  /// Track ids ordered by how often they've been played, most first.
  List<MapEntry<String, int>> mostPlayedIds({int limit});

  /// How many times [trackId] has been played.
  int playCountFor(String trackId);
}

/// Queries a track's star rating (0-5, 0 meaning unrated) — real signal
/// `RatingsPlugin` already collects but that, before this interface
/// existed, nothing outside that plugin itself could read: another
/// plugin has no way to reach a different plugin's concrete type, only
/// a registered capability. Added so `SmartPlaylistPlugin`'s rule
/// engine (§42) can evaluate a `rating:` condition — the same
/// caller-supplies-the-lookup shape `library_search.dart`'s `rating:`
/// search qualifier already established in the Omnis app itself,
/// mirrored here for the plugin side of the same idea.
abstract class IRatingsProvider {
  /// [trackId]'s rating, or `0` if it's never been rated — matches
  /// `RatingsPlugin.ratingOf`'s own convention exactly, so a caller
  /// never needs to special-case "no provider registered" differently
  /// from "registered, but this track has no rating."
  int ratingOf(String trackId);
}

/// Queries a track's favorited state — real signal `FavoritesPlugin`
/// already collects but that, before this interface existed, nothing
/// outside that plugin itself could read, the identical gap
/// [IRatingsProvider]'s own doc already describes for ratings. Added so
/// `QueuePresetPlugin`'s "Favorites Mix" preset (§39) can build a queue
/// from favorited tracks without depending on `FavoritesPlugin` by
/// concrete type.
abstract class IFavoritesProvider {
  /// Whether [trackId] is favorited — matches `FavoritesPlugin
  /// .isFavorite`'s own convention exactly.
  bool isFavorite(String trackId);

  /// Every currently favorited track id, in favorited order (oldest
  /// first) — matches the order `FavoritesPlugin`'s own persisted id
  /// list is stored in.
  List<String> favoriteIds();
}

/// A track's thumbs-up/down preference — MusicBee comparison §36:
/// distinct from [IRatingsProvider]'s 0-5 star scale, a coarse "yes/no"
/// signal some listeners prefer over picking a specific star count.
enum ThumbState { none, up, down }

/// Queries a track's thumbs-up/down state — the identical
/// nothing-outside-the-owning-plugin-can-read-this gap
/// [IRatingsProvider]/[IFavoritesProvider]'s own docs already describe,
/// mirrored here for a third, independent signal. `RatingsPlugin`
/// implements this alongside [IRatingsProvider] — the two are separate
/// interfaces because a track can be thumbed without ever being
/// star-rated and vice versa, not two views of the same value.
abstract class IThumbsProvider {
  /// [trackId]'s thumb state, or [ThumbState.none] if it's never been
  /// thumbed — matches `RatingsPlugin.thumbOf`'s own convention exactly.
  ThumbState thumbOf(String trackId);
}

/// Builds a ready-to-play queue for a named query (a mood/preset label
/// like `"Chill"` or `"Workout"`).
///
/// More than one implementation can be registered at once —
/// `SmartPlaylistPlugin` (matches curated `BaseTrack.mood` tags) and
/// `QueuePresetPlugin` (matches objective BPM/genre data, so it still
/// produces something on a freshly scanned library with no mood tags at
/// all) both do. Callers use `ServiceRegistry.getAll<IQueueBuilder>()`
/// and try each in registration order, keeping the first non-empty
/// result — see `HomePage._MoodsPageState._playMood`. Registration order
/// is therefore meaningful here (`bundled_plugins.dart` lists
/// `SmartPlaylistPlugin` before `QueuePresetPlugin` deliberately: a
/// curated mood match should win over an objective fallback whenever one
/// exists), unlike [ILyricsProvider]/[IPlayHistoryProvider], where only
/// the *primary* (`get<T>()`) registration is ever consulted.
abstract class IQueueBuilder {
  /// Query names this provider understands. Distinct providers can offer
  /// overlapping or entirely different sets.
  List<String> get supportedQueries;

  /// Builds a queue for [query] from [tracks]. Returns an empty list if
  /// this provider has nothing for that query — never throws.
  List<BaseTrack> buildQueueFor(List<BaseTrack> tracks, String query);
}

/// Looks up canonical/community metadata for a track from an external
/// source (MusicBrainz, Last.fm, Discogs today, all behind one provider —
/// `MetadataEnrichmentPlugin`).
abstract class IMetadataProvider {
  /// Whether this provider can usefully run right now (e.g. has a
  /// configured credential). A provider that's always `false` here is
  /// inert, not broken — callers should say so rather than silently
  /// doing nothing when a user taps "look up metadata."
  bool get isAvailable;

  /// Looks up [track]. Never throws — a failed or unreachable source
  /// returns an empty result, same as "not found."
  Future<EnrichmentResult> enrich(BaseTrack track);
}

/// Analyzes a track's actual audio content (BPM/key/mood via real signal
/// analysis) — as opposed to [IMetadataProvider], which looks things up
/// from external metadata, not the audio itself.
abstract class IAudioAnalysisProvider {
  /// Whether this provider can usefully run right now (e.g. has a
  /// configured analysis endpoint).
  bool get isAvailable;

  /// Analyzes [track]'s audio. Never throws — an unreachable/unconfigured
  /// source returns an empty result.
  Future<AudioAnalysisResult> analyze(BaseTrack track);
}

/// Writes a field directly into a local audio file's own tags.
///
/// Implemented by `TagEditorPlugin`. Exists so a plugin that fetched
/// something worth embedding in the file itself — today, `LyricsPlugin`'s
/// "write to file metadata" option for auto-fetched lyrics — can do so
/// without depending on `TagEditorPlugin` by concrete type, the same
/// "ask for the interface, not the plugin" pattern every other interface
/// here follows. A future writer (a different tag library, a native
/// implementation) could register in its place without `LyricsPlugin`
/// changing.
abstract class IFileTagWriter {
  /// Writes [lyrics] into [filePath]'s own tags. Returns `true` on
  /// success. Never throws — an unreadable/unwritable file returns
  /// `false`, the same "fail soft" contract [writeTags]-style methods use
  /// throughout this codebase.
  Future<bool> writeLyrics(String filePath, String lyrics);
}

/// Supplies levels for an animated visualizer.
///
/// Registered under this interface so a future real spectrum-analysis
/// source could replace or join the current UI-driven one
/// (`VisualizerPlugin`, which just_audio's lack of a PCM/FFT tap limits
/// to injected, not measured, levels) without `VisualizerBars` changing.
abstract class IVisualizerProvider {
  /// The most recently emitted levels, so a widget that subscribes late
  /// still renders something rather than flat bars.
  List<double> get latest;

  Stream<List<double>> get levels;
}

/// Looks up a representative photo for an artist by name.
///
/// Registered under this interface, not a concrete plugin type, so a
/// future alternate source (a different image API, a locally-curated set)
/// could replace or join `ArtistImagePlugin` without a caller changing.
/// Returns a URL rather than raw image bytes — the provider's job is
/// finding the photo, not fetching/decoding/caching it; callers (e.g.
/// `ArtistAvatar`) decide how to actually load it.
abstract class IArtistImageProvider {
  /// Whether this provider can usefully run right now.
  bool get isAvailable;

  /// Looks up a photo URL for [artistName]. Returns `null` when nothing is
  /// found, the lookup fails, or this provider is unavailable — never
  /// throws.
  Future<String?> imageUrlFor(String artistName);
}

/// Reports which output device (if any) is currently connected.
///
/// Implemented by `BluetoothPlaybackPlugin`. Exists so another plugin
/// that wants to react to a device connecting/disconnecting —
/// `EqualizerPlugin`'s per-device EQ presets today — can do so without
/// depending on `BluetoothPlaybackPlugin` by concrete type, the same
/// "ask for the interface, not the plugin" pattern every other interface
/// here follows.
abstract class IDeviceConnectivityProvider {
  /// The currently connected device's name, or `null` when nothing is
  /// connected.
  String? get connectedDeviceName;

  /// Emits every time [connectedDeviceName] changes.
  Stream<String?> get deviceChanges;
}

/// Turns a natural-language request into a real queue built from the
/// caller's own library — the spec's §21 "AI subsystem" ("a major
/// optional ecosystem," in its own words) starting from one deliberately
/// narrow slice: playlist creation from a prompt like "make me a
/// two-hour workout playlist." Natural-language search, metadata
/// cleanup, tagging, a conversational "library assistant," voice
/// control, and artist-similarity discovery are each real, separate
/// capabilities the spec names — none of them is this interface's job,
/// and cramming them in here would be exactly the kind of
/// keeps-growing-forever interface `service_interfaces.dart`'s own file
/// doc warns against.
///
/// Distinct from [IQueueBuilder] rather than folded into it:
/// [IQueueBuilder.buildQueueFor] is synchronous by design (built for
/// on-device, deterministic matching — `SmartPlaylistPlugin`'s mood-tag
/// substring match, `QueuePresetPlugin`'s genre/BPM thresholds), and a
/// real AI provider needs a genuine network round-trip, which a
/// synchronous contract can't accommodate at all.
///
/// Never required for normal functionality — the spec's own explicit
/// requirement for this whole subsystem. `ServiceRegistry` already
/// models "zero or more providers may exist" for every capability
/// interface here, so the app behaves identically whether zero, one, or
/// several `IAIProvider`s are registered.
abstract class IAIProvider {
  /// Whether this provider is ready to use right now (e.g. has a
  /// user-supplied API key configured) — the same `isAvailable` contract
  /// every other capability interface in this file uses, checked before
  /// offering any AI-powered UI at all.
  bool get isAvailable;

  /// Builds a queue for [prompt] by picking from [library] — never
  /// inventing a track that isn't actually in it. Returns an empty list,
  /// never throws, on any failure: no credential configured, a network
  /// error, a response that can't be parsed, or a provider that
  /// genuinely found nothing that fits.
  Future<List<BaseTrack>> buildPlaylistFromPrompt(
    String prompt,
    List<BaseTrack> library,
  );

  /// Finds tracks in [library] matching a plain-language [query] (e.g.
  /// "upbeat songs from the 90s I haven't played in a while") — item
  /// 43's "natural language search" gap, distinct from
  /// [buildPlaylistFromPrompt]: a search returns whatever genuinely
  /// matches in no particular order, not a curated listening sequence.
  /// Same never-invents-a-track/never-throws contract as
  /// [buildPlaylistFromPrompt]: an empty list on any failure — no
  /// credential configured, a network error, an unparseable response,
  /// or a provider that found nothing matching.
  Future<List<BaseTrack>> searchLibrary(
    String query,
    List<BaseTrack> library,
  );
}
