/// BaseTrack represents a unified track object for all types of media
class BaseTrack {
  /// Unique identifier for the track
  final String id;

  /// Track title
  final String title;

  /// Track artists
  final List<String> artists;

  /// Album name
  final String album;

  /// Track duration in seconds
  final int duration;

  /// Track number in album
  final int? trackNumber;

  /// Disc number
  final int? discNumber;

  /// Year of release
  final int? year;

  /// Genre list
  final List<String> genres;

  /// Track BPM (Beats Per Minute)
  final double? bpm;

  /// Key (e.g., "C# Minor")
  final String? key;

  /// Mood (e.g., "Happy", "Chill")
  final String? mood;

  /// Cover art URL or local path
  final String? coverArt;

  /// Track type (local, spotify, youtube)
  final TrackType type;

  /// Spotify ID if available
  final String? spotifyId;

  /// YouTube ID if available
  final String? youtubeId;

  /// Local file path if available
  final String? localPath;

  /// Stream URL if available (for YouTube/Spotify tracks)
  final String? streamUrl;

  /// ReplayGain values
  final ReplayGainValues? replayGain;

  /// Album artist — distinct from [artists] (the track's own performers),
  /// e.g. "Various Artists" for a compilation whose individual tracks
  /// each credit different performers. `null` when unknown; callers that
  /// want a display value should fall back to `artists.first`.
  final String? albumArtist;

  /// The kind of release this track's album is, when known.
  final ReleaseType? releaseType;

  /// Full release date, when known — more precise than [year], which
  /// stays for backward compatibility and as a fallback when only the
  /// year is known.
  final DateTime? releaseDate;

  /// When this track was first added to the user's library — not the
  /// release date. Real data on Android (MediaStore's own `date_added`);
  /// stamped by the scanner's caller on desktop/iOS, where there's no
  /// reliable native equivalent. `null` for a track scanned before this
  /// field existed.
  final DateTime? dateAdded;

  /// The local file's mtime as of the last scan that read its tags.
  /// `null` for a non-local track, or a local one scanned before this
  /// field existed. Lets a future scan skip re-reading a file's tags
  /// when this still matches the file's current mtime — see
  /// `MediaScanner._scanFilesystem`.
  final DateTime? fileModifiedAt;

  /// Short codec/format label sniffed from the file's own header bytes —
  /// e.g. "FLAC", "MP3", "PCM (WAV)". `null` for a non-local track, an
  /// unrecognized extension, or a local one scanned before this field
  /// existed. Distinct from an ID3/tag field: this comes from the actual
  /// audio stream's framing, not embedded metadata. See
  /// `AudioFormatReader` in the main app for how this is derived.
  final String? codec;

  /// Sample rate in Hz (e.g. 44100, 48000, 96000), when the codec's
  /// header made it available. `null` when unknown or not applicable.
  final int? sampleRateHz;

  /// Bit depth in bits per sample (e.g. 16, 24), meaningful for PCM/
  /// lossless formats (WAV, FLAC, AIFF). `null` for lossy formats where
  /// the concept doesn't apply, or when unknown.
  final int? bitDepth;

  /// Bitrate in kbps. For lossy formats this is a real average (computed
  /// from a VBR header's total frame/byte counts when present, not just
  /// the first frame's value); for lossless formats it's the file's
  /// actual average (file size / duration), not a fixed encoder setting.
  /// `null` when unknown.
  final int? bitrateKbps;

  /// Channel count (1 = mono, 2 = stereo, ...). `null` when unknown.
  final int? channels;

  /// The track's composer, distinct from [artists] (the performers) —
  /// classical/film-score/cover libraries commonly need this
  /// distinction. `null` when unknown; read from the same `TCOM`/
  /// `TXXX:COMPOSER` tag `TagEditorPlugin`'s own "Composer" edit field
  /// already reads and writes (`TrackTags.composer`) — this field is
  /// what makes that data reach the library model at all, previously
  /// edit-only and never scanned in.
  final String? composer;

  /// Constructor
  BaseTrack({
    required this.id,
    required this.title,
    required this.artists,
    required this.album,
    required this.duration,
    this.trackNumber,
    this.discNumber,
    this.year,
    this.genres = const [],
    this.bpm,
    this.key,
    this.mood,
    this.coverArt,
    required this.type,
    this.spotifyId,
    this.youtubeId,
    this.localPath,
    this.streamUrl,
    this.replayGain,
    this.albumArtist,
    this.releaseType,
    this.releaseDate,
    this.dateAdded,
    this.fileModifiedAt,
    this.codec,
    this.sampleRateHz,
    this.bitDepth,
    this.bitrateKbps,
    this.channels,
    this.composer,
  });

  /// Create a copy of this track with updated values
  BaseTrack copyWith({
    String? id,
    String? title,
    List<String>? artists,
    String? album,
    int? duration,
    int? trackNumber,
    int? discNumber,
    int? year,
    List<String>? genres,
    double? bpm,
    String? key,
    String? mood,
    String? coverArt,
    TrackType? type,
    String? spotifyId,
    String? youtubeId,
    String? localPath,
    String? streamUrl,
    ReplayGainValues? replayGain,
    String? albumArtist,
    ReleaseType? releaseType,
    DateTime? releaseDate,
    DateTime? dateAdded,
    DateTime? fileModifiedAt,
    String? codec,
    int? sampleRateHz,
    int? bitDepth,
    int? bitrateKbps,
    int? channels,
    String? composer,
  }) {
    return BaseTrack(
      id: id ?? this.id,
      title: title ?? this.title,
      artists: artists ?? this.artists,
      album: album ?? this.album,
      duration: duration ?? this.duration,
      trackNumber: trackNumber ?? this.trackNumber,
      discNumber: discNumber ?? this.discNumber,
      year: year ?? this.year,
      genres: genres ?? this.genres,
      bpm: bpm ?? this.bpm,
      key: key ?? this.key,
      mood: mood ?? this.mood,
      coverArt: coverArt ?? this.coverArt,
      type: type ?? this.type,
      spotifyId: spotifyId ?? this.spotifyId,
      youtubeId: youtubeId ?? this.youtubeId,
      localPath: localPath ?? this.localPath,
      streamUrl: streamUrl ?? this.streamUrl,
      replayGain: replayGain ?? this.replayGain,
      albumArtist: albumArtist ?? this.albumArtist,
      releaseType: releaseType ?? this.releaseType,
      releaseDate: releaseDate ?? this.releaseDate,
      dateAdded: dateAdded ?? this.dateAdded,
      fileModifiedAt: fileModifiedAt ?? this.fileModifiedAt,
      codec: codec ?? this.codec,
      sampleRateHz: sampleRateHz ?? this.sampleRateHz,
      bitDepth: bitDepth ?? this.bitDepth,
      bitrateKbps: bitrateKbps ?? this.bitrateKbps,
      channels: channels ?? this.channels,
      composer: composer ?? this.composer,
    );
  }

  /// Convert to map for storage
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'artists': artists,
      'album': album,
      'duration': duration,
      'trackNumber': trackNumber,
      'discNumber': discNumber,
      'year': year,
      'genres': genres,
      'bpm': bpm,
      'key': key,
      'mood': mood,
      'coverArt': coverArt,
      'type': type.name,
      'spotifyId': spotifyId,
      'youtubeId': youtubeId,
      'localPath': localPath,
      'streamUrl': streamUrl,
      'replayGain': replayGain?.toJson(),
      'albumArtist': albumArtist,
      'releaseType': releaseType?.name,
      'releaseDate': releaseDate?.toIso8601String(),
      'dateAdded': dateAdded?.toIso8601String(),
      'fileModifiedAt': fileModifiedAt?.toIso8601String(),
      'codec': codec,
      'sampleRateHz': sampleRateHz,
      'bitDepth': bitDepth,
      'bitrateKbps': bitrateKbps,
      'channels': channels,
      'composer': composer,
    };
  }

  /// Create from JSON
  factory BaseTrack.fromJson(Map<String, dynamic> json) {
    return BaseTrack(
      id: json['id'] as String,
      title: json['title'] as String,
      artists: List<String>.from(json['artists']),
      album: json['album'] as String,
      duration: json['duration'] as int,
      trackNumber: json['trackNumber'] as int?,
      discNumber: json['discNumber'] as int?,
      year: json['year'] as int?,
      genres: List<String>.from(json['genres']),
      bpm: json['bpm'] as double?,
      key: json['key'] as String?,
      mood: json['mood'] as String?,
      coverArt: json['coverArt'] as String?,
      type: TrackType.values.firstWhere((t) => t.name == json['type']),
      spotifyId: json['spotifyId'] as String?,
      youtubeId: json['youtubeId'] as String?,
      localPath: json['localPath'] as String?,
      streamUrl: json['streamUrl'] as String?,
      replayGain: json['replayGain'] != null
          ? ReplayGainValues.fromJson(json['replayGain'])
          : null,
      // Additive fields: absent in JSON written before they existed,
      // which must decode as null rather than throw.
      albumArtist: json['albumArtist'] as String?,
      releaseType: json['releaseType'] != null
          ? ReleaseType.values.firstWhere(
              (t) => t.name == json['releaseType'],
              orElse: () => ReleaseType.album,
            )
          : null,
      releaseDate: json['releaseDate'] != null
          ? DateTime.tryParse(json['releaseDate'] as String)
          : null,
      dateAdded: json['dateAdded'] != null
          ? DateTime.tryParse(json['dateAdded'] as String)
          : null,
      fileModifiedAt: json['fileModifiedAt'] != null
          ? DateTime.tryParse(json['fileModifiedAt'] as String)
          : null,
      codec: json['codec'] as String?,
      sampleRateHz: json['sampleRateHz'] as int?,
      bitDepth: json['bitDepth'] as int?,
      bitrateKbps: json['bitrateKbps'] as int?,
      channels: json['channels'] as int?,
      composer: json['composer'] as String?,
    );
  }

  /// Content equality for a `List<String>` — [artists]/[genres] compare
  /// with this rather than plain `==` in [operator ==]/[hashCode] below.
  /// Dart's `List` doesn't override `==`/`hashCode` for content equality
  /// (two structurally-identical lists built from separate literals are
  /// only `==` if they're the *same instance*), which previously made
  /// two structurally-identical [BaseTrack]s built from separate list
  /// literals never compare equal — a latent trap for any future code
  /// that assumes value equality (e.g. deduping via `Set<BaseTrack>`).
  static bool _listEquals(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is BaseTrack &&
        other.id == id &&
        other.title == title &&
        _listEquals(other.artists, artists) &&
        other.album == album &&
        other.duration == duration &&
        other.trackNumber == trackNumber &&
        other.discNumber == discNumber &&
        other.year == year &&
        _listEquals(other.genres, genres) &&
        other.bpm == bpm &&
        other.key == key &&
        other.mood == mood &&
        other.coverArt == coverArt &&
        other.type == type &&
        other.spotifyId == spotifyId &&
        other.youtubeId == youtubeId &&
        other.localPath == localPath &&
        other.streamUrl == streamUrl &&
        other.replayGain == replayGain &&
        other.albumArtist == albumArtist &&
        other.releaseType == releaseType &&
        other.releaseDate == releaseDate &&
        other.dateAdded == dateAdded &&
        other.fileModifiedAt == fileModifiedAt &&
        other.codec == codec &&
        other.sampleRateHz == sampleRateHz &&
        other.bitDepth == bitDepth &&
        other.bitrateKbps == bitrateKbps &&
        other.channels == channels &&
        other.composer == composer;
  }

  @override
  int get hashCode {
    // Object.hash() caps out at 20 positional arguments; this class has
    // more fields than that, so hashAll (no such limit) is required, not
    // just a style preference.
    return Object.hashAll([
      id,
      title,
      Object.hashAll(artists), // content hash, not List's identity-based one
      album,
      duration,
      trackNumber,
      discNumber,
      year,
      Object.hashAll(genres),
      bpm,
      key,
      mood,
      coverArt,
      type,
      spotifyId,
      youtubeId,
      localPath,
      streamUrl,
      replayGain,
      albumArtist,
      releaseType,
      releaseDate,
      dateAdded,
      fileModifiedAt,
      codec,
      sampleRateHz,
      bitDepth,
      bitrateKbps,
      channels,
      composer,
    ]);
  }
}

/// TrackType represents the source type of a track
enum TrackType {
  /// Local file
  local,

  /// Spotify track
  spotify,

  /// YouTube stream
  youtube,

  /// A live internet radio station (Icecast/Shoutcast-style continuous
  /// stream) — see `RadioPlugin` in `Omnis-Plugins`. Distinct from
  /// [youtube]/[spotify]: a station has no fixed [BaseTrack.duration]
  /// (always `0`) and no per-track identity of its own — [id] identifies
  /// the *station*, not a song.
  radio,

  /// A track streamed from a self-hosted OpenSubsonic-compatible media
  /// server (Navidrome, Airsonic, Subsonic itself, ...) — see
  /// `OpenSubsonicPlugin` in `Omnis-Plugins`. Unlike [spotify]/[youtube],
  /// this is directly playable: [BaseTrack.streamUrl] is the server's own
  /// real audio stream endpoint, not a metadata-only reference.
  subsonic,

  /// A track streamed from a self-hosted Jellyfin media server — see
  /// `JellyfinPlugin` in `Omnis-Plugins`. Like [subsonic], directly
  /// playable: [BaseTrack.streamUrl] is Jellyfin's own real audio stream
  /// endpoint. A distinct value from [subsonic] rather than reused for
  /// it — Jellyfin is its own protocol (session-token auth, different
  /// endpoint/field shapes), not an OpenSubsonic-compatible server.
  jellyfin,

  /// A track streamed from a self-hosted Plex Media Server — see
  /// `PlexPlugin` in `Omnis-Plugins`. Directly playable, like [subsonic]/
  /// [jellyfin]: [BaseTrack.streamUrl] points at the real media file
  /// Plex serves (its `Media[0].Part[0].key`), not a metadata-only
  /// reference. Its own distinct value — Plex is a third, incompatible
  /// protocol (a single account-scoped `X-Plex-Token`, not a per-request
  /// or per-session credential exchange the way [subsonic]/[jellyfin]
  /// each are).
  plex,

  /// A track served by a DLNA/UPnP media server on the local network —
  /// see `DlnaPlugin` in `Omnis-Plugins`. Directly playable, like every
  /// other self-hosted type here: [BaseTrack.streamUrl] is the real
  /// `<res>` URL a `ContentDirectory` `Browse` response points at. Its
  /// own distinct value — DLNA/UPnP is a fundamentally different *kind*
  /// of protocol from [subsonic]/[jellyfin]/[plex] (SSDP discovery +
  /// SOAP/XML, not a JSON REST API with a username/token), typically
  /// with **no authentication at all** on a trusted local network,
  /// unlike every other type here.
  dlna,

  /// A track streamed from a self-hosted Emby media server — see
  /// `EmbyPlugin` in `Omnis-Plugins`. Directly playable, like
  /// [jellyfin]/[subsonic]/[plex]: [BaseTrack.streamUrl] is Emby's own
  /// real audio stream endpoint. A distinct value from [jellyfin] even
  /// though the two protocols are close cousins (Jellyfin began as a
  /// 2018 fork of Emby and still shares its `X-Emby-Authorization`
  /// header name) — kept separate rather than reused because they are
  /// two different servers a user could each independently run, exactly
  /// the same reasoning [subsonic]/[jellyfin]/[plex] already established
  /// for each other despite some of them sharing REST-API shape too.
  emby,
}

/// ReleaseType represents the kind of release an album is.
enum ReleaseType {
  /// A standard full-length album.
  album,

  /// A single (typically one to a few tracks).
  single,

  /// An EP (extended play — more than a single, shorter than an album).
  ep,

  /// A compilation of tracks from multiple releases (often multiple
  /// album artists, hence [BaseTrack.albumArtist] commonly reading
  /// "Various Artists" for these).
  compilation,
}

/// ReplayGainValues stores ReplayGain information for a track
class ReplayGainValues {
  /// Track gain
  final double? trackGain;

  /// Album gain
  final double? albumGain;

  /// Track peak
  final double? trackPeak;

  /// Album peak
  final double? albumPeak;

  /// Constructor
  ReplayGainValues({
    this.trackGain,
    this.albumGain,
    this.trackPeak,
    this.albumPeak,
  });

  /// Convert to map for storage
  Map<String, dynamic> toJson() {
    return {
      'trackGain': trackGain,
      'albumGain': albumGain,
      'trackPeak': trackPeak,
      'albumPeak': albumPeak,
    };
  }

  /// Create from JSON
  factory ReplayGainValues.fromJson(Map<String, dynamic> json) {
    return ReplayGainValues(
      trackGain: json['trackGain'] as double?,
      albumGain: json['albumGain'] as double?,
      trackPeak: json['trackPeak'] as double?,
      albumPeak: json['albumPeak'] as double?,
    );
  }

  /// Same "found alongside the `BaseTrack` list-equality bug while fixing
  /// it" story — [BaseTrack.operator ==]/[BaseTrack.hashCode] compare
  /// [BaseTrack.replayGain] with plain `==`, which (absent an override
  /// here) is identity-based, the identical defect class the `artists`/
  /// `genres` fix addresses. Without this, two structurally-identical
  /// [ReplayGainValues] built from separate constructor calls — which is
  /// exactly what `ReplayGainValues.fromJson` produces on every load —
  /// would never compare equal to one another either.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReplayGainValues &&
          other.trackGain == trackGain &&
          other.albumGain == albumGain &&
          other.trackPeak == trackPeak &&
          other.albumPeak == albumPeak);

  @override
  int get hashCode => Object.hash(trackGain, albumGain, trackPeak, albumPeak);
}
