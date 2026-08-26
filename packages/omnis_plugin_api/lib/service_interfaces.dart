import 'dart:typed_data';

import 'package:omnis_plugin_api/audio_analysis_result.dart';
import 'package:omnis_plugin_api/base_track.dart';
import 'package:omnis_plugin_api/custom_mood.dart';
import 'package:omnis_plugin_api/enrichment_result.dart';
import 'package:omnis_plugin_api/lyric_line.dart';
import 'package:omnis_plugin_api/play_record.dart';
import 'package:omnis_plugin_api/smart_playlist_rule.dart';
import 'package:omnis_plugin_api/thumb_state.dart';
import 'package:omnis_plugin_api/track_tags.dart';

export 'package:omnis_plugin_api/thumb_state.dart' show ThumbState;

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

  /// Whether [track] has any lyrics stored for it at all — a cheaper,
  /// synchronous existence check a caller uses to decide whether to show
  /// a "has lyrics" indicator, without needing the full text
  /// [currentLyricFor] returns. Matches `LyricsPlugin.hasLyrics`'s own
  /// convention: `false` for "nothing stored," never a thrown error.
  bool hasLyrics(BaseTrack track);
}

/// Supplies the full ordered list of time-synced lyric lines for a
/// track, when a provider genuinely has them — letting a caller render
/// every line at once (Spotify-style scrolling lyrics), not just
/// [ILyricsProvider.currentLyricFor]'s single current line/block.
///
/// A separate interface from [ILyricsProvider], not a method added onto
/// it, deliberately — verified directly, not assumed: Dart's
/// `implements` clause requires a class to re-provide *every* member of
/// an interface it implements, even one given a default body in the
/// interface itself (unlike, say, Java's default interface methods,
/// which an implementing class inherits automatically without
/// overriding) — only `extends`/`with` actually inherit an
/// implementation, and neither existing [ILyricsProvider] implementer
/// can switch to those without a larger, unrelated refactor. Adding a
/// method straight onto [ILyricsProvider] — with or without a default
/// body — would therefore have been an instant compile break for every
/// existing implementer the moment this package's version bumped:
/// `LyricsPlugin` (`Omnis-Plugins` repo, `implements ILyricsProvider`,
/// picking this up is a separate, not-yet-landed follow-up in that
/// repo's own release) and `SandboxedLyricsProvider`
/// (`lib/core/plugin_sandbox_services.dart`, this app).
///
/// A caller checks `provider is ISyncedLyricsProvider` — the exact
/// "ask for the capability interface, not the concrete plugin type"
/// pattern [IRatingsProvider]/[IThumbsProvider]/[IFavoritesProvider]
/// above already establish for a signal not every provider of the base
/// interface has — and falls back to
/// [ILyricsProvider.currentLyricFor]'s existing single-block rendering
/// when a provider doesn't implement it, which is every provider today
/// until `LyricsPlugin` picks this up.
abstract class ISyncedLyricsProvider {
  /// The full ordered list of time-synced lines for [track], if this
  /// provider genuinely has synced lyrics for it. Returns `null` — never
  /// an empty list for "nothing synced" — when it only has (or has no)
  /// plain, untimed lyrics for [track], so a caller can use "is this
  /// null" as the one check that decides whether to fall back to
  /// [ILyricsProvider.currentLyricFor]'s single-block rendering.
  List<LyricLine>? syncedLyricsFor(BaseTrack track);
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

  /// [trackId]'s rating on the same 0-5 scale as [ratingOf], but as a
  /// precise `double` rather than a rounded `int` — the picker UI reads
  /// this to show partial-star state; `0.0` if never rated, matching
  /// `RatingsPlugin.preciseRatingOf`'s own convention exactly.
  double preciseRatingOf(String trackId);

  /// Sets [trackId]'s rating to [rating] (0.0-5.0). The write side,
  /// mirroring [IFavoritesProvider.setFavorite]'s own reasoning: every UI
  /// call site that used to reach `RatingsPlugin` by concrete type now
  /// goes through this interface, which is what makes the provider
  /// swappable at all.
  Future<void> setPreciseRating(String trackId, double rating);
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

  /// Marks [trackId] favorited/unfavorited — the write side, added
  /// alongside the sandbox's `favorites` bridge capability so a
  /// downloadable favorites provider can be reached the same way the
  /// bundled one always has been. Every UI call site that used to reach
  /// `FavoritesPlugin` by concrete type (`bundled<FavoritesPlugin>()`)
  /// now goes through this interface instead, which is what makes the
  /// provider swappable at all — a UI file no longer needs to know
  /// whether favorites are bundled or downloaded. [track], when given,
  /// is a snapshot for a non-local track (radio station, online search
  /// result) that [favoritesWithSnapshots] can later reconstruct even
  /// though it isn't in the scanned library.
  Future<void> setFavorite(String trackId, bool favorite, {BaseTrack? track});

  /// Every favorited track, in favorited order: a scanned-library match
  /// from [localTracks] when there is one, otherwise a reconstruction
  /// from the snapshot [setFavorite] captured for it. A favorited local
  /// track that's since been deleted, or a non-local one favorited
  /// before a snapshot existed for it, is silently skipped rather than
  /// producing a broken entry.
  List<BaseTrack> favoritesWithSnapshots(List<BaseTrack> localTracks);
}


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

  /// Sets [trackId]'s thumb state. Setting [ThumbState.none] clears it —
  /// matches `RatingsPlugin.setThumb`'s own convention exactly. The write
  /// side, same reasoning as [IRatingsProvider.setPreciseRating].
  Future<void> setThumb(String trackId, ThumbState state);
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

  /// Looks up cover art for [track] from this provider's source(s).
  /// Returns `null` — never throws — when nothing is found, the lookup
  /// fails, or this provider is unavailable, the same "fail soft"
  /// contract [enrich] already uses.
  Future<Uint8List?> lookupArtwork(BaseTrack track);
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

/// Searches a self-hosted media server's own catalog and returns real,
/// directly playable [BaseTrack]s (a genuine `streamUrl`, unlike
/// [IAIProvider.searchLibrary], which only ever searches the tracks
/// already scanned into the local library). Implemented by every
/// self-hosted connectivity plugin whose stream URL just works with
/// Omnis's own `AudioEngine` with no special handling — Ampache, Koel,
/// OpenSubsonic, Jellyfin, Plex, Emby today.
///
/// Deliberately **not** implemented by `YoutubeMusicImportPlugin` or
/// `SpotifyImportPlugin`: both return metadata-only tracks that
/// `AudioEngine` cannot actually play (see each plugin's own class doc
/// for why) — registering them here would silently misrepresent a
/// search result as playable when tapping it can't do what every other
/// registered provider's result does. The "Online" tab (`lib/ui`) gives
/// YouTube/Spotify their own dedicated, honestly-labeled entry points
/// instead of forcing them through this contract.
///
/// More than one provider can be registered at once, the same
/// `ServiceRegistry.getAll<T>()` shape [IQueueBuilder] already
/// establishes — the "Online" tab shows one entry per registered,
/// [isConfigured] provider, alongside Radio.
abstract class IOnlineSearchProvider {
  /// A short, user-facing name for this provider's tab/section — e.g.
  /// "Ampache", "Koel". Matches the plugin's own `MusicPlugin.name`.
  String get providerName;

  /// Whether this provider has enough configuration (server URL,
  /// credentials) to actually search right now. `false` hides this
  /// provider from the "Online" tab's selector entirely, rather than
  /// showing an entry that can only ever return nothing.
  bool get isConfigured;

  /// Searches this provider's server catalog for [query]. Returns an
  /// empty list — never throws — on any failure: not configured, a
  /// network error, an auth failure, or a search that genuinely found
  /// nothing.
  Future<List<BaseTrack>> search(String query, {int limit = 25});
}

/// Browses/searches Internet radio stations. Implemented by
/// `RadioPlugin`. A separate interface from [IOnlineSearchProvider]
/// deliberately — that one is scoped to self-hosted media-server
/// search (Ampache/Koel/OpenSubsonic/Jellyfin/Plex/Emby), all of which
/// share one "search this server's existing catalog" shape with no
/// concept of "top/popular results with no query," which radio
/// stations genuinely have and self-hosted servers don't.
abstract class IRadioProvider {
  /// The most popular stations, with no search query — Internet
  /// Radio's landing-page content. Returns an empty list, never
  /// throws, on any failure (network error, upstream directory down).
  Future<List<BaseTrack>> topStations({int limit = 30});

  /// Searches stations matching [query]. Returns an empty list, never
  /// throws, on any failure.
  Future<List<BaseTrack>> searchStations(String query, {int limit = 30});
}

/// Sets a track as the device ringtone. Implemented by `RingtonePlugin` —
/// registered under this interface, not the concrete type, the same
/// "ask for the capability, not the plugin" pattern every interface in
/// this file follows.
abstract class IRingtoneProvider {
  /// Attempts to set [track] as the device ringtone. Returns `true` on
  /// success. Never throws — see [lastError] for a user-facing reason on
  /// failure (unsupported platform, no local file, a platform-level
  /// error), matching `RingtonePlugin.setAsRingtone`'s own convention.
  Future<bool> setAsRingtone(BaseTrack track);

  /// A user-facing description of why the most recent [setAsRingtone]
  /// call failed, or `null` if the most recent call succeeded (or none
  /// has been made yet).
  String? get lastError;
}

/// Reads and writes every tag field a local audio file supports — the
/// broader read/write surface `IFileTagWriter` deliberately doesn't
/// cover (that interface is scoped to one narrow write, `writeLyrics`,
/// for a different caller — see its own doc comment). Implemented by
/// `TagEditorPlugin` alongside `IFileTagWriter`; both interfaces exist
/// independently because they serve different callers with different
/// needs, not because one supersedes the other.
abstract class ITagWriter {
  /// Writes any subset of the given fields into [filePath]'s own tags —
  /// every parameter left `null` is left unchanged in the file. Returns
  /// `true` on success. Never throws — an unreadable/unwritable file, or
  /// an unsupported platform, returns `false`.
  Future<bool> writeTags(
    String filePath, {
    String? title,
    String? artist,
    String? album,
    String? albumArtist,
    String? genre,
    String? year,
    String? track,
    String? disc,
    String? composer,
    String? comment,
    String? bpm,
    String? initialKey,
    String? mood,
    Uint8List? artworkBytes,
    Map<String, String>? extraFields,
  });

  /// Reads every tag from [filePath], as both flattened raw frames (for
  /// a "show everything" editor UI) and the convenience getters
  /// `TrackTags` exposes for the fields `BaseTrack` understands
  /// directly. Set [includeArtwork] to `false` to skip decoding the
  /// (potentially large) artwork frame when only text fields are needed.
  Future<TrackTags> readTags(String filePath, {bool includeArtwork = true});

  /// Whether [filePath] has an undo snapshot available right now — lets a
  /// caller (e.g. `TagEditorDialog`'s "Undo last edit" action) enable or
  /// disable itself without attempting the restore just to find out.
  bool hasUndoSnapshot(String filePath);

  /// Restores [filePath] to the tag values it had immediately before the
  /// most recent [writeTags] call that touched it (the snapshot
  /// [writeTags] itself records on every successful write). Returns
  /// `true` on success, `false` if there is no snapshot for this file or
  /// the restore itself fails — never throws.
  Future<bool> undoLastEdit(String filePath);
}

/// Reads and plays a user's saved rule-based smart playlists —
/// distinct from [IQueueBuilder] (which `SmartPlaylistPlugin` also
/// implements): that interface matches a *query name* like a mood label
/// against curated `BaseTrack.mood` tags, while this interface plays a
/// specific *saved rule* the user built and named through the plugin's
/// own settings UI. Implemented by `SmartPlaylistPlugin`.
abstract class ISmartPlaylistProvider {
  /// Every rule the user has saved, in no particular guaranteed order —
  /// a caller displaying them decides its own ordering (today,
  /// insertion/save order).
  List<SmartPlaylistRule> get savedRules;

  /// Builds a ready-to-play queue by evaluating the saved rule
  /// [ruleId] against [tracks]. Returns an empty list if no rule with
  /// that id is saved, or if the rule genuinely matches nothing — never
  /// throws.
  List<BaseTrack> buildQueueForRule(List<BaseTrack> tracks, String ruleId);

  /// Deletes the saved rule [ruleId]. A no-op — not an error — if no
  /// rule with that id exists.
  Future<void> deleteRule(String ruleId);
}

/// Opens the Home dashboard's "customize" bottom sheet (pick which
/// sections show, in what order) — reached from the command palette's
/// "Customize home" action. Registered by whichever plugin owns the Home
/// dashboard tab; before Tier 2, `home_page.dart` reached this directly
/// via a `GlobalKey<HomeDashboardPageState>` into a widget it constructed
/// itself, which stopped being possible once the dashboard became a
/// plugin-owned page `home_page.dart` only holds a `WidgetBuilder` for.
abstract class IHomeCustomizer {
  /// Opens the customize sheet. A no-op if the dashboard isn't currently
  /// visible/mounted — matches the previous `GlobalKey?.currentState?.`
  /// null-safe-no-op behavior exactly, so a stale command-palette action
  /// (dashboard plugin disabled after the palette opened) degrades
  /// silently rather than throwing.
  void openCustomizeSheet();
}

/// Plays a named preset mood or a user-created [CustomMood] directly, and
/// exposes the user's saved custom moods — reached from the command
/// palette's §37 "search everywhere" mood results and the pop-out
/// sidebar's "MY MOODS" section. Registered by whichever plugin owns the
/// Moods tab; before Tier 2, `home_page.dart` and
/// `global_sidebar_drawer.dart` both reached the Moods page directly via a
/// `GlobalKey<MoodsPageState>`, which stopped being possible once that
/// page became a plugin-owned one the app only holds a `WidgetBuilder`
/// for — the identical problem [IHomeCustomizer] solves for the Home
/// dashboard.
abstract class IMoodPlayer {
  /// Plays the built-in preset mood named [mood] — one of the queries
  /// some registered [IQueueBuilder] reports in its `supportedQueries`.
  /// A no-op if the Moods page isn't currently mounted, or if [mood]
  /// doesn't match a known preset — matches the previous null-safe
  /// `GlobalKey?.currentState?.` behavior exactly, so a stale caller (a
  /// command-palette action fired after the Moods plugin was disabled)
  /// degrades silently rather than throwing.
  void playMood(String mood);

  /// Plays a user-created custom mood, filtering the library through
  /// [CustomMood.matches]. Same no-op-when-unmounted contract as
  /// [playMood].
  void playCustomMood(CustomMood custom);

  /// Every custom mood the user has saved, so a caller outside the owning
  /// plugin (the pop-out sidebar, which lists moods by name in its "MY
  /// MOODS" section and needs the full object to hand back to
  /// [playCustomMood]) can resolve a mood name without reaching the
  /// plugin-private store that persists them. Returns an empty list —
  /// never throws — when no plugin owns the Moods tab, or when its page
  /// hasn't finished its initial load, in which case a pinned custom mood
  /// simply doesn't render rather than showing as a broken entry.
  List<CustomMood> get customMoods;
}

/// Contributes a self-contained embedded playback UI as one more section
/// of the "Online" tab — YouTube's own embedded IFrame player, Spotify's
/// own Connect remote-control panel. Both are deliberately **not**
/// [IOnlineSearchProvider]s (see that interface's own doc comment for
/// why: they only ever return metadata-only tracks `AudioEngine` can't
/// actually play), so this is a separate, narrower interface for exactly
/// "give me your existing settings widget to embed as a tab section."
///
/// Registered in `initialize()`/`enable()`, unregistered in
/// `disable()`/`dispose()` — the same lifecycle every capability
/// interface in this file follows — so the "Online" tab's provider list
/// (`ServiceRegistry.getAll<IEmbeddedPlaybackProvider>()`) already
/// reflects a plugin's current enabled state with no separate
/// `ManagedPlugin.enabled` check needed: a disabled plugin simply isn't
/// registered, the same "ask the registry, not a plugin's own enabled
/// flag" pattern [IOnlineSearchProvider]/[IRadioProvider] etc. already
/// establish.
///
/// Added for Tier 2 task 5 (extracting the Online tab into a bundled
/// plugin): the pre-extraction `OnlinePage` reached each of these two
/// plugins directly by concrete-type-adjacent lookup
/// (`PluginManager.byId('youtube_playback')`/`.enabled`) plus
/// `PluginManager.uiSlotForPlugin(...)`, neither of which a bundled
/// plugin (`omnis_plugins`, depending only on this package) can reach —
/// `ManagedPlugin`/`PluginManager` are both Omnis-app-only types, not
/// part of this package's surface. This interface is the
/// capability-interface replacement for that reach, the same shape
/// [IHomeCustomizer]/[IMoodPlayer] already established for their own
/// `GlobalKey`-into-app-owned-code reaches.
abstract class IEmbeddedPlaybackProvider {
  /// Short user-facing tab label — e.g. "YouTube", "Spotify". Matches
  /// the plugin's own `MusicPlugin.name`, the same convention
  /// [IOnlineSearchProvider.providerName] already follows for a name
  /// surfaced directly in the same tab's chip row.
  String get providerName;

  /// This provider's own `uiSlot('plugin_settings')` widget — the exact
  /// widget `PluginSettingsPage` would show for this plugin, embedded
  /// here as one section among several instead. Always a real Flutter
  /// `Widget` in practice; typed `dynamic` because this abstract surface
  /// never imports `package:flutter` directly, matching
  /// `MusicPlugin.uiSlot`'s own `dynamic` return type.
  dynamic buildSettingsSlot();
}

/// Read access to user-added custom radio stations
/// (`omnis_plugins`' `CustomRadioStationStore`/`CustomRadioStation`) for
/// the two Omnis-app call sites that need it — scheduled "play this
/// custom station" playback (`MainCore._checkPlaybackSchedules`) and the
/// scheduled-playback editor's "pick a target" list
/// (`PlaybackSchedulePage`) — without either one reaching a plugin-owned
/// store by a direct concrete import.
///
/// Registered in `initialize()`/`enable()`, unregistered in
/// `disable()`/`dispose()` — the same lifecycle every capability
/// interface in this file follows, looked up via
/// `pluginManager.services.get<ICustomRadioStationProvider>()`.
///
/// Added for a Tier 2 task 5 fix round: the initial extraction had
/// `main_core.dart`/`playback_schedule_page.dart` import
/// `package:omnis_plugins/custom_radio_station_store.dart` directly —
/// working (same file, same JSON, no data-path bug) but a violation of
/// this plan's binding constraint that a UI call site's need from an
/// extracted plugin goes through a capability interface, not a direct
/// import of plugin-private state. Task 4 hit the identical shape (the
/// app needing to read a plugin-owned store) and resolved it exactly
/// this way — [IMoodPlayer.customMoods] over a direct `CustomMoodStore`
/// import — for the same reason: that store is plugin-private state now,
/// and the app can't (and shouldn't) reach it directly.
///
/// Deliberately **not** exposing `CustomRadioStation` itself — that type
/// lives in `omnis_plugins`, not this package, so this package (which
/// the app depends on, and which depends on nothing plugin-side) has no
/// way to name it in a return type. [customStationSummaries] and
/// [trackForCustomStation] instead expose exactly the two shapes the
/// two real call sites need — an id+name pair for listing/labeling, and
/// a ready-to-queue [BaseTrack] for actually playing one — read off
/// those call sites directly rather than guessed at, the same "minimal
/// surface, not a speculative passthrough" restraint [IHomeCustomizer]/
/// [IMoodPlayer] already followed for their own narrow app-facing reads.
abstract class ICustomRadioStationProvider {
  /// Every user-added custom station's id and display name, in the order
  /// they were added — matches `CustomRadioStationStore.load()`'s own
  /// order. `PlaybackSchedulePage` uses this both to populate the
  /// schedule editor's "Playlist or station" dropdown and to resolve a
  /// saved schedule's `radioStationId` back to a display name; neither
  /// use needs the station's stream URL or creation time, so those
  /// fields deliberately aren't part of this surface. Returns an empty
  /// list — never throws — when nothing has ever been saved, matching
  /// `CustomRadioStationStore.load()`'s own empty-on-nothing-saved
  /// contract.
  ///
  /// A **positional** record — `id`/`name` in the type above are
  /// documentation-only hints, not named-field accessors (Dart only
  /// generates `.name`-style getters for a record type written with
  /// `{...}` named fields). Read each entry via `.$1` (id) / `.$2`
  /// (name), the same convention `AudioEngine.abRepeatRange`'s
  /// `(Duration a, Duration b)?` already establishes in this codebase.
  Future<List<(String id, String name)>> customStationSummaries();

  /// The real, playable [BaseTrack] for the custom station with
  /// [stationId] — matches `CustomRadioStation.toTrack()`'s own
  /// conversion exactly (a real `streamUrl`, `type: TrackType.radio`, no
  /// network call needed to resolve it). Returns `null` — never throws —
  /// when no station with that id exists any more (e.g. a schedule whose
  /// referenced station was since deleted), the same "a stale reference
  /// degrades to nothing rather than crashing" contract
  /// `MainCore._checkPlaybackSchedules`'s own doc comment already
  /// documents for a deleted playlist.
  Future<BaseTrack?> trackForCustomStation(String stationId);
}
