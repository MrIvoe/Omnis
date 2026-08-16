import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/core/backup_scheduler.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Thrown when a backup archive can't be built.
class BackupCreateException implements Exception {
  final String message;
  BackupCreateException(this.message);
  @override
  String toString() => message;
}

/// Result of [BackupService.restoreBackup] — always returned, never
/// thrown, so a caller doesn't need a try/catch to show the user what
/// happened (matches the "boring core, fail soft" contract every other
/// store in this app already follows).
class BackupRestoreResult {
  final bool success;
  final String? error;

  /// Which known files were actually written. Empty on failure — see
  /// [BackupService.restoreBackup]'s doc: nothing is ever partially
  /// applied.
  final List<String> restoredFiles;

  const BackupRestoreResult._(
      {required this.success, this.error, this.restoredFiles = const []});

  factory BackupRestoreResult.success(List<String> restoredFiles) =>
      BackupRestoreResult._(success: true, restoredFiles: restoredFiles);

  factory BackupRestoreResult.failure(String error) =>
      BackupRestoreResult._(success: false, error: error);
}

/// One-click backup/restore of Omnis's persisted data (§41/§48 of the
/// Omnis 2.0 product spec: "automatic backup... with validation before
/// overwriting anything").
///
/// Scope, deliberately: the JSON stores that live directly under the
/// app's documents directory — library, playlists, play history, and
/// the recovery journal. `AppSettings`/plugin-scoped `SharedPreferences`
/// state and plugin credentials are *not* included — bundling those
/// safely (secrets, per-plugin schemas, migration across app versions)
/// is a materially bigger, separate piece of work (closer to §47
/// "Universal export"); this is the "don't lose my library and
/// playlists" backup, not a full account export.
///
/// Every store this service touches already writes atomically
/// (temp-file + rename — see `LibraryStore`, `PlaylistStore`,
/// `PlayHistoryStore`, `RecoveryJournal`); [restoreBackup] reuses that
/// same pattern so a restore is exactly as crash-safe as an ordinary
/// save.
class BackupService {
  /// Bumped only if the manifest shape itself changes incompatibly —
  /// not on every release. [restoreBackup] rejects a manifest with a
  /// version it doesn't recognize rather than guessing at its shape.
  static const int manifestVersion = 1;

  /// The store files this service knows how to back up/restore. Order
  /// doesn't matter; a backup from a fresh install with (say) no
  /// playlists yet simply omits `omnis_playlists.json` — every file is
  /// optional, not required.
  static const List<String> knownFiles = [
    'omnis_library.json',
    'omnis_playlists.json',
    'omnis_play_history.json',
    'omnis_recovery_journal.json',
  ];

  Directory? _documentsDirOverride;

  /// Test hook: point the service at a specific directory instead of
  /// the real app documents directory.
  set documentsDirOverride(Directory dir) => _documentsDirOverride = dir;

  void clearDocumentsDirOverride() => _documentsDirOverride = null;

  Future<Directory> _documentsDir() async =>
      _documentsDirOverride ?? await getApplicationDocumentsDirectory();

  /// Builds a backup archive of every known store file that currently
  /// exists, as zip bytes ready to write to disk or hand to a share
  /// sheet. A fresh install with nothing persisted yet still produces a
  /// valid (near-empty) archive — an empty library isn't an error.
  Future<Uint8List> createBackup() async {
    final dir = await _documentsDir();
    final archive = Archive();
    final includedFiles = <String>[];

    for (final name in knownFiles) {
      final file = File(p.join(dir.path, name));
      if (!await file.exists()) continue;
      final bytes = await file.readAsBytes();
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
      includedFiles.add(name);
    }

    final manifestBytes = utf8.encode(jsonEncode({
      'version': manifestVersion,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'files': includedFiles,
    }));
    archive.addFile(
        ArchiveFile('manifest.json', manifestBytes.length, manifestBytes));

    final zipBytes = ZipEncoder().encode(archive);
    if (zipBytes == null) {
      throw BackupCreateException('Failed to build the backup archive.');
    }
    return Uint8List.fromList(zipBytes);
  }

  /// Restores a backup previously produced by [createBackup].
  ///
  /// Validates the whole archive — manifest present and a recognized
  /// version, every file it declares present in the zip, and every
  /// declared file's bytes are at least syntactically valid JSON —
  /// *before* writing a single byte to any real store file. A corrupt,
  /// foreign, or truncated zip therefore leaves the current library/
  /// playlists/history completely untouched rather than partially
  /// overwritten; only once every check has passed does it write each
  /// file, atomically, the same temp-file + rename every other store in
  /// this app already uses.
  Future<BackupRestoreResult> restoreBackup(List<int> zipBytes) async {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(zipBytes);
    } catch (e) {
      return BackupRestoreResult.failure(
          "That doesn't look like a valid backup file: $e");
    }

    final manifestFile = archive.findFile('manifest.json');
    if (manifestFile == null) {
      return BackupRestoreResult.failure(
          "This doesn't look like an Omnis backup — no manifest found.");
    }

    final Map<String, dynamic> manifest;
    try {
      final decoded =
          jsonDecode(utf8.decode(manifestFile.content as List<int>));
      if (decoded is! Map) {
        throw const FormatException('manifest is not a JSON object');
      }
      manifest = Map<String, dynamic>.from(decoded);
    } catch (e) {
      return BackupRestoreResult.failure('The backup manifest is corrupt: $e');
    }

    final version = manifest['version'];
    if (version != manifestVersion) {
      return BackupRestoreResult.failure(
          'This backup was made by an incompatible version of Omnis '
          '(manifest version $version, expected $manifestVersion).');
    }

    final declaredFiles =
        (manifest['files'] as List?)?.whereType<String>().toList() ??
            const [];

    // Validate every declared file before writing anything.
    final staged = <String, List<int>>{};
    for (final name in declaredFiles) {
      if (!knownFiles.contains(name)) {
        return BackupRestoreResult.failure(
            'The backup references an unrecognized file: "$name".');
      }
      final entry = archive.findFile(name);
      if (entry == null) {
        return BackupRestoreResult.failure(
            'The backup is missing a file it declared: "$name".');
      }
      final content = entry.content as List<int>;
      try {
        jsonDecode(utf8.decode(content));
      } catch (e) {
        return BackupRestoreResult.failure(
            '"$name" in the backup is not valid JSON: $e');
      }
      staged[name] = content;
    }

    // Every declared file validated — now actually write them.
    final dir = await _documentsDir();
    final written = <String>[];
    for (final entry in staged.entries) {
      final file = File(p.join(dir.path, entry.key));
      final tmp = File('${file.path}.tmp');
      try {
        await tmp.writeAsBytes(entry.value, flush: true);
        await tmp.rename(file.path);
        written.add(entry.key);
      } catch (e) {
        // A failure partway through writing (disk full, permission
        // denied on this one file) still means everything in [written]
        // so far was already restored — report exactly what happened
        // rather than claiming total success or total failure.
        return BackupRestoreResult.failure(
            'Restored ${written.length} file(s) before failing to write '
            '"${entry.key}": $e');
      }
    }

    return BackupRestoreResult.success(written);
  }

  /// How many rotated automatic-backup files to keep on disk — see
  /// [maybeRunAutomaticBackup].
  static const int autoBackupKeepCount = 5;

  /// Runs an automatic backup if [settings] (defaults to
  /// [AppSettings.instance]) says one is enabled and due (via
  /// [BackupScheduler.isDue]) — item 4/50's "automatic scheduled
  /// backups" gap: previously [createBackup] only ever ran from
  /// `BackupSettingsPage`'s two manual buttons, with no timer or
  /// interval anywhere.
  ///
  /// Writes straight to `<documents>/backups/omnis-backup-<timestamp>
  /// .zip` — no file-picker dialog, since this runs unattended (e.g. at
  /// app startup), unlike [createBackup] itself (which just returns
  /// bytes for a caller's own manual-save flow). Prunes older automatic
  /// backups down to [autoBackupKeepCount] (newest kept, via
  /// [BackupScheduler.filesToPrune]), then stamps
  /// [AppSettings.lastAutoBackupAt]. Never throws — a failure here must
  /// never block startup, the same "denial degrades, never blocks boot"
  /// contract this app's permission-gating already follows.
  Future<void> maybeRunAutomaticBackup({
    AppSettings? settings,
    DateTime? now,
  }) async {
    final appSettings = settings ?? AppSettings.instance;
    if (!appSettings.autoBackupEnabled) return;
    final effectiveNow = now ?? DateTime.now();
    final due = BackupScheduler.isDue(
      appSettings.lastAutoBackupAt,
      Duration(days: appSettings.autoBackupIntervalDays),
      effectiveNow,
    );
    if (!due) return;

    try {
      final dir = await _documentsDir();
      final backupsDir = Directory(p.join(dir.path, 'backups'));
      if (!await backupsDir.exists()) {
        await backupsDir.create(recursive: true);
      }

      final bytes = await createBackup();
      final stamp = effectiveNow
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final file = File(p.join(backupsDir.path, 'omnis-backup-$stamp.zip'));
      await file.writeAsBytes(bytes, flush: true);

      final existing = await backupsDir
          .list()
          .where((e) => e is File && e.path.endsWith('.zip'))
          .cast<File>()
          .toList();
      final withDates = [
        for (final f in existing) _TimestampedFile(f, await f.lastModified())
      ];
      final toDelete = BackupScheduler.filesToPrune(
          withDates, autoBackupKeepCount, (f) => f.modifiedAt);
      for (final entry in toDelete) {
        try {
          await entry.file.delete();
        } catch (_) {
          // Best-effort pruning; a stray extra file is harmless.
        }
      }

      appSettings.lastAutoBackupAt = effectiveNow;
    } catch (e) {
      // Best-effort; never let an automatic backup failure block startup.
    }
  }
}

class _TimestampedFile {
  final File file;
  final DateTime modifiedAt;
  const _TimestampedFile(this.file, this.modifiedAt);
}
