import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/base_track.dart';

BaseTrack _track({String? composer}) => BaseTrack(
      id: '1',
      title: 'Title',
      artists: const ['Artist'],
      album: 'Album',
      duration: 200,
      type: TrackType.local,
      composer: composer,
    );

void main() {
  group('BaseTrack.composer', () {
    test('defaults to null when not provided', () {
      expect(_track().composer, isNull);
    });

    test('toJson/fromJson round-trips a real value', () {
      final track = _track(composer: 'John Williams');
      final decoded = BaseTrack.fromJson(track.toJson());
      expect(decoded.composer, 'John Williams');
    });

    test('a JSON blob written before this field existed decodes as null, '
        'not a throw — the standard additive-field backward-compat '
        'contract every other nullable BaseTrack field already follows',
        () {
      final legacyJson = _track().toJson()..remove('composer');
      final decoded = BaseTrack.fromJson(legacyJson);
      expect(decoded.composer, isNull);
    });

    test('copyWith updates composer without touching other fields', () {
      final track = _track(composer: 'Original');
      final updated = track.copyWith(composer: 'Updated');
      expect(updated.composer, 'Updated');
      expect(updated.title, track.title);
    });

    test('two otherwise-identical tracks with different composers are '
        'not equal, and have different hash codes', () {
      final a = _track(composer: 'Composer A');
      final b = _track(composer: 'Composer B');
      expect(a == b, isFalse);
      expect(a.hashCode == b.hashCode, isFalse);
    });

    test('two structurally-identical tracks (including composer) are '
        'equal', () {
      final a = _track(composer: 'Same Composer');
      final b = _track(composer: 'Same Composer');
      expect(a == b, isTrue);
      expect(a.hashCode, b.hashCode);
    });
  });
}
