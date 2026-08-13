import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/semver.dart';

void main() {
  test('equal versions compare as zero', () {
    expect(compareVersions('1.2.3', '1.2.3'), 0);
  });

  test('a greater patch version compares positive', () {
    expect(compareVersions('1.2.4', '1.2.3'), greaterThan(0));
    expect(compareVersions('1.2.3', '1.2.4'), lessThan(0));
  });

  test('a greater minor version outweighs a smaller patch difference', () {
    expect(compareVersions('1.3.0', '1.2.9'), greaterThan(0));
  });

  test('a greater major version outweighs everything else', () {
    expect(compareVersions('2.0.0', '1.99.99'), greaterThan(0));
  });

  test('compares numerically, not lexically — 1.10.0 beats 1.9.0', () {
    // A plain string compare would get this backwards ("1.10.0" < "1.9.0"
    // lexically, since '1' < '9').
    expect(compareVersions('1.10.0', '1.9.0'), greaterThan(0));
  });

  test('a missing trailing segment is treated as zero', () {
    expect(compareVersions('1.2', '1.2.0'), 0);
    expect(compareVersions('1.2.1', '1.2'), greaterThan(0));
  });

  test('a non-numeric segment degrades to zero rather than throwing', () {
    expect(() => compareVersions('1.0.0-beta', '1.0.0'), returnsNormally);
    expect(compareVersions('1.0.0-beta', '1.0.0'), 0);
  });

  test('a completely malformed version string never throws', () {
    expect(() => compareVersions('not-a-version', '1.0.0'), returnsNormally);
  });
}
