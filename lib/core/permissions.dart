import 'package:permission_handler/permission_handler.dart';

/// Central place for requesting OS permissions Omnis or its plugins need,
/// beyond what `on_audio_query` already handles internally for library
/// scanning (see `MediaScanner._scanAndroid`'s `checkAndRequest()` call —
/// storage/media read is already covered and doesn't go through here).
///
/// Requested contextually, not all upfront: [ensureCorePermissions]
/// covers what the Core itself needs to function normally (right now:
/// posting the media notification) and is called once at startup.
/// Bluetooth/location are requested only when a plugin that actually
/// uses them runs, via [requestBluetooth]/[requestLocation] — asking for
/// a permission a fresh install has no use for yet is exactly the kind
/// of "why does this app want that" moment that makes people distrust an
/// app, and both Android and iOS guidance says to ask in context, not
/// upfront.
///
/// Every method here is best-effort and never throws out to the caller —
/// a denied or platform-unsupported permission degrades the corresponding
/// feature, it must never block the app or crash it.
class OmnisPermissions {
  OmnisPermissions._();

  /// Requests whatever the Core needs to function normally. Call once,
  /// early in startup.
  static Future<void> ensureCorePermissions() async {
    // Android 13+ (API 33) added this as its own runtime permission; the
    // media notification (lock screen / notification-center playback
    // controls) does not post at all without it. A no-op returning
    // already-granted on platforms where it isn't a distinct runtime
    // permission (older Android, desktop, iOS's own separate prompt
    // flow).
    try {
      await Permission.notification.request();
    } catch (_) {
      // Platform doesn't expose this permission at all — nothing to do.
    }
  }

  /// Requests broad storage write access (Android 11+'s "All files
  /// access" — `MANAGE_EXTERNAL_STORAGE`), needed before
  /// `TagEditorPlugin.writeTags` can modify a track's ID3 tags on modern
  /// Android — scoped storage otherwise blocks a raw file write to a
  /// path the app didn't create itself. Unlike a normal runtime
  /// permission, granting this routes through a system Settings screen,
  /// not an in-app dialog — `permission_handler` handles that routing.
  /// Call this once, the first time a write actually needs it (e.g. from
  /// the tag editor UI), not blindly at startup — it's a heavy,
  /// unusual-looking ask for a fresh install to see with no context.
  static Future<bool> requestStorageWrite() async {
    try {
      final status = await Permission.manageExternalStorage.request();
      return status.isGranted;
    } catch (_) {
      // Older Android (pre-scoped-storage) or a non-Android platform:
      // this permission doesn't exist there, and writes already work via
      // the plain filesystem — report success rather than a
      // platform-appropriate false negative.
      return true;
    }
  }

  /// Requests Bluetooth permissions, for a plugin that needs to detect or
  /// control a connected Bluetooth audio device (Android 12+ split
  /// Bluetooth into its own runtime-requestable connect/scan permissions
  /// separate from the old blanket BLUETOOTH/BLUETOOTH_ADMIN manifest
  /// permissions). Returns whether every permission requested was
  /// granted.
  static Future<bool> requestBluetooth() async {
    try {
      final statuses = await [
        Permission.bluetoothConnect,
        Permission.bluetoothScan,
      ].request();
      return statuses.values.every((status) => status.isGranted);
    } catch (_) {
      return false;
    }
  }

  /// Requests location access, for a plugin that needs speed/position
  /// (e.g. driving-mode detection). [always] additionally requests
  /// background location on top of foreground — only pass `true` for a
  /// feature that genuinely needs to detect driving while the app isn't
  /// in the foreground; it's a much heavier ask, shown with a separate,
  /// more scrutinized system prompt on both Android and iOS, and should
  /// never be requested just because [always] defaults to something
  /// convenient.
  static Future<bool> requestLocation({bool always = false}) async {
    try {
      final whenInUse = await Permission.locationWhenInUse.request();
      if (!whenInUse.isGranted) return false;
      if (!always) return true;
      final background = await Permission.locationAlways.request();
      return background.isGranted;
    } catch (_) {
      return false;
    }
  }
}
