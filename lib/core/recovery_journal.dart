import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:omnis/core/playback_state.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Persists [PlaybackState] snapshots for crash recovery and queue
/// restoration (§42 of the Omnis 2.0 product spec).
///
/// Design contract, the same "boring core" rule that governs every other
/// storage layer in this app:
///
///  * **Atomic writes.** The snapshot is written to a sibling temp file and
///    renamed over the real file only after the write completes. A crash
///    or power loss mid-write therefore leaves the *previous* good
///    snapshot intact, never a half-written one. This is the recovery
///    journal's entire reason to exist — a journal that can corrupt itself
///    while recovering from a crash is worse than no journal at all.
///  * **Corrupt/absent file ⇒ no resume.** [load] returns `null` on any
///    read/decode failure. Callers treat `null` as "nothing to resume,"
///    which is exactly what a fresh install or a wiped storage should see.
///  * **Best-effort writes.** A failed write is logged, never thrown —
///    losing the journal must never take down playback or the UI.
///  * **Time-decayed snapshots.** [removeIfStale] lets a caller drop
///    snapshots older than a cutoff (e.g. "don't offer resume from three
///    days ago"), so the journal never resurrects stale queues into the
///    user's face.
class RecoveryJournal {
  /// The single app-wide instance.
  static final RecoveryJournal instance = RecoveryJournal._();

  RecoveryJournal._();

  File? _fileOverride;

  /// The journal is stored alongside the other Omnis JSON stores
  /// (`omnis_playlists.json`, the library JSON) in the app documents
  /// directory.
  Future<File> _getFile() async {
    if (_fileOverride != null) return _fileOverride!;
    final dir = await getApplicationDocumentsDirectory();
    _fileOverride = File(p.join(dir.path, 'omnis_recovery_journal.json'));
    return _fileOverride!;
  }

  /// Test hook: point the journal at a specific file (e.g. a temp dir).
  @visibleForTesting
  set fileOverride(File file) {
    _fileOverride = file;
  }

  /// Test hook: clear the override so a later call resolves the real
  /// documents-directory file again.
  void clearFileOverride() => _fileOverride = null;

  /// Persist [state] atomically.
  Future<void> save(PlaybackState state) async {
    try {
      final file = await _getFile();
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(jsonEncode(state.toJson()), flush: true);
      // Rename is atomic on the same filesystem; the temp file shares the
      // journal's directory, so this is a same-volume rename.
      await tmp.rename(file.path);
    } catch (e) {
      debugPrint('Omnis: recovery journal write failed (non-fatal): $e');
    }
  }

  /// Load the most recent snapshot. Returns `null` when there is nothing
  /// to resume (no file, empty file, or corrupt/unparseable content).
  Future<PlaybackState?> load() async {
    try {
      final file = await _getFile();
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return PlaybackState.fromJson(Map<String, dynamic>.from(decoded));
    } catch (e) {
      debugPrint('Omnis: recovery journal read failed (treating as none): $e');
      return null;
    }
  }

  /// Discard the journal (after a successful resume, or when the user
  /// declines "resume where you left off?").
  Future<void> clear() async {
    try {
      final file = await _getFile();
      if (await file.exists()) {
        await file.delete();
      }
      final tmp = File('${file.path}.tmp');
      if (await tmp.exists()) {
        await tmp.delete();
      }
    } catch (e) {
      debugPrint('Omnis: recovery journal clear failed (non-fatal): $e');
    }
  }

  /// Whether a loaded snapshot is stale enough to be ignored — the user
  /// hasn't opened Omnis in [maxAge] and a queue from before that is more
  /// likely noise than a "pick up where I left off" moment.
  bool isStale(PlaybackState state,
      {Duration maxAge = const Duration(hours: 24)}) {
    final cutoff = DateTime.now().toUtc().subtract(maxAge);
    return state.savedAt.isBefore(cutoff);
  }

  /// Remove the journal entirely if the stored snapshot is older than
  /// [maxAge]. Returns `true` if it was removed.
  Future<bool> removeIfStale(
      {Duration maxAge = const Duration(hours: 24)}) async {
    final state = await load();
    if (state == null || !isStale(state, maxAge: maxAge)) return false;
    await clear();
    return true;
  }
}
