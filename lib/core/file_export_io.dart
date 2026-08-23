import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

/// Whether the current platform's `file_picker.saveFile` call returns a
/// path the caller must write the bytes to itself (desktop), as opposed
/// to already having written them (Android/iOS, where `saveFile` takes
/// the bytes directly and the OS handles the write). A `file_picker`
/// plugin-contract fact — not a UI-adaptivity decision — so it lives here
/// rather than on `PlatformCapabilities`.
class FileExportIo {
  const FileExportIo._();

  static bool get requiresManualWrite =>
      !kIsWeb && !Platform.isAndroid && !Platform.isIOS;
}
