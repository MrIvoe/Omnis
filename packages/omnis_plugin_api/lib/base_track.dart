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
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is BaseTrack &&
        other.id == id &&
        other.title == title &&
        other.artists == artists &&
        other.album == album &&
        other.duration == duration &&
        other.trackNumber == trackNumber &&
        other.discNumber == discNumber &&
        other.year == year &&
        other.genres == genres &&
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
        other.fileModifiedAt == fileModifiedAt;
  }

  @override
  int get hashCode {
    // Object.hash() caps out at 20 positional arguments; this class has
    // more fields than that, so hashAll (no such limit) is required, not
    // just a style preference.
    return Object.hashAll([
      id,
      title,
      artists,
      album,
      duration,
      trackNumber,
      discNumber,
      year,
      genres,
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
}
