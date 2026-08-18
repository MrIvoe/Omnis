import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/rename_reconciliation.dart';

BaseTrack _local(String id, String path, {String title = 'Title'}) {
  return BaseTrack(
    id: id,
    title: title,
    artists: const ['Artist'],
    album: 'Album',
    duration: 200,
    type: TrackType.local,
    localPath: path,
  );
}

/// A deterministic fake fingerprint: two paths "fingerprint the same" iff
/// they're passed the same [samePaths] pair in the test — real content
/// hashing is tested separately in `computeFileFingerprint` itself (a
/// pure function of real file bytes, not exercised here since this test
/// is about the matching/pruning logic, not hashing).
Future<String?> Function(String path) _fakeFingerprint(
  Map<String, String> pathToFingerprint,
) {
  return (path) async => pathToFingerprint[path];
}

void main() {
  group('reconcileRenamedTracks', () {
    test('a matching fingerprint is recognized as a rename: keeps the old '
        'id and dateAdded, takes every other field from the new scan',
        () async {
      final oldDate = DateTime(2020, 1, 1);
      final oldTrack =
          _local('local:/music/old.mp3', '/music/old.mp3', title: 'Old title')
              .copyWith(dateAdded: oldDate);
      final newCandidate =
          _local('local:/music/new.mp3', '/music/new.mp3', title: 'New title');

      final result = await reconcileRenamedTracks(
        missingTracks: [oldTrack],
        candidateNewTracks: [newCandidate],
        fingerprints: {oldTrack.id: 'fp-A'},
        computeFingerprint: _fakeFingerprint({'/music/new.mp3': 'fp-A'}),
      );

      expect(result.trulyNew, isEmpty);
      expect(result.renamed, hasLength(1));
      final renamed = result.renamed.single;
      expect(renamed.id, oldTrack.id);
      expect(renamed.dateAdded, oldDate);
      expect(renamed.title, 'New title');
      expect(renamed.localPath, '/music/new.mp3');
    });

    test('no fingerprint match: treated as a real deletion + a real '
        'addition, and the deleted id\'s fingerprint entry is pruned',
        () async {
      final oldTrack = _local('local:/music/old.mp3', '/music/old.mp3');
      final newCandidate = _local('local:/music/new.mp3', '/music/new.mp3');

      final result = await reconcileRenamedTracks(
        missingTracks: [oldTrack],
        candidateNewTracks: [newCandidate],
        fingerprints: {oldTrack.id: 'fp-A'},
        computeFingerprint: _fakeFingerprint({'/music/new.mp3': 'fp-B'}),
      );

      expect(result.renamed, isEmpty);
      expect(result.trulyNew, [newCandidate]);
      expect(result.updatedFingerprints.containsKey(oldTrack.id), isFalse);
      expect(result.updatedFingerprints[newCandidate.id], 'fp-B');
    });

    test('a missing track with no recorded fingerprint can never be '
        'recognized as a rename source — treated as a real deletion',
        () async {
      final oldTrack = _local('local:/music/old.mp3', '/music/old.mp3');
      final newCandidate = _local('local:/music/new.mp3', '/music/new.mp3');

      final result = await reconcileRenamedTracks(
        missingTracks: [oldTrack],
        candidateNewTracks: [newCandidate],
        fingerprints: const {}, // oldTrack was never fingerprinted
        computeFingerprint: _fakeFingerprint({'/music/new.mp3': 'fp-anything'}),
      );

      expect(result.renamed, isEmpty);
      expect(result.trulyNew, [newCandidate]);
    });

    test('each missing track matches at most one candidate — a second '
        'candidate with the same fingerprint is treated as truly new',
        () async {
      final oldTrack = _local('local:/music/old.mp3', '/music/old.mp3');
      final candidateA = _local('local:/music/a.mp3', '/music/a.mp3');
      final candidateB = _local('local:/music/b.mp3', '/music/b.mp3');

      final result = await reconcileRenamedTracks(
        missingTracks: [oldTrack],
        candidateNewTracks: [candidateA, candidateB],
        fingerprints: {oldTrack.id: 'fp-A'},
        computeFingerprint: _fakeFingerprint({
          '/music/a.mp3': 'fp-A',
          '/music/b.mp3': 'fp-A',
        }),
      );

      expect(result.renamed, hasLength(1));
      expect(result.renamed.single.localPath, '/music/a.mp3');
      expect(result.trulyNew, hasLength(1));
      expect(result.trulyNew.single.localPath, '/music/b.mp3');
    });

    test('genuinely new tracks get their fingerprint recorded even when '
        'there are no missing tracks to match against at all', () async {
      final newCandidate = _local('local:/music/new.mp3', '/music/new.mp3');

      final result = await reconcileRenamedTracks(
        missingTracks: const [],
        candidateNewTracks: [newCandidate],
        fingerprints: const {},
        computeFingerprint: _fakeFingerprint({'/music/new.mp3': 'fp-C'}),
      );

      expect(result.trulyNew, [newCandidate]);
      expect(result.updatedFingerprints[newCandidate.id], 'fp-C');
    });

    test('existing unrelated fingerprint entries are preserved untouched',
        () async {
      final result = await reconcileRenamedTracks(
        missingTracks: const [],
        candidateNewTracks: const [],
        fingerprints: {'unrelated_id': 'fp-untouched'},
        computeFingerprint: _fakeFingerprint(const {}),
      );

      expect(result.updatedFingerprints, {'unrelated_id': 'fp-untouched'});
    });
  });
}
