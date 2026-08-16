import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/backup_scheduler.dart';

class _FakeBackupFile {
  final String name;
  final DateTime createdAt;
  const _FakeBackupFile(this.name, this.createdAt);
}

void main() {
  final now = DateTime(2026, 8, 15);

  group('isDue', () {
    test('null lastBackupAt is always due, regardless of interval', () {
      expect(BackupScheduler.isDue(null, const Duration(days: 365), now),
          isTrue);
    });

    test('a backup older than the interval is due', () {
      final last = now.subtract(const Duration(days: 8));
      expect(BackupScheduler.isDue(last, const Duration(days: 7), now),
          isTrue);
    });

    test('a backup within the interval is not due', () {
      final last = now.subtract(const Duration(days: 3));
      expect(BackupScheduler.isDue(last, const Duration(days: 7), now),
          isFalse);
    });

    test('exactly at the interval boundary is due — >=, not >', () {
      final last = now.subtract(const Duration(days: 7));
      expect(BackupScheduler.isDue(last, const Duration(days: 7), now),
          isTrue);
    });

    test('a backup timestamp in the future (clock skew) is not due', () {
      final last = now.add(const Duration(days: 1));
      expect(BackupScheduler.isDue(last, const Duration(days: 7), now),
          isFalse);
    });
  });

  group('filesToPrune', () {
    test('fewer files than keepCount prunes nothing', () {
      final files = [
        _FakeBackupFile('a', now),
        _FakeBackupFile('b', now.subtract(const Duration(days: 1))),
      ];

      final result =
          BackupScheduler.filesToPrune(files, 5, (f) => f.createdAt);

      expect(result, isEmpty);
    });

    test('exactly keepCount files prunes nothing', () {
      final files = [
        _FakeBackupFile('a', now),
        _FakeBackupFile('b', now.subtract(const Duration(days: 1))),
      ];

      final result =
          BackupScheduler.filesToPrune(files, 2, (f) => f.createdAt);

      expect(result, isEmpty);
    });

    test('more files than keepCount prunes the oldest, keeping the '
        'newest N', () {
      final files = [
        _FakeBackupFile('oldest', now.subtract(const Duration(days: 10))),
        _FakeBackupFile('newest', now),
        _FakeBackupFile('middle', now.subtract(const Duration(days: 5))),
      ];

      final result =
          BackupScheduler.filesToPrune(files, 2, (f) => f.createdAt);

      expect(result.map((f) => f.name), ['oldest']);
    });

    test('works correctly even when the input is not pre-sorted', () {
      final files = [
        _FakeBackupFile('b', now.subtract(const Duration(days: 2))),
        _FakeBackupFile('d', now.subtract(const Duration(days: 4))),
        _FakeBackupFile('a', now.subtract(const Duration(days: 1))),
        _FakeBackupFile('c', now.subtract(const Duration(days: 3))),
      ];

      final result =
          BackupScheduler.filesToPrune(files, 1, (f) => f.createdAt);

      expect(result.map((f) => f.name), ['b', 'c', 'd']);
    });

    test('keepCount 0 prunes everything', () {
      final files = [_FakeBackupFile('a', now)];

      final result =
          BackupScheduler.filesToPrune(files, 0, (f) => f.createdAt);

      expect(result.map((f) => f.name), ['a']);
    });

    test('a negative keepCount is treated as 0, not a crash', () {
      final files = [_FakeBackupFile('a', now)];

      final result =
          BackupScheduler.filesToPrune(files, -3, (f) => f.createdAt);

      expect(result.map((f) => f.name), ['a']);
    });

    test('an empty file list prunes nothing', () {
      final result = BackupScheduler.filesToPrune<_FakeBackupFile>(
          const [], 5, (f) => f.createdAt);

      expect(result, isEmpty);
    });
  });
}
