import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/ui/theme/declarative/theme_manifest.dart';
import 'package:omnis/ui/theme/omnis_icon_style.dart';

const _minimalHeader = '''
id: test_theme
name: Test Theme
colors:
  primary: "#FF0000"
''';

void main() {
  group('ThemeManifest.parse — icons.style (closed vocabulary)', () {
    test('defaults to OmnisIconStyle.defaultStyleKey when the icons block '
        'is absent entirely', () {
      final manifest = ThemeManifest.parse(_minimalHeader, sourceUrl: 'test');

      expect(manifest, isNotNull);
      expect(manifest!.iconStyle, OmnisIconStyle.defaultStyleKey);
    });

    test('defaults to OmnisIconStyle.defaultStyleKey when icons: is '
        'present but style: is missing', () {
      const text = '$_minimalHeader'
          'icons:\n'
          '  somethingElse: true\n';
      final manifest = ThemeManifest.parse(text, sourceUrl: 'test');

      expect(manifest, isNotNull);
      expect(manifest!.iconStyle, OmnisIconStyle.defaultStyleKey);
    });

    for (final key in OmnisIconStyle.allowedStyles.keys) {
      test('accepts the allowed value "$key"', () {
        final text = '$_minimalHeader'
            'icons:\n'
            '  style: $key\n';
        final manifest = ThemeManifest.parse(text, sourceUrl: 'test');

        expect(manifest, isNotNull);
        expect(manifest!.iconStyle, key);
      });
    }

    test('falls back to the default for an unrecognized value — never '
        'rejects the whole file the way a required field would', () {
      const text = '$_minimalHeader'
          'icons:\n'
          '  style: neon_holographic_pack\n';
      final manifest = ThemeManifest.parse(text, sourceUrl: 'test');

      expect(manifest, isNotNull,
          reason: 'an unrecognized icons.style must not fail the whole '
              'parse, same as an unrecognized typography.fontFamily');
      expect(manifest!.iconStyle, OmnisIconStyle.defaultStyleKey);
    });

    test('an icons.style of a wrong type (not a string) falls back to '
        'the default rather than throwing', () {
      const text = '$_minimalHeader'
          'icons:\n'
          '  style: 42\n';
      final manifest = ThemeManifest.parse(text, sourceUrl: 'test');

      expect(manifest, isNotNull);
      expect(manifest!.iconStyle, OmnisIconStyle.defaultStyleKey);
    });
  });

  group('ThemedIcon.resolve', () {
    test('returns the field matching each OmnisIconStyleKind', () {
      const icon = ThemedIcon(
        filled: Icons.home,
        outlined: Icons.home_outlined,
        rounded: Icons.home_rounded,
        sharp: Icons.home_sharp,
      );

      expect(icon.resolve(OmnisIconStyleKind.filled), Icons.home);
      expect(icon.resolve(OmnisIconStyleKind.outlined), Icons.home_outlined);
      expect(icon.resolve(OmnisIconStyleKind.rounded), Icons.home_rounded);
      expect(icon.resolve(OmnisIconStyleKind.sharp), Icons.home_sharp);
    });

    test('defaults to OmnisIconStyle.current when no style is passed', () {
      const icon = ThemedIcon(
        filled: Icons.home,
        outlined: Icons.home_outlined,
        rounded: Icons.home_rounded,
        sharp: Icons.home_sharp,
      );
      final previous = OmnisIconStyle.current;
      addTearDown(() => OmnisIconStyle.current = previous);

      OmnisIconStyle.current = OmnisIconStyleKind.sharp;
      expect(icon.resolve(), Icons.home_sharp);
    });
  });

  group('OmnisIconStyle.allowedStyles', () {
    test('has exactly one key per OmnisIconStyleKind value, round-tripping '
        'cleanly', () {
      expect(OmnisIconStyle.allowedStyles.length,
          OmnisIconStyleKind.values.length);
      expect(OmnisIconStyle.allowedStyles.values.toSet(),
          OmnisIconStyleKind.values.toSet());
    });

    test('defaultStyleKey is itself a key of allowedStyles', () {
      expect(OmnisIconStyle.allowedStyles.containsKey(
          OmnisIconStyle.defaultStyleKey), isTrue);
    });
  });
}
