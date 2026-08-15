import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/schema_versioning.dart';

void main() {
  group('wrapVersioned', () {
    test('wraps a payload with the given version', () {
      final wrapped = wrapVersioned(['a', 'b'], 3);

      expect(wrapped, {
        'schemaVersion': 3,
        'data': ['a', 'b'],
      });
    });
  });

  group('unwrapVersioned', () {
    test('reads version and data from a real versioned envelope', () {
      final result = unwrapVersioned({
        'schemaVersion': 2,
        'data': {'x': 1},
      });

      expect(result.version, 2);
      expect(result.data, {'x': 1});
    });

    test('treats a bare list (the pre-versioning shape every store '
        'wrote before this scaffold existed) as version 0, with the '
        'whole decoded value as the payload', () {
      final result = unwrapVersioned(['a', 'b', 'c']);

      expect(result.version, 0);
      expect(result.data, ['a', 'b', 'c']);
    });

    test('treats a bare map with no "schemaVersion" key as version 0 '
        'too — the exact shape PlayHistoryStore wrote before this '
        'scaffold existed', () {
      final result = unwrapVersioned({'trackId1': 'stats1'});

      expect(result.version, 0);
      expect(result.data, {'trackId1': 'stats1'});
    });

    test('a non-Map, non-versioned value (already-corrupt content) '
        'still degrades to version 0 rather than throwing', () {
      final result = unwrapVersioned('not even an object');

      expect(result.version, 0);
      expect(result.data, 'not even an object');
    });
  });

  group('runMigrations', () {
    test('applies no transformation when fromVersion already equals '
        'toVersion', () {
      final result = runMigrations(['x'], 1, 1, {0: (d) => ['migrated']});

      expect(result, ['x']);
    });

    test('runs every migration step in order, each one building on the '
        'previous step\'s result', () {
      final migrations = <int, SchemaMigration>{
        0: (data) => (data as List)..add('via-0-to-1'),
        1: (data) => (data as List)..add('via-1-to-2'),
      };

      final result = runMigrations(['start'], 0, 2, migrations);

      expect(result, ['start', 'via-0-to-1', 'via-1-to-2']);
    });

    test('a version with no registered migration is a no-op for that '
        'step, not an error — the common case, since most versions '
        "won't ever need a real transformation", () {
      final migrations = <int, SchemaMigration>{
        1: (data) => (data as List)..add('via-1-to-2'),
      };

      final result = runMigrations(['start'], 0, 2, migrations);

      expect(result, ['start', 'via-1-to-2']);
    });

    test('starting mid-way (fromVersion > 0) only runs the remaining '
        'steps, not ones already applied', () {
      final migrations = <int, SchemaMigration>{
        0: (data) => (data as List)..add('should-not-run'),
        1: (data) => (data as List)..add('via-1-to-2'),
      };

      final result = runMigrations(['start'], 1, 2, migrations);

      expect(result, ['start', 'via-1-to-2']);
    });
  });

  group('wrap/unwrap round-trip', () {
    test('a payload wrapped then unwrapped comes back unchanged', () {
      const payload = {
        'nested': [1, 2, 3],
        'flag': true,
      };

      final wrapped = wrapVersioned(payload, 1);
      final unwrapped = unwrapVersioned(wrapped);

      expect(unwrapped.version, 1);
      expect(unwrapped.data, payload);
    });
  });
}
