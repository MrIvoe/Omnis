import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/play_completion.dart';

void main() {
  group('completionRatio', () {
    test('a zero duration returns null — no real denominator', () {
      expect(completionRatio(30, 0), isNull);
    });

    test('a negative duration returns null', () {
      expect(completionRatio(30, -5), isNull);
    });

    test('a normal position/duration pair computes the exact ratio', () {
      expect(completionRatio(90, 180), 0.5);
    });

    test('zero position returns 0.0, not null', () {
      expect(completionRatio(0, 180), 0.0);
    });

    test('a position exactly equal to duration returns 1.0', () {
      expect(completionRatio(180, 180), 1.0);
    });

    test('a position past duration (common near end-of-track) clamps to '
        '1.0 rather than exceeding it', () {
      expect(completionRatio(200, 180), 1.0);
    });

    test('a negative position clamps to 0.0', () {
      expect(completionRatio(-5, 180), 0.0);
    });
  });

  group('isSkip', () {
    test('a ratio below the default 0.5 threshold is a skip', () {
      expect(isSkip(0.3), isTrue);
    });

    test('a ratio at or above the default threshold is not a skip', () {
      expect(isSkip(0.5), isFalse);
      expect(isSkip(0.9), isFalse);
    });

    test('a custom threshold is honored', () {
      expect(isSkip(0.2, threshold: 0.1), isFalse);
      expect(isSkip(0.05, threshold: 0.1), isTrue);
    });

    test('0.0 is always a skip, 1.0 is never a skip', () {
      expect(isSkip(0.0), isTrue);
      expect(isSkip(1.0), isFalse);
    });
  });
}
