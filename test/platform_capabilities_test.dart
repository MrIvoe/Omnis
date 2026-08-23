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
}
