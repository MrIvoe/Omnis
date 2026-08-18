import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Persists each local track's [computeFileFingerprint] result, keyed by
/// track id — item 5's rename-survives-a-rescan fix needs to know a
/// file's fingerprint *before* it disappears from its old path, which
/// means it has to be computed and saved the first time a track is seen,
/// not retroactively once a rename is suspected (by then the old path is
/// gone and unreadable). `LibraryPage._pickAndAdd` is the only writer:
/// every genuinely new local track gets its fingerprint stored here right
/// after being added, and a later rescan looks a disappeared track's
/// stored fingerprint up here to recognize its replacement.
///
/// Same load/save-JSON-file, caller-owns-the-map shape `PlaylistStore`/
/// `CustomMoodStore` already established — a plain `Map<String, String>`
/// needs no per-entry-defensive decoding the way a richer object would,
/// since a malformed entry here just means "no known fingerprint for that
/// id," the same as it never having been recorded at all.
class TrackFingerprintStore {
  TrackFingerprintStore._();

  static final TrackFingerprintStore instance = TrackFingerprintStore._();

  File? _file;

  Future<File> _getFile() async {
    if (_file != null) return _file!;
    final dir = await getApplicationDocumentsDirectory();
    _file = File('${dir.path}/omnis_track_fingerprints.json');
    return _file!;
  }

  /// Load the persisted id-to-fingerprint map. Returns an empty map if
  /// none exists or the file is corrupt — never throws.
  Future<Map<String, String>> load() async {
    try {
      final file = await _getFile();
      if (!await file.exists()) return {};
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return {
        for (final entry in decoded.entries)
          if (entry.key is String && entry.value is String)
            entry.key as String: entry.value as String,
      };
    } catch (e) {
      return {};
    }
  }

  /// Persist [fingerprints] to disk. Atomic write (sibling `.tmp` +
  /// rename), the same crash/power-loss-safe pattern every other JSON
  /// store in this app already uses.
  Future<void> save(Map<String, String> fingerprints) async {
    try {
      final file = await _getFile();
      final json = jsonEncode(fingerprints);
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(json, flush: true);
      await tmp.rename(file.path);
    } catch (e) {
      // Best-effort persistence; a failure here must never crash the app.
    }
  }

  /// Test-only: drops the cached file handle so each test starts clean.
  void resetForTesting() {
    _file = null;
  }
}
