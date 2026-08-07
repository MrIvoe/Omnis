import 'dart:convert';
import 'dart:io';

import 'package:omnis_plugin_api/playlist.dart';
import 'package:path_provider/path_provider.dart';

// `Playlist` moved to `omnis_plugin_api` (see that package's
// `playlist.dart`) so `PluginContext.loadPlaylists()` can return it
// without depending on this file. Re-exported so every existing
// `import 'package:omnis/core/playlist_store.dart'` in this app keeps
// getting both `PlaylistStore` and `Playlist` unchanged.
export 'package:omnis_plugin_api/playlist.dart' show Playlist;

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
