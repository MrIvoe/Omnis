import 'dart:convert';
import 'dart:io';

import 'package:omnis/core/base_track.dart';
import 'package:omnis_plugin_api/playlist.dart';
import 'package:path_provider/path_provider.dart';

// `Playlist` moved to `omnis_plugin_api` (see that package's
// `playlist.dart`) so `PluginContext.loadPlaylists()` can return it
// without depending on this file. Re-exported so every existing
// `import 'package:omnis/core/playlist_store.dart'` in this app keeps
// getting both `PlaylistStore` and `Playlist` unchanged.
export 'package:omnis_plugin_api/playlist.dart' show Playlist;

/// Result of [PlaylistStore.exportM3U].
class M3UExportResult {
  /// The M3U8 file content, ready to write to disk.
  final String content;

  /// How many playlist entries were written.
  final int writtenCount;

  /// How many entries were skipped — a streaming-only track
  /// (Spotify/YouTube) has no local file an M3U player could open, or a
  /// track id no longer exists in the library at all.
  final int skippedCount;

  const M3UExportResult({
    required this.content,
    required this.writtenCount,
    required this.skippedCount,
  });
}

/// Result of [PlaylistStore.importM3U].
class M3UImportResult {
  /// The new playlist, built from whichever entries matched the current
  /// library. Not yet saved — the caller decides when to persist it
  /// (typically by adding it to their in-memory list and calling
  /// [PlaylistStore.save]), matching how every other playlist mutation
  /// in this app works.
  final Playlist playlist;

  /// How many entries matched a track in the current library.
  final int matchedCount;

  /// How many entries didn't match — a moved/renamed/missing file, or a
  /// track that was never scanned into this library.
  final int skippedCount;

  const M3UImportResult({
    required this.playlist,
    required this.matchedCount,
    required this.skippedCount,
  });
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
  ///
  /// Each entry is decoded independently and a failure skips just that
  /// one playlist — `Playlist.fromJson` hard-casts `id`/`name` and
  /// throws on anything malformed. A single corrupted record among many
  /// used to throw out of a bulk `.map(...)`, wiping *every* playlist —
  /// the user's own hand-curated content, with nothing to regenerate it
  /// from — over one bad entry. Same rationale as `LibraryStore`'s
  /// identical per-entry guard.
  Future<List<Playlist>> load() async {
    try {
      final file = await _getFile();
      if (!await file.exists()) return [];
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return [];
      final decoded = jsonDecode(raw) as List<dynamic>;
      final playlists = <Playlist>[];
      for (final entry in decoded) {
        if (entry is! Map) continue;
        try {
          playlists.add(Playlist.fromJson(Map<String, dynamic>.from(entry)));
        } catch (_) {
          continue;
        }
      }
      return playlists;
    } catch (e) {
      // Corrupt or unreadable file: treat as empty, don't crash.
      return [];
    }
  }

  /// Persist the given playlists to disk.
  ///
  /// Writes to a sibling `.tmp` file and renames it over the real path —
  /// atomic on the filesystems this app targets, so a crash/power-loss
  /// mid-write leaves the previous complete file intact rather than a
  /// truncated one (the same corruption `LibraryStore.save` guards
  /// against, and just as costly here: this is the user's own
  /// hand-built playlists, not something a rescan can regenerate).
  Future<void> save(List<Playlist> playlists) async {
    try {
      final file = await _getFile();
      final json = jsonEncode(playlists.map((p) => p.toJson()).toList());
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(json, flush: true);
      await tmp.rename(file.path);
    } catch (e) {
      // Best-effort persistence; a failure here must never crash the app.
    }
  }

  /// Renders [playlist] as M3U8 content, resolving each track id against
  /// [tracks]. Only local tracks with a real file path can be
  /// represented — a streaming-only entry (Spotify/YouTube) or a track
  /// id no longer in the library is skipped, not written as a broken
  /// reference.
  M3UExportResult exportM3U(Playlist playlist, List<BaseTrack> tracks) {
    final byId = {for (final t in tracks) t.id: t};
    final buffer = StringBuffer('#EXTM3U\n');
    var written = 0;
    var skipped = 0;
    for (final id in playlist.trackIds) {
      final track = byId[id];
      if (track == null || track.type != TrackType.local || track.localPath == null) {
        skipped++;
        continue;
      }
      final artist = track.artists.isNotEmpty ? track.artists.join(', ') : 'Unknown Artist';
      buffer.writeln('#EXTINF:${track.duration},$artist - ${track.title}');
      buffer.writeln(track.localPath);
      written++;
    }
    return M3UExportResult(
      content: buffer.toString(),
      writtenCount: written,
      skippedCount: skipped,
    );
  }

  /// Parses M3U/M3U8 [content] into a new playlist named [name], matching
  /// each file path against [tracks]' own [BaseTrack.localPath]. Falls
  /// back to matching on filename alone when the full path doesn't match
  /// — a playlist exported on a different machine (or a different
  /// library folder) commonly has paths that don't line up exactly, but
  /// the filenames usually still do. Comment lines (`#...`, including
  /// `#EXTINF` metadata) and blank lines are ignored; this only reads the
  /// path lines. Never throws — an unreadable line is just skipped.
  ///
  /// Not persisted — see [M3UImportResult.playlist]'s doc.
  M3UImportResult importM3U(
    String content,
    List<BaseTrack> tracks, {
    required String name,
  }) {
    final byPath = {
      for (final t in tracks)
        if (t.localPath != null) t.localPath!: t,
    };
    final byFilename = {
      for (final t in tracks)
        if (t.localPath != null) _basename(t.localPath!): t,
    };

    final trackIds = <String>[];
    var skipped = 0;
    for (final rawLine in const LineSplitter().convert(content)) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final track = byPath[line] ?? byFilename[_basename(line)];
      if (track != null) {
        trackIds.add(track.id);
      } else {
        skipped++;
      }
    }

    final playlist = Playlist(
      id: 'playlist_${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      trackIds: trackIds,
      createdAt: DateTime.now(),
    );
    return M3UImportResult(
      playlist: playlist,
      matchedCount: trackIds.length,
      skippedCount: skipped,
    );
  }

  String _basename(String path) => File(path).uri.pathSegments.isNotEmpty
      ? File(path).uri.pathSegments.last
      : path;
}
