import 'dart:convert';
import 'dart:io';

import 'package:omnis/core/base_track.dart';
import 'package:path_provider/path_provider.dart';

/// Persists the scanned library to disk so it survives app restarts.
///
/// Tracks are stored as a JSON array in the app's documents directory.
/// On startup, the Library page loads from here instead of rescanning the
/// whole phone (which is slow and requires permission every time).
class LibraryStore {
  LibraryStore._();

  static final LibraryStore instance = LibraryStore._();

  File? _file;

  /// The JSON file that holds the library.
  Future<File> _getFile() async {
    if (_file != null) return _file!;
    final dir = await getApplicationDocumentsDirectory();
    _file = File('${dir.path}/omnis_library.json');
    return _file!;
  }

  /// Load the persisted library. Returns an empty list if none exists.
  Future<List<BaseTrack>> load() async {
    try {
      final file = await _getFile();
      if (!await file.exists()) return [];
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return [];
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((e) => BaseTrack.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      // Corrupt or unreadable cache: treat as empty, don't crash.
      return [];
    }
  }

  /// Persist the given tracks to disk.
  Future<void> save(List<BaseTrack> tracks) async {
    try {
      final file = await _getFile();
      final json = jsonEncode(tracks.map((t) => t.toJson()).toList());
      await file.writeAsString(json);
    } catch (e) {
      // Best-effort persistence; a failure here must never crash the app.
    }
  }

  /// Clear the persisted library.
  Future<void> clear() async {
    try {
      final file = await _getFile();
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }
}
