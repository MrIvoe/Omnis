/// One track's aggregate play stats — not a per-play event log (unlike
/// `ScrobblePlugin`'s `PlayRecord` list, which exists for a different
/// purpose). The Home dashboard only ever needs "how many times, when
/// last, how far in," so storage stays bounded by library size instead of
/// growing forever.
///
/// Lives in `omnis_plugin_api` (not `play_history_store.dart`, where it
/// used to be defined) for the same reason `PlayRecord` does: the type
/// crosses the Omnis-app/`omnis_plugins` boundary. `PlayHistoryStore`
/// (core, always-on, writer side — it hooks the audio engine's own
/// track-lifecycle events, which only the app's core layer can see) stays
/// in the Omnis app, but `HomeDashboardPlugin` (the plugin that now owns
/// the page this data was collected for) reads it through
/// `PluginContext.loadRecentlyPlayed`/`loadMostPlayed`/
/// `loadContinueListening`/`loadMostSkipped`, which return this type.
class TrackPlayStats {
  final String trackId;
  final int playCount;
  final DateTime lastPlayedAt;

  /// How far into the track playback last got, for the Continue Listening
  /// section. Reset to zero on every fresh [PlayHistoryStore.recordPlay]
  /// (a new listen starts over), then updated by
  /// [PlayHistoryStore.recordPosition] as that listen progresses.
  final int lastPositionSeconds;

  /// The track's duration as of the last position update — kept alongside
  /// the position (rather than re-reading `BaseTrack.duration`, which is
  /// unreliable for filesystem-scanned tracks) so "10%–90% through" can be
  /// computed without a second lookup.
  final int durationSeconds;

  /// A full `BaseTrack.toJson()` snapshot, captured at [PlayHistoryStore
  /// .recordPlay] time — **only** for a track whose [BaseTrack.type] isn't
  /// [TrackType.local]. Item 41's "a station's history entry is recorded
  /// but never rendered" gap (and the same gap for every other
  /// non-scanned track type — Spotify/YouTube/Jellyfin/Plex/Subsonic/
  /// DLNA/Emby — which shares the identical root cause, not just radio):
  /// `HomeDashboardPage` previously joined every history entry against
  /// `LibraryRepository`'s scanned library purely by id, which a live,
  /// never-imported track (a radio station fetched from Radio Browser,
  /// a streaming-service track) is never part of — the play genuinely
  /// happened and was genuinely recorded, but there was nothing to
  /// display for it. `null` for a local track — its full metadata is
  /// already in the scanned library, so storing a second copy here would
  /// be pure duplication for the overwhelmingly common case.
  final Map<String, dynamic>? trackSnapshot;

  /// How many listens of this track ended before reaching
  /// [PlayHistoryStore.recordTrackEnd]'s completion threshold — item 16/
  /// MusicBee-comparison §37's "skip tracking" gap. A derived completion
  /// rate is `(playCount - skipCount) / playCount`, so this is the only
  /// new field needed rather than storing the rate itself. Defaults to
  /// `0` and decodes as `0` for any pre-existing record written before
  /// this field existed — the same additive-field convention every
  /// other optional field on this class already follows.
  final int skipCount;

  const TrackPlayStats({
    required this.trackId,
    required this.playCount,
    required this.lastPlayedAt,
    this.lastPositionSeconds = 0,
    this.durationSeconds = 0,
    this.trackSnapshot,
    this.skipCount = 0,
  });

  TrackPlayStats copyWith({
    int? playCount,
    DateTime? lastPlayedAt,
    int? lastPositionSeconds,
    int? durationSeconds,
    Map<String, dynamic>? trackSnapshot,
    int? skipCount,
  }) {
    return TrackPlayStats(
      trackId: trackId,
      playCount: playCount ?? this.playCount,
      lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
      lastPositionSeconds: lastPositionSeconds ?? this.lastPositionSeconds,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      trackSnapshot: trackSnapshot ?? this.trackSnapshot,
      skipCount: skipCount ?? this.skipCount,
    );
  }

  Map<String, dynamic> toJson() => {
        'trackId': trackId,
        'playCount': playCount,
        'lastPlayedAt': lastPlayedAt.toIso8601String(),
        'lastPositionSeconds': lastPositionSeconds,
        'durationSeconds': durationSeconds,
        if (trackSnapshot != null) 'trackSnapshot': trackSnapshot,
        'skipCount': skipCount,
      };

  factory TrackPlayStats.fromJson(Map<String, dynamic> json) {
    final snapshot = json['trackSnapshot'];
    return TrackPlayStats(
      trackId: json['trackId'] as String,
      playCount: json['playCount'] as int,
      lastPlayedAt: DateTime.parse(json['lastPlayedAt'] as String),
      lastPositionSeconds: json['lastPositionSeconds'] as int? ?? 0,
      durationSeconds: json['durationSeconds'] as int? ?? 0,
      trackSnapshot:
          snapshot is Map ? Map<String, dynamic>.from(snapshot) : null,
      skipCount: json['skipCount'] as int? ?? 0,
    );
  }
}
