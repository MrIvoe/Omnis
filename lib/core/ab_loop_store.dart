import 'dart:convert';
import 'dart:io';

import 'package:omnis/core/schema_versioning.dart';
import 'package:path_provider/path_provider.dart';

/// This store's current on-disk shape version — see `schema_versioning.dart`.
const _currentSchemaVersion = 1;
const _migrations = <int, SchemaMigration>{};

/// A named A-B repeat loop, saved for a specific track — MusicBee
/// comparison §27 / spec §19's "saved/named loops" gap.
/// `AbRepeatController` (see that class) only ever holds one loop in
/// memory at a time and forgets it the moment it's cleared or a new A
/// point is marked; this is what lets a practicing/DJ loop survive past
/// that moment and be reapplied later without re-marking it by ear.
class SavedAbLoop {
  final String id;
  final String trackId;
  final String name;
  final Duration start;
  final Duration end;
  final DateTime createdAt;

  const SavedAbLoop({
    required this.id,
    required this.trackId,
    required this.name,
    required this.start,
    required this.end,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'trackId': trackId,
        'name': name,
        'startMs': start.inMilliseconds,
        'endMs': end.inMilliseconds,
        'createdAt': createdAt.toIso8601String(),
      };

  factory SavedAbLoop.fromJson(Map<String, dynamic> json) => SavedAbLoop(
        id: json['id'] as String,
        trackId: json['trackId'] as String,
        name: json['name'] as String,
        start: Duration(milliseconds: json['startMs'] as int),
        end: Duration(milliseconds: json['endMs'] as int),
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
}

/// Persists named A-B loops. Same atomic-write + schema-versioned-
/// envelope shape every other store in this app already uses (see
/// `CustomRadioStationStore` for the identical template). Deliberately
/// has no dependency on `AudioEngine`/`AbRepeatController` at all — it's
/// pure storage, fully unit-testable standalone.
class AbLoopStore {
  AbLoopStore._();

  static final AbLoopStore instance = AbLoopStore._();

  File? _file;

  Future<File> _getFile() async {
    if (_file != null) return _file!;
    final dir = await getApplicationDocumentsDirectory();
    _file = File('${dir.path}/omnis_ab_loops.json');
    return _file!;
  }

  /// Load every persisted loop, across all tracks, in the order they were
  /// saved. Returns an empty list if none exist or the file is corrupt —
  /// each entry is decoded independently, so one malformed record can't
  /// wipe the rest.
  Future<List<SavedAbLoop>> load() async {
    try {
      final file = await _getFile();
      if (!await file.exists()) return [];
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return [];
      final decoded = jsonDecode(raw);
      final unwrapped = unwrapVersioned(decoded);
      final migrated = runMigrations(unwrapped.data, unwrapped.version,
          _currentSchemaVersion, _migrations);
      if (migrated is! List) return [];
      final loops = <SavedAbLoop>[];
      for (final entry in migrated) {
        if (entry is! Map) continue;
        try {
          loops.add(SavedAbLoop.fromJson(Map<String, dynamic>.from(entry)));
        } catch (_) {
          continue;
        }
      }
      return loops;
    } catch (e) {
      return [];
    }
  }

  /// Every saved loop for [trackId], in the order they were saved.
  Future<List<SavedAbLoop>> loopsForTrack(String trackId) async {
    final all = await load();
    return all.where((l) => l.trackId == trackId).toList();
  }

  /// Persist [loops] to disk. Writes to a sibling `.tmp` file and renames
  /// it over the real path — atomic on the filesystems this app targets,
  /// the same crash-safety every other store's `save` already has.
  Future<void> save(List<SavedAbLoop> loops) async {
    try {
      final file = await _getFile();
      final json = jsonEncode(wrapVersioned(
          loops.map((l) => l.toJson()).toList(), _currentSchemaVersion));
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(json, flush: true);
      await tmp.rename(file.path);
    } catch (e) {
      // Best-effort persistence; a failure here must never crash the app.
    }
  }

  /// Saves a new named loop for [trackId] between [start] and [end].
  Future<List<SavedAbLoop>> add(
    String trackId,
    String name,
    Duration start,
    Duration end,
  ) async {
    final existing = await load();
    final loop = SavedAbLoop(
      id: 'ab_loop_${DateTime.now().microsecondsSinceEpoch}',
      trackId: trackId,
      name: name,
      start: start,
      end: end,
      createdAt: DateTime.now(),
    );
    final updated = [...existing, loop];
    await save(updated);
    return updated;
  }

  /// Deletes the saved loop with [id], if one exists. A harmless no-op
  /// otherwise.
  Future<List<SavedAbLoop>> delete(String id) async {
    final existing = await load();
    final updated = existing.where((l) => l.id != id).toList();
    await save(updated);
    return updated;
  }
}
