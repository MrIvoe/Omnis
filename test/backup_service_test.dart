import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/backup_service.dart';

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
}
