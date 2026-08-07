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
