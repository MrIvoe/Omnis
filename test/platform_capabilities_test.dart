import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/platform_capabilities.dart';

void main() {
  group('PlatformCapabilities', () {
    test('isTouchPrimary and isDesktopPrimary are mutually exclusive', () {
      expect(
        PlatformCapabilities.isTouchPrimary &&
            PlatformCapabilities.isDesktopPrimary,
        false,
        reason: 'A platform cannot be both touch-primary and desktop-primary',
      );
    });

    test('isRotatable equals isTouchPrimary', () {
      expect(
        PlatformCapabilities.isRotatable,
        equals(PlatformCapabilities.isTouchPrimary),
        reason: 'isRotatable should be true only on touch-primary platforms',
      );
    });

    test('supportsRightClick equals isDesktopPrimary', () {
      expect(
        PlatformCapabilities.supportsRightClick,
        equals(PlatformCapabilities.isDesktopPrimary),
        reason: 'Right-click support should match desktop-primary platforms',
      );
    });

    test('supportsOutputDeviceSelection is a valid boolean', () {
      expect(
        PlatformCapabilities.supportsOutputDeviceSelection,
        isA<bool>(),
      );
    });
  });

  group('test overrides', () {
    // These are the seam Task 5's own test suites (global keyboard
    // shortcuts, gesture-only layouts, gesture settings) use to exercise
    // both the touch-primary and desktop-primary branch of a call site on
    // a single CI host, which otherwise only ever runs as one real
    // `Platform.isX`. Reset unconditionally after every test in this
    // group, not just the ones that set an override, so a failure
    // part-way through a test here can never leak into a later file.
    tearDown(PlatformCapabilities.resetOverridesForTesting);

    test('debugIsTouchPrimaryOverride replaces isTouchPrimary when set', () {
      PlatformCapabilities.debugIsTouchPrimaryOverride = true;
      expect(PlatformCapabilities.isTouchPrimary, isTrue);
      expect(PlatformCapabilities.isRotatable, isTrue,
          reason: 'isRotatable is defined in terms of isTouchPrimary');

      PlatformCapabilities.debugIsTouchPrimaryOverride = false;
      expect(PlatformCapabilities.isTouchPrimary, isFalse);
    });

    test('debugIsDesktopPrimaryOverride replaces isDesktopPrimary when set',
        () {
      PlatformCapabilities.debugIsDesktopPrimaryOverride = true;
      expect(PlatformCapabilities.isDesktopPrimary, isTrue);
      expect(PlatformCapabilities.supportsRightClick, isTrue,
          reason: 'supportsRightClick is defined in terms of '
              'isDesktopPrimary');

      PlatformCapabilities.debugIsDesktopPrimaryOverride = false;
      expect(PlatformCapabilities.isDesktopPrimary, isFalse);
    });

    test('resetOverridesForTesting restores the real platform-derived value',
        () {
      final realIsTouchPrimary = PlatformCapabilities.isTouchPrimary;
      final realIsDesktopPrimary = PlatformCapabilities.isDesktopPrimary;

      PlatformCapabilities.debugIsTouchPrimaryOverride = !realIsTouchPrimary;
      PlatformCapabilities.debugIsDesktopPrimaryOverride =
          !realIsDesktopPrimary;
      PlatformCapabilities.resetOverridesForTesting();

      expect(PlatformCapabilities.isTouchPrimary, realIsTouchPrimary);
      expect(PlatformCapabilities.isDesktopPrimary, realIsDesktopPrimary);
    });
  });
}
