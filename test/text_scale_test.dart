import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/text_scale.dart';

void main() {
  group('clampTextScale', () {
    test('a value already within range is returned unchanged', () {
      expect(clampTextScale(1.0), 1.0);
      expect(clampTextScale(1.2), 1.2);
    });

    test('a value below the minimum clamps to 0.85', () {
      expect(clampTextScale(0.5), 0.85);
      expect(clampTextScale(0.0), 0.85);
      expect(clampTextScale(-1.0), 0.85);
    });

    test('a value above the maximum clamps to 1.5', () {
      expect(clampTextScale(2.0), 1.5);
      expect(clampTextScale(100.0), 1.5);
    });

    test('the exact boundary values are returned unchanged', () {
      expect(clampTextScale(0.85), 0.85);
      expect(clampTextScale(1.5), 1.5);
    });
  });
}
