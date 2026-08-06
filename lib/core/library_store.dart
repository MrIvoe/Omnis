import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show compute;
import 'package:omnis/core/base_track.dart';
import 'package:path_provider/path_provider.dart';

/// Decodes a raw JSON string into tracks. A top-level function (not a
/// method/closure) because [compute] spawns a new isolate to run it in,
/// which requires a function with no captured state.
List<BaseTrack> _decodeTracks(String raw) {
  final decoded = jsonDecode(raw) as List<dynamic>;
  return decoded.map((e) => BaseTrack.fromJson(e as Map<String, dynamic>)).toList();
}

/// Encodes tracks into a raw JSON string — the [compute]-friendly
/// top-level counterpart to [_decodeTracks].
String _encodeTracks(List<BaseTrack> tracks) =>
    jsonEncode(tracks.map((t) => t.toJson()).toList());

/// Persists the scanned library to disk so it survives app restarts.
///
/// Tracks are stored as a JSON array in the app's documents directory.
/// On startup, the Library page loads from here instead of rescanning the
/// whole phone (which is slow and requires permission every time).
///
/// Encoding/decoding runs on a background isolate via [compute] — a real
/// library (thousands of tracks, each with a dozen-plus fields) makes
/// `jsonEncode`/`jsonDecode` and the per-track (de)serialization
/// expensive enough to visibly stutter the UI thread if run inline, and
/// `save()` is called after nearly every library mutation (add, delete,
/// tag edit, favorite), not just on load.
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
      return await compute(_decodeTracks, raw);
    } catch (e) {
      // Corrupt or unreadable cache: treat as empty, don't crash.
      return [];
    }
  }

  /// Persist the given tracks to disk.
  Future<void> save(List<BaseTrack> tracks) async {
    try {
      final file = await _getFile();
      final json = await compute(_encodeTracks, tracks);
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
