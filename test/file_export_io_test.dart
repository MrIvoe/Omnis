import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/file_export_io.dart';
import 'package:omnis/core/platform_capabilities.dart';

void main() {
  group('FileExportIo', () {
    test('requiresManualWrite is the logical negation of isTouchPrimary', () {
      expect(
        FileExportIo.requiresManualWrite,
        equals(!PlatformCapabilities.isTouchPrimary),
        reason:
            'Desktop platforms (where !isTouchPrimary) require manual write; '
            'touch-primary platforms (Android/iOS) do not',
      );
    });

    test('requiresManualWrite is a valid boolean', () {
      expect(
        FileExportIo.requiresManualWrite,
        isA<bool>(),
      );
    });
  });
}
