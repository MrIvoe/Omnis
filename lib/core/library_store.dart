import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show compute, visibleForTesting;
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/schema_versioning.dart';
import 'package:path_provider/path_provider.dart';

/// This store's current on-disk shape version — see
/// `schema_versioning.dart`. [_migrations] is empty because no real
/// migration has ever been needed yet (this is the payload's first
/// versioned release, item 4's "no schema migration system" gap); a
/// future format change adds an entry keyed by the version it upgrades
/// *from*.
const _currentSchemaVersion = 1;
const _migrations = <int, SchemaMigration>{};

/// Decodes a raw JSON string into tracks. A top-level function (not a
/// method/closure) because [compute] spawns a new isolate to run it in,
/// which requires a function with no captured state.
///
/// Each track entry is decoded independently and a failure skips just
/// that one entry — `BaseTrack.fromJson` hard-casts several fields
/// (`id`, `duration`, `type`, ...) and throws on anything malformed. A
/// single corrupted record among thousands (a bad write, a future schema
/// change, a hand-edited file) used to throw out of the `.map(...)`
/// here, which [load] would catch and treat as "the whole file is
/// unreadable" — silently reverting the *entire* persisted library to
/// empty over one bad entry. Same rationale as `PlaybackState.fromJson`'s
/// identical per-entry guard for its queue.
List<BaseTrack> _decodeTracks(String raw) {
  final decoded = jsonDecode(raw);
  final unwrapped = unwrapVersioned(decoded);
  final migrated = runMigrations(
      unwrapped.data, unwrapped.version, _currentSchemaVersion, _migrations);
  if (migrated is! List) return [];
  final tracks = <BaseTrack>[];
  for (final entry in migrated) {
    if (entry is! Map) continue;
    try {
      tracks.add(BaseTrack.fromJson(Map<String, dynamic>.from(entry)));
    } catch (_) {
      continue;
    }
  }
  return tracks;
}

/// Encodes tracks into a raw JSON string — the [compute]-friendly
/// top-level counterpart to [_decodeTracks].
String _encodeTracks(List<BaseTrack> tracks) => jsonEncode(wrapVersioned(
    tracks.map((t) => t.toJson()).toList(), _currentSchemaVersion));

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
///
/// Two failure modes this guards against:
///  - **A write killed partway through.** Android in particular kills
///    processes aggressively, and a `writeAsString` interrupted mid-write
///    leaves a truncated/corrupt `omnis_library.json` — the next [load]
///    would silently fall back to an empty library, discarding the whole
///    cache. [save] instead writes to a sibling `.tmp` file and
///    [File.rename]s it over the real path, which is atomic on the
///    filesystems this app targets: any given [load] sees either the old
///    complete file or the new complete file, never a partial one.
///  - **A write storm.** A batch tag edit or bulk favorite touching many
///    tracks previously called [save] once per track — every mutation
///    re-encoding and rewriting the *entire* library. [save] now debounces:
///    calls within [_debounceDelay] of each other collapse into a single
///    write of whatever the latest tracks were, and every caller's
///    `Future` still only resolves once that write actually happens (or
///    is superseded and dropped — see [save]'s doc).
class LibraryStore {
  LibraryStore._();

  static final LibraryStore instance = LibraryStore._();

  static const _debounceDelay = Duration(milliseconds: 500);

  File? _file;
  Timer? _debounceTimer;
  List<BaseTrack>? _pendingTracks;
  Completer<void>? _pendingCompleter;

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

  /// Persist the given tracks to disk, debounced by [_debounceDelay].
  ///
  /// A call within the debounce window of a previous, not-yet-flushed
  /// call replaces its pending tracks rather than queuing a second write
  /// — only the most recent snapshot ever actually reaches disk. Every
  /// caller in that window shares one `Future` that resolves once that
  /// single write completes, so `await save(tracks)` still means "this
  /// (or a newer) snapshot is now persisted," not "immediately."
  Future<void> save(List<BaseTrack> tracks) {
    _pendingTracks = tracks;
    _debounceTimer?.cancel();
    _pendingCompleter ??= Completer<void>();
    _debounceTimer = Timer(_debounceDelay, _flushPending);
    return _pendingCompleter!.future;
  }

  /// Cancels any pending debounce timer and writes immediately — call this
  /// before something that needs the on-disk file to genuinely be current
  /// right now (there is currently no caller; exposed for that future
  /// need and for tests).
  Future<void> flushPending() async {
    if (_debounceTimer == null) return;
    _debounceTimer!.cancel();
    await _flushPending();
  }

  Future<void> _flushPending() async {
    final tracks = _pendingTracks;
    final completer = _pendingCompleter;
    _pendingTracks = null;
    _pendingCompleter = null;
    _debounceTimer = null;
    if (tracks == null) {
      completer?.complete();
      return;
    }
    try {
      final file = await _getFile();
      final json = await compute(_encodeTracks, tracks);
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(json, flush: true);
      await tmp.rename(file.path);
    } catch (e) {
      // Best-effort persistence; a failure here must never crash the app.
    }
    completer?.complete();
  }

  /// Clear the persisted library.
  Future<void> clear() async {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _pendingTracks = null;
    _pendingCompleter?.complete();
    _pendingCompleter = null;
    try {
      final file = await _getFile();
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  /// Test-only: cancels any pending debounced write and drops the cached
  /// file handle, so each test file starts clean regardless of what an
  /// earlier test left pending — mirrors `LibraryRepository.resetForTesting`.
  @visibleForTesting
  void resetForTesting() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _pendingTracks = null;
    _pendingCompleter = null;
    _file = null;
  }
}
