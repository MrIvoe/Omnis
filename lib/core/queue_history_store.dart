import 'dart:convert';
import 'dart:io';

import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/schema_versioning.dart';
import 'package:path_provider/path_provider.dart';

/// This store's current on-disk shape version — see `schema_versioning.dart`.
const _currentSchemaVersion = 1;
const _migrations = <int, SchemaMigration>{};

/// One past queue — either auto-recorded ([name] `null`, a rolling log
/// entry) or a user-named snapshot ([name] non-null, kept forever until
/// explicitly deleted). Stores full [BaseTrack] snapshots rather than
/// track ids: a queue commonly holds streaming/radio tracks that may
/// never be in any scanned library at all, so resolving by id against
/// the current library later could silently lose entries the same way
/// item 41's play-history join gap did before its `trackSnapshot` fix —
/// storing the real track data up front avoids that class of bug
/// entirely rather than needing a fallback for it.
class QueueHistoryEntry {
  final String id;
  final String? name;
  final DateTime createdAt;
  final List<BaseTrack> tracks;

  const QueueHistoryEntry({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.tracks,
  });

  bool get isSnapshot => name != null;

  /// The same [tracks] ids, in order — used only to detect "this is the
  /// same queue as the most recent auto-history entry," not persisted.
  List<String> get trackIds => tracks.map((t) => t.id).toList();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'tracks': tracks.map((t) => t.toJson()).toList(),
      };

  factory QueueHistoryEntry.fromJson(Map<String, dynamic> json) {
    final rawTracks = json['tracks'];
    final tracks = <BaseTrack>[];
    if (rawTracks is List) {
      for (final entry in rawTracks) {
        if (entry is! Map) continue;
        try {
          tracks.add(BaseTrack.fromJson(Map<String, dynamic>.from(entry)));
        } catch (_) {
          // One malformed track snapshot within an otherwise-good entry
          // is skipped, not fatal to the rest of the queue — the same
          // per-entry-defensive stance every JSON-backed store here
          // already holds, just one level deeper than usual.
          continue;
        }
      }
    }
    return QueueHistoryEntry(
      id: json['id'] as String,
      name: json['name'] as String?,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      tracks: tracks,
    );
  }
}

/// Persists queue history (an automatic, capped rolling log — spec §7's
/// "Queue history") and queue snapshots (user-named, never auto-evicted
/// — spec §7's "Queue snapshots") in one file, distinguished by
/// [QueueHistoryEntry.name]. Same atomic-write + schema-versioned-
/// envelope shape every other store in this app already uses.
class QueueHistoryStore {
  QueueHistoryStore._();

  static final QueueHistoryStore instance = QueueHistoryStore._();

  /// How many auto-recorded (non-snapshot) entries are kept — the
  /// oldest is evicted once a new one pushes past this. Snapshots are
  /// never counted against this cap or auto-evicted; only an explicit
  /// [deleteEntry] removes one.
  static const maxAutoHistoryEntries = 20;

  File? _file;

  Future<File> _getFile() async {
    if (_file != null) return _file!;
    final dir = await getApplicationDocumentsDirectory();
    _file = File('${dir.path}/omnis_queue_history.json');
    return _file!;
  }

  /// Load persisted entries, newest first. Returns an empty list if none
  /// exist or the file is corrupt.
  Future<List<QueueHistoryEntry>> load() async {
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
      final entries = <QueueHistoryEntry>[];
      for (final entry in migrated) {
        if (entry is! Map) continue;
        try {
          entries.add(
              QueueHistoryEntry.fromJson(Map<String, dynamic>.from(entry)));
        } catch (_) {
          continue;
        }
      }
      return entries;
    } catch (e) {
      return [];
    }
  }

  /// Persist [entries] to disk. Writes to a sibling `.tmp` file and
  /// renames it over the real path — atomic on the filesystems this app
  /// targets, the same crash-safety every other store's `save` already
  /// has.
  Future<void> save(List<QueueHistoryEntry> entries) async {
    try {
      final file = await _getFile();
      final json = jsonEncode(wrapVersioned(
          entries.map((e) => e.toJson()).toList(), _currentSchemaVersion));
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(json, flush: true);
      await tmp.rename(file.path);
    } catch (e) {
      // Best-effort persistence; a failure here must never crash the app.
    }
  }

  /// Records [queue] as a new auto-history entry, skipping empty queues
  /// and a queue that's identical (same track ids, same order) to the
  /// most recent auto-history entry — a reorder or minor mutation that
  /// still routes through `setQueue` shouldn't spam a "new" history
  /// entry for what's really the same queue continuing. Caps auto
  /// entries at [maxAutoHistoryEntries], evicting the oldest *auto*
  /// entry first — snapshots are never touched by this eviction.
  Future<List<QueueHistoryEntry>> recordAutoHistory(
      List<BaseTrack> queue) async {
    if (queue.isEmpty) return load();
    final existing = await load();
    QueueHistoryEntry? mostRecentAuto;
    for (final e in existing) {
      if (!e.isSnapshot) {
        mostRecentAuto = e;
        break;
      }
    }
    final newIds = queue.map((t) => t.id).toList();
    if (mostRecentAuto != null &&
        _sameOrder(mostRecentAuto.trackIds, newIds)) {
      return existing;
    }

    final entry = QueueHistoryEntry(
      id: 'qh_${DateTime.now().microsecondsSinceEpoch}',
      name: null,
      createdAt: DateTime.now(),
      tracks: List.of(queue),
    );

    final updated = [entry, ...existing];
    final snapshots = updated.where((e) => e.isSnapshot).toList();
    final autos = updated.where((e) => !e.isSnapshot).toList();
    final cappedAutos = autos.length > maxAutoHistoryEntries
        ? autos.sublist(0, maxAutoHistoryEntries)
        : autos;
    // Newest-first overall, snapshots and auto entries interleaved by
    // their own recency rather than grouped — matches how [load] and
    // the UI both just show one flat, newest-first list.
    final result = [...cappedAutos, ...snapshots]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    await save(result);
    return result;
  }

  /// Saves [queue] as a new, permanently-kept named snapshot.
  Future<List<QueueHistoryEntry>> saveSnapshot(
      String name, List<BaseTrack> queue) async {
    final existing = await load();
    final entry = QueueHistoryEntry(
      id: 'qs_${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      createdAt: DateTime.now(),
      tracks: List.of(queue),
    );
    final updated = [entry, ...existing];
    await save(updated);
    return updated;
  }

  /// Deletes one entry (auto-history or snapshot) by id.
  Future<List<QueueHistoryEntry>> deleteEntry(String id) async {
    final existing = await load();
    final updated = existing.where((e) => e.id != id).toList();
    await save(updated);
    return updated;
  }

  bool _sameOrder(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
