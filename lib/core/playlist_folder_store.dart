import 'dart:convert';
import 'dart:io';

import 'package:omnis/core/schema_versioning.dart';
import 'package:path_provider/path_provider.dart';

/// This store's current on-disk shape version — see `schema_versioning.dart`.
const _currentSchemaVersion = 1;
const _migrations = <int, SchemaMigration>{};

/// A named group a playlist can optionally belong to — one flat level,
/// no nesting: the "folders/groups" ask (item 13) doesn't call for
/// nested folders, and one level keeps both the model and the UI simple.
class PlaylistFolder {
  final String id;
  final String name;

  const PlaylistFolder({required this.id, required this.name});

  PlaylistFolder copyWith({String? name}) =>
      PlaylistFolder(id: id, name: name ?? this.name);

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  factory PlaylistFolder.fromJson(Map<String, dynamic> json) =>
      PlaylistFolder(id: json['id'] as String, name: json['name'] as String);
}

/// [PlaylistFolderStore.load]'s result: the folders themselves, plus
/// which folder (if any) each playlist belongs to.
class PlaylistFolderData {
  final List<PlaylistFolder> folders;

  /// playlistId -> folderId. A playlist with no entry here (the common
  /// case, and the only case before any folder has ever been created)
  /// isn't in any folder.
  final Map<String, String> assignments;

  const PlaylistFolderData(
      {required this.folders, required this.assignments});

  static const empty = PlaylistFolderData(folders: [], assignments: {});
}

/// Persists playlist folders/groups — kept in its own file rather than
/// folded into [PlaylistStore]'s own JSON, the same "one store per
/// concern" shape `LibraryStore`/`PlayHistoryStore`/`RecoveryJournal`
/// already follow. Deliberately not modeled as a field on `Playlist`
/// itself: that class lives in `omnis_plugin_api`, a package shared
/// (via git dependency) with `Omnis-Plugins` — changing it means a
/// cross-repo version bump for a purely organizational, UI-only concept
/// no plugin actually needs to know about.
class PlaylistFolderStore {
  PlaylistFolderStore._();

  static final PlaylistFolderStore instance = PlaylistFolderStore._();

  File? _file;

  Future<File> _getFile() async {
    if (_file != null) return _file!;
    final dir = await getApplicationDocumentsDirectory();
    _file = File('${dir.path}/omnis_playlist_folders.json');
    return _file!;
  }

  /// Load persisted folders/assignments. Returns [PlaylistFolderData.empty]
  /// if none exist or the file is corrupt — each folder entry and each
  /// assignment entry is decoded independently, so one malformed record
  /// can't wipe the rest (the same per-entry-defensive stance every
  /// other JSON-backed store in this app already holds).
  Future<PlaylistFolderData> load() async {
    try {
      final file = await _getFile();
      if (!await file.exists()) return PlaylistFolderData.empty;
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return PlaylistFolderData.empty;
      final decoded = jsonDecode(raw);
      final unwrapped = unwrapVersioned(decoded);
      final migrated = runMigrations(unwrapped.data, unwrapped.version,
          _currentSchemaVersion, _migrations);
      if (migrated is! Map) return PlaylistFolderData.empty;

      final folders = <PlaylistFolder>[];
      final rawFolders = migrated['folders'];
      if (rawFolders is List) {
        for (final entry in rawFolders) {
          if (entry is! Map) continue;
          try {
            folders.add(
                PlaylistFolder.fromJson(Map<String, dynamic>.from(entry)));
          } catch (_) {
            continue;
          }
        }
      }

      final assignments = <String, String>{};
      final rawAssignments = migrated['assignments'];
      if (rawAssignments is Map) {
        for (final entry in rawAssignments.entries) {
          if (entry.key is String && entry.value is String) {
            assignments[entry.key as String] = entry.value as String;
          }
        }
      }

      return PlaylistFolderData(folders: folders, assignments: assignments);
    } catch (e) {
      // Corrupt or unreadable file: treat as empty, don't crash.
      return PlaylistFolderData.empty;
    }
  }

  /// Persist [data] to disk. Writes to a sibling `.tmp` file and renames
  /// it over the real path — atomic on the filesystems this app targets,
  /// the same crash-safety every other store's `save` already has.
  Future<void> save(PlaylistFolderData data) async {
    try {
      final file = await _getFile();
      final json = jsonEncode(wrapVersioned({
        'folders': data.folders.map((f) => f.toJson()).toList(),
        'assignments': data.assignments,
      }, _currentSchemaVersion));
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(json, flush: true);
      await tmp.rename(file.path);
    } catch (e) {
      // Best-effort persistence; a failure here must never crash the app.
    }
  }
}
