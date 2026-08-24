import 'package:permission_handler/permission_handler.dart';

/// Central place for requesting OS permissions Omnis or its plugins need,
/// beyond what `on_audio_query` already handles internally for library
/// scanning (see `MediaScanner._scanAndroid`'s `checkAndRequest()` call —
/// storage/media read is already covered and doesn't go through here).
///
/// Not a blanket ask-everything-upfront approach — asking for a permission
/// a fresh install has no use for yet is exactly the kind of "why does
/// this app want that" moment that makes people distrust an app, and both
/// Android and iOS guidance says to ask in context, not upfront. But it
/// isn't purely contextual/lazy either. [ensureCorePermissions] covers
/// what the Core itself needs to function normally (right now: posting
/// the media notification) and is called once at startup, always.
/// [requestStorageWrite]/[requestBluetooth]/[requestLocation]/
/// [requestMicrophone] are each plugin-specific asks with two distinct
/// callers: [ensureUpfrontPermissions] batches them once, at first run,
/// scoped to whichever plugins are already enabled by then (see that
/// method's own doc); a plugin enabled *after* first run instead triggers
/// the same method on its own, contextually, via `PluginContext`, exactly
/// as before this batching entry point existed. Either way, the
/// individual `request*` methods stay the single place that actually
/// calls into `permission_handler`.
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

  /// Requests microphone access, for a plugin that taps system audio via
  /// an API the OS gates behind this permission even when it isn't
  /// actually recording from the physical mic (e.g. Android's Visualizer
  /// API, which VisualizerPlugin uses).
  static Future<bool> requestMicrophone() async {
    try {
      final status = await Permission.microphone.request();
      return status.isGranted;
    } catch (_) {
      return false;
    }
  }

  /// Requests everything the Core needs plus whatever [enabledPluginIds]
  /// need, in one batch — called once, at first run, after the plugin
  /// manager has completed its first pass over which plugins are enabled
  /// by default. A plugin enabled *later* still requests its own
  /// permission contextually via `PluginContext`, unchanged — this method
  /// only covers what's already enabled at the moment it's called, which
  /// is what keeps "ask upfront" compatible with "no plugins installed
  /// means nothing to ask for": a fresh install with every optional
  /// plugin left at its default (some enabled, some not) only sees
  /// prompts for what's actually active, not a hypothetical maximum.
  static Future<void> ensureUpfrontPermissions(
      Set<String> enabledPluginIds) async {
    await ensureCorePermissions();
    if (enabledPluginIds.contains('tag_editor')) {
      await requestStorageWrite();
    }
    if (enabledPluginIds.contains('bluetooth_playback')) {
      await requestBluetooth();
    }
    if (enabledPluginIds.contains('driving_mode')) {
      await requestLocation();
    }
    if (enabledPluginIds.contains('visualizer')) {
      await requestMicrophone();
    }
  }
}
