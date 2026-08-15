import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:omnis/core/playback_state.dart';
import 'package:omnis/core/schema_versioning.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// This store's current on-disk shape version — see
/// `schema_versioning.dart`. No real migration has ever been needed yet
/// (this is the file's first versioned release), so [_migrations] is
/// empty; a future format change adds an entry keyed by the version it
/// upgrades *from*, not a rewrite of the read/write logic below.
const _currentSchemaVersion = 1;
const _migrations = <int, SchemaMigration>{};

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

  /// Serializes every [save] call onto one chain — [MainCore] calls
  /// [save] from several unawaited, independently-firing call sites
  /// (pause, track change, a 20s heartbeat), any two of which can land
  /// close enough together to overlap. Without this, two concurrent
  /// writes race on the *same* `.tmp` path: both `writeAsString` calls
  /// target it, and whichever `rename` runs second finds nothing left to
  /// rename (the first call already moved it), which — while caught and
  /// non-fatal — silently drops that second, possibly more current,
  /// snapshot. Chaining onto whatever's already pending guarantees only
  /// one write is ever in flight, the same guarantee `LibraryStore.save`
  /// gets for free from its debounce timer.
  Future<void> _pendingSave = Future<void>.value();

  /// Persist [state] atomically.
  Future<void> save(PlaybackState state) {
    final next = _pendingSave.then((_) => _writeNow(state));
    _pendingSave = next;
    return next;
  }

  Future<void> _writeNow(PlaybackState state) async {
    try {
      final file = await _getFile();
      final tmp = File('${file.path}.tmp');
      final envelope = wrapVersioned(state.toJson(), _currentSchemaVersion);
      await tmp.writeAsString(jsonEncode(envelope), flush: true);
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
      final unwrapped = unwrapVersioned(decoded);
      final migrated = runMigrations(
          unwrapped.data, unwrapped.version, _currentSchemaVersion, _migrations);
      if (migrated is! Map) return null;
      return PlaybackState.fromJson(Map<String, dynamic>.from(migrated));
    } catch (e) {
      debugPrint('Omnis: recovery journal read failed (treating as none): $e');
      return null;
    }
  }

  /// Discard the journal (after a successful resume, or when the user
  /// declines "resume where you left off?").
  ///
  /// Chained onto the same [_pendingSave] queue as [save] — a resume/
  /// dismiss action landing at the same moment as the periodic
  /// heartbeat save must not race it (delete-then-recreate, or
  /// recreate-then-delete, depending on which happened to win).
  Future<void> clear() {
    final next = _pendingSave.then((_) => _clearNow());
    _pendingSave = next;
    return next;
  }

  Future<void> _clearNow() async {
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
