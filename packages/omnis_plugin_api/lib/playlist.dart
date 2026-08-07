/// A named, user-created collection of tracks (by id), independent of the
/// live playback queue.
///
/// Every named competitor (Spotify, Poweramp, Musicolet, Namida) treats
/// "a playlist" and "what's currently queued to play" as two different
/// things — a playlist survives being played, a queue doesn't need to.
///
/// Lives here rather than in `PlaylistStore` (where it originated) so a
/// plugin can read playlists via `PluginContext.loadPlaylists()` without
/// depending on the app's persistence layer — `PlaylistStore` itself
/// stays in the app and still owns reading/writing these to disk.
class Playlist {
  final String id;
  final String name;

  /// Track ids, in playlist order. Ids that no longer exist in the
  /// library are left in place rather than silently dropped — the UI
  /// filters them out at render time (see `PlaylistPage`), so a track
  /// that comes back (rescanned, replaced) rejoins the playlist instead
  /// of needing to be re-added by hand.
  final List<String> trackIds;
  final DateTime createdAt;

  const Playlist({
    required this.id,
    required this.name,
    required this.trackIds,
    required this.createdAt,
  });

  Playlist copyWith({String? name, List<String>? trackIds}) => Playlist(
        id: id,
        name: name ?? this.name,
        trackIds: trackIds ?? this.trackIds,
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'trackIds': trackIds,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };

  factory Playlist.fromJson(Map<String, dynamic> json) => Playlist(
        id: json['id'] as String,
        name: json['name'] as String,
        trackIds: List<String>.from(json['trackIds'] as List? ?? const []),
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          json['createdAt'] is int ? json['createdAt'] as int : 0,
        ),
      );
}
