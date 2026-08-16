import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/core/backup_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Builds a raw zip (not via [BackupService.createBackup]) from a
/// name -> text-content map, for tests that need to hand
/// [BackupService.restoreBackup] a deliberately malformed/foreign
/// archive that the real create path would never produce.
List<int> _buildRawZip(Map<String, String> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    final bytes = utf8.encode(entry.value);
    archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
  }
  return ZipEncoder().encode(archive)!;
}

/// Covers §41/§48 of the Omnis 2.0 product spec ("automatic backup...
/// with validation before overwriting anything"). The core guarantee
/// under test throughout: [BackupService.restoreBackup] either restores
/// everything it declared, or touches nothing at all — never a partial
/// apply from a bad backup.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory sourceDir;
  late Directory targetDir;
  late BackupService service;

  setUp(() async {
    sourceDir = await Directory.systemTemp.createTemp('omnis_backup_src');
    targetDir = await Directory.systemTemp.createTemp('omnis_backup_dst');
    service = BackupService()..documentsDirOverride = sourceDir;
  });

  tearDown(() async {
    if (await sourceDir.exists()) await sourceDir.delete(recursive: true);
    if (await targetDir.exists()) await targetDir.delete(recursive: true);
  });

  Future<void> writeStoreFile(Directory dir, String name, Object content) =>
      File('${dir.path}/$name').writeAsString(jsonEncode(content));

  group('createBackup', () {
    test('a fresh install with no store files produces a valid archive '
        'with just a manifest declaring no files', () async {
      final bytes = await service.createBackup();

      final restoreService = BackupService()..documentsDirOverride = targetDir;
      final result = await restoreService.restoreBackup(bytes);

      expect(result.success, isTrue);
      expect(result.restoredFiles, isEmpty);
    });

    test('includes every store file that exists, omits ones that '
        "don't", () async {
      await writeStoreFile(sourceDir, 'omnis_library.json', [
        {'id': '1', 'title': 'Song'}
      ]);
      await writeStoreFile(sourceDir, 'omnis_playlists.json', []);
      // omnis_play_history.json and omnis_recovery_journal.json
      // deliberately absent.

      final bytes = await service.createBackup();
      final restoreService = BackupService()..documentsDirOverride = targetDir;
      final result = await restoreService.restoreBackup(bytes);

      expect(result.success, isTrue);
      expect(result.restoredFiles.toSet(),
          {'omnis_library.json', 'omnis_playlists.json'});
    });
  });

  group('restoreBackup — round trip', () {
    test('a full backup restores byte-for-byte identical content into a '
        'different directory', () async {
      await writeStoreFile(sourceDir, 'omnis_library.json', [
        {'id': '1', 'title': 'Song One'},
        {'id': '2', 'title': 'Song Two'},
      ]);
      await writeStoreFile(sourceDir, 'omnis_playlists.json', [
        {'id': 'p1', 'name': 'Road Trip'}
      ]);
      await writeStoreFile(sourceDir, 'omnis_play_history.json', {
        '1': {'trackId': '1', 'playCount': 3}
      });
      await writeStoreFile(sourceDir, 'omnis_recovery_journal.json',
          {'currentIndex': 0, 'queue': []});

      final bytes = await service.createBackup();
      final restoreService = BackupService()..documentsDirOverride = targetDir;
      final result = await restoreService.restoreBackup(bytes);

      expect(result.success, isTrue);
      expect(result.restoredFiles.toSet(), BackupService.knownFiles.toSet());

      for (final name in BackupService.knownFiles) {
        final original = await File('${sourceDir.path}/$name').readAsString();
        final restored = await File('${targetDir.path}/$name').readAsString();
        expect(restored, original, reason: '$name should round-trip exactly');
      }
    });

    test('restoring does not leave a .tmp file behind for any restored '
        'store', () async {
      await writeStoreFile(sourceDir, 'omnis_library.json', []);
      final bytes = await service.createBackup();
      final restoreService = BackupService()..documentsDirOverride = targetDir;

      await restoreService.restoreBackup(bytes);

      expect(await File('${targetDir.path}/omnis_library.json.tmp').exists(),
          isFalse);
    });

    test('restore only writes the files the backup actually contained — '
        'a pre-existing store file not part of the backup is left '
        'untouched', () async {
      await writeStoreFile(sourceDir, 'omnis_library.json', []);
      // No playlists in the source — a backup of just the library.
      final bytes = await service.createBackup();

      // The target already has its own playlists, unrelated to this backup.
      await writeStoreFile(targetDir, 'omnis_playlists.json', [
        {'id': 'existing', 'name': 'Keep Me'}
      ]);
      final restoreService = BackupService()..documentsDirOverride = targetDir;

      final result = await restoreService.restoreBackup(bytes);

      expect(result.success, isTrue);
      expect(result.restoredFiles, ['omnis_library.json']);
      final untouched =
          await File('${targetDir.path}/omnis_playlists.json').readAsString();
      expect(untouched, contains('Keep Me'));
    });
  });

  group('restoreBackup — validation before overwriting anything', () {
    test('rejects bytes that are not a zip archive at all, writing '
        'nothing', () async {
      final restoreService = BackupService()..documentsDirOverride = targetDir;

      final result =
          await restoreService.restoreBackup(utf8.encode('not a zip file'));

      expect(result.success, isFalse);
      expect(result.error, isNotNull);
      expect(await targetDir.list().toList(), isEmpty);
    });

    test('rejects a zip with no manifest.json', () async {
      // A zip built without ever calling createBackup — no manifest.
      final bytes = _buildRawZip({'omnis_library.json': '[]'});
      final restoreService = BackupService()..documentsDirOverride = targetDir;

      final result = await restoreService.restoreBackup(bytes);

      expect(result.success, isFalse);
      expect(result.error, contains('manifest'));
      expect(await targetDir.list().toList(), isEmpty);
    });

    test('rejects a manifest with an unrecognized version, writing '
        'nothing even though the file content itself is fine', () async {
      final bytes = _buildRawZip({
        'manifest.json': jsonEncode({
          'version': 999,
          'files': ['omnis_library.json'],
        }),
        'omnis_library.json': '[]',
      });
      final restoreService = BackupService()..documentsDirOverride = targetDir;

      final result = await restoreService.restoreBackup(bytes);

      expect(result.success, isFalse);
      expect(result.error, contains('incompatible'));
      expect(await targetDir.list().toList(), isEmpty);
    });

    test('rejects a manifest declaring a file that is not actually in '
        'the zip', () async {
      final bytes = _buildRawZip({
        'manifest.json': jsonEncode({
          'version': BackupService.manifestVersion,
          'files': ['omnis_library.json'], // declared but never added below
        }),
      });
      final restoreService = BackupService()..documentsDirOverride = targetDir;

      final result = await restoreService.restoreBackup(bytes);

      expect(result.success, isFalse);
      expect(result.error, contains('missing'));
      expect(await targetDir.list().toList(), isEmpty);
    });

    test('rejects a manifest declaring an unknown/unrecognized file '
        'name', () async {
      final bytes = _buildRawZip({
        'manifest.json': jsonEncode({
          'version': BackupService.manifestVersion,
          'files': ['../../etc/passwd'],
        }),
        '../../etc/passwd': 'nope',
      });
      final restoreService = BackupService()..documentsDirOverride = targetDir;

      final result = await restoreService.restoreBackup(bytes);

      expect(result.success, isFalse);
      expect(result.error, contains('unrecognized'));
      expect(await targetDir.list().toList(), isEmpty);
    });

    test('rejects the whole backup if even one declared file is not '
        'valid JSON — including files declared *before* the bad one, '
        'proving validation happens before any write', () async {
      final bytes = _buildRawZip({
        'manifest.json': jsonEncode({
          'version': BackupService.manifestVersion,
          'files': ['omnis_library.json', 'omnis_playlists.json'],
        }),
        'omnis_library.json': '[]', // valid
        'omnis_playlists.json': 'not valid json {{{', // invalid
      });
      final restoreService = BackupService()..documentsDirOverride = targetDir;

      final result = await restoreService.restoreBackup(bytes);

      expect(result.success, isFalse);
      expect(result.error, contains('omnis_playlists.json'));
      // The valid library file must NOT have been written either — the
      // whole backup is one all-or-nothing unit.
      expect(await targetDir.list().toList(), isEmpty,
          reason: 'a bad file anywhere in the backup must block every '
              'write, not just skip the bad one');
    });

    test('a corrupt backup does not disturb a store file that already '
        'exists at the target', () async {
      await writeStoreFile(targetDir, 'omnis_library.json', [
        {'id': 'keep', 'title': 'Do Not Lose Me'}
      ]);
      final bytes = _buildRawZip({
        'manifest.json': jsonEncode({
          'version': BackupService.manifestVersion,
          'files': ['omnis_library.json'],
        }),
        'omnis_library.json': 'not valid json {{{',
      });
      final restoreService = BackupService()..documentsDirOverride = targetDir;

      final result = await restoreService.restoreBackup(bytes);

      expect(result.success, isFalse);
      final untouched =
          await File('${targetDir.path}/omnis_library.json').readAsString();
      expect(untouched, contains('Do Not Lose Me'));
    });
  });

  group('maybeRunAutomaticBackup (item 4/50)', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await AppSettings.instance.initialize();
    });

    test('does nothing when auto-backup is disabled (the default)',
        () async {
      await service.maybeRunAutomaticBackup();

      final backupsDir = Directory('${sourceDir.path}/backups');
      expect(await backupsDir.exists(), isFalse);
      expect(AppSettings.instance.lastAutoBackupAt, isNull);
    });

    test('writes a zip and stamps lastAutoBackupAt when enabled and due '
        '(never run before)', () async {
      AppSettings.instance.autoBackupEnabled = true;
      final now = DateTime(2026, 8, 15, 12);

      await service.maybeRunAutomaticBackup(now: now);

      final backupsDir = Directory('${sourceDir.path}/backups');
      expect(await backupsDir.exists(), isTrue);
      final files = await backupsDir.list().toList();
      expect(files, hasLength(1));
      expect(files.single.path, endsWith('.zip'));
      expect(AppSettings.instance.lastAutoBackupAt, now);
    });

    test('does nothing when enabled but not yet due', () async {
      AppSettings.instance.autoBackupEnabled = true;
      AppSettings.instance.autoBackupIntervalDays = 7;
      final now = DateTime(2026, 8, 15);
      AppSettings.instance.lastAutoBackupAt =
          now.subtract(const Duration(days: 1));

      await service.maybeRunAutomaticBackup(now: now);

      final backupsDir = Directory('${sourceDir.path}/backups');
      expect(await backupsDir.exists(), isFalse);
    });

    test('runs again once the interval has elapsed', () async {
      AppSettings.instance.autoBackupEnabled = true;
      AppSettings.instance.autoBackupIntervalDays = 7;
      final now = DateTime(2026, 8, 15);
      AppSettings.instance.lastAutoBackupAt =
          now.subtract(const Duration(days: 8));

      await service.maybeRunAutomaticBackup(now: now);

      final backupsDir = Directory('${sourceDir.path}/backups');
      expect(await backupsDir.exists(), isTrue);
      expect(AppSettings.instance.lastAutoBackupAt, now);
    });

    test('prunes older automatic backups beyond the keep count', () async {
      AppSettings.instance.autoBackupEnabled = true;
      final backupsDir = Directory('${sourceDir.path}/backups');
      await backupsDir.create(recursive: true);
      // Pre-seed more files than the keep count, each with a distinct
      // mtime so pruning has a real newest-N ordering to respect.
      for (var i = 0; i < BackupService.autoBackupKeepCount + 3; i++) {
        final f = File('${backupsDir.path}/omnis-backup-seed-$i.zip');
        await f.writeAsBytes([0]);
        await f.setLastModified(
            DateTime(2026, 1, 1).add(Duration(days: i)));
      }

      await service.maybeRunAutomaticBackup(now: DateTime(2026, 8, 15));

      final remaining = await backupsDir.list().toList();
      // The freshly-written backup counts toward the same keep-count
      // pool as every pre-seeded one (it's the newest by mtime, so it's
      // never itself pruned) — total remaining is exactly keepCount, not
      // keepCount + 1.
      expect(remaining.length, BackupService.autoBackupKeepCount);
    });

    test('a failure (e.g. an unwritable path) never throws — startup '
        'must never be blocked by this', () async {
      AppSettings.instance.autoBackupEnabled = true;
      // Point at a path that can't be created as a directory (a file
      // already sits where the "backups" subdirectory would go).
      final blocker = File('${sourceDir.path}/backups');
      await blocker.writeAsBytes([0]);

      await expectLater(
          service.maybeRunAutomaticBackup(now: DateTime(2026, 8, 15)),
          completes);
      expect(AppSettings.instance.lastAutoBackupAt, isNull,
          reason: 'the failed attempt must not falsely claim success');
    });
  });
}
