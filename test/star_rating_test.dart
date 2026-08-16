import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/star_rating.dart';

void main() {
  group('snapToHalfStep', () {
    test('a value near 0 snaps down to 0.0', () {
      expect(snapToHalfStep(0.24), 0.0);
    });

    test('a value just past the boundary snaps up to 0.5', () {
      expect(snapToHalfStep(0.26), 0.5);
    });

    test('an exact half-step value round-trips unchanged', () {
      expect(snapToHalfStep(2.5), 2.5);
      expect(snapToHalfStep(3.0), 3.0);
    });

    test('a negative raw value clamps to 0.0', () {
      expect(snapToHalfStep(-1.5), 0.0);
    });

    test('a raw value above 5 clamps to 5.0', () {
      expect(snapToHalfStep(7.2), 5.0);
    });

    test('every quarter-step in a full star rounds to its nearer half '
        'step', () {
      expect(snapToHalfStep(1.1), 1.0);
      expect(snapToHalfStep(1.4), 1.5);
      expect(snapToHalfStep(1.6), 1.5);
      expect(snapToHalfStep(1.9), 2.0);
    });
  });

  group('isValidHalfStarRating', () {
    test('0 (unrated) is always valid', () {
      expect(isValidHalfStarRating(0), isTrue);
    });

    test('every half-step from 0.5 to 5.0 is valid', () {
      for (var i = 1; i <= 10; i++) {
        expect(isValidHalfStarRating(i / 2), isTrue, reason: '${i / 2}');
      }
    });

    test('a non-half-step value is invalid', () {
      expect(isValidHalfStarRating(4.3), isFalse);
      expect(isValidHalfStarRating(0.3), isFalse);
    });

    test('a value below 0.5 (but not exactly 0) is invalid', () {
      expect(isValidHalfStarRating(0.25), isFalse);
    });

    test('a value above 5 is invalid', () {
      expect(isValidHalfStarRating(5.5), isFalse);
    });

    test('a negative value is invalid', () {
      expect(isValidHalfStarRating(-1), isFalse);
    });
  });

  group('iconStateFor', () {
    test('a whole rating fills every star up to and including it', () {
      expect(iconStateFor(1, 3.0), StarIconState.full);
      expect(iconStateFor(3, 3.0), StarIconState.full);
      expect(iconStateFor(4, 3.0), StarIconState.empty);
      expect(iconStateFor(5, 3.0), StarIconState.empty);
    });

    test('a half rating (e.g. 3.5) shows the next star as half, the rest '
        'past it as empty', () {
      expect(iconStateFor(3, 3.5), StarIconState.full);
      expect(iconStateFor(4, 3.5), StarIconState.half);
      expect(iconStateFor(5, 3.5), StarIconState.empty);
    });

    test('a rating of 0 shows every star empty', () {
      for (var i = 1; i <= 5; i++) {
        expect(iconStateFor(i, 0), StarIconState.empty);
      }
    });

    test('a rating of 5.0 shows every star full', () {
      for (var i = 1; i <= 5; i++) {
        expect(iconStateFor(i, 5.0), StarIconState.full);
      }
    });

    test('a rating of 0.5 shows only the first star as half', () {
      expect(iconStateFor(1, 0.5), StarIconState.half);
      expect(iconStateFor(2, 0.5), StarIconState.empty);
    });
  });
}
