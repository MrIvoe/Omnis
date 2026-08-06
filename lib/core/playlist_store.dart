import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// A named, user-created collection of tracks (by id), independent of the
/// live playback queue.
///
/// Every named competitor (Spotify, Poweramp, Musicolet, Namida) treats
/// "a playlist" and "what's currently queued to play" as two different
/// things — a playlist survives being played, a queue doesn't need to.
/// Omnis previously had no such concept at all: the "Playlists" tab was
/// just a read-only view of whatever the live queue happened to be.
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

/// Persists named playlists to disk, the same load/save shape as
/// `LibraryStore` — one JSON file in the app's documents directory, the
/// caller owns the in-memory list and decides when to save.
class PlaylistStore {
  PlaylistStore._();

  static final PlaylistStore instance = PlaylistStore._();

  File? _file;

  Future<File> _getFile() async {
    if (_file != null) return _file!;
    final dir = await getApplicationDocumentsDirectory();
    _file = File('${dir.path}/omnis_playlists.json');
    return _file!;
  }

  /// Load persisted playlists. Returns an empty list if none exist.
  Future<List<Playlist>> load() async {
    try {
      final file = await _getFile();
      if (!await file.exists()) return [];
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return [];
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((e) => Playlist.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      // Corrupt or unreadable file: treat as empty, don't crash.
      return [];
    }
  }

  /// Persist the given playlists to disk.
  Future<void> save(List<Playlist> playlists) async {
    try {
      final file = await _getFile();
      final json = jsonEncode(playlists.map((p) => p.toJson()).toList());
      await file.writeAsString(json);
    } catch (e) {
      // Best-effort persistence; a failure here must never crash the app.
    }
  }
}
