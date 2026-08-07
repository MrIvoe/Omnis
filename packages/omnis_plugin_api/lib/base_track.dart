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
        other.replayGain == replayGain;
  }

  @override
  int get hashCode {
    return Object.hash(
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
    );
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
