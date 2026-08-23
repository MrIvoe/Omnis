import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

/// Static, build-time-fixed platform-class flags — never re-evaluated
/// mid-session, since Flutter has no reliable signal for a capability
/// changing at runtime (a keyboard attached to a running Android device,
/// a touchscreen enabled on Windows) without platform-channel work this
/// class deliberately doesn't attempt. Consumed like `AppSettings.instance`
/// elsewhere in this codebase: a plain static read, never an
/// `InheritedWidget`/`ChangeNotifier` — nothing here changes mid-session.
///
/// Every flag answers "does this platform's *typical* input model support
/// X" — not a per-device hardware inventory. An Android tablet with a
/// keyboard case, or a Windows touch-laptop, is a real exception none of
/// these flags detect; that's an accepted trade-off for this pass's scope,
/// not an oversight (see the design spec's "Two platform classes, not a
/// device inventory" note).
class PlatformCapabilities {
  const PlatformCapabilities._();

  /// Android or iOS: touch is the primary input model, no hardware
  /// keyboard is normally attached.
  static bool get isTouchPrimary =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Windows, macOS, or Linux: keyboard+mouse is the primary input model,
  /// no touchscreen is normally present.
  static bool get isDesktopPrimary =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  /// Whether this platform's `Orientation` (derived from window
  /// width-vs-height, not a physical sensor) reflects an actual device
  /// rotation. `false` on desktop platforms, where a window simply being
  /// wider than tall is not "the device rotated to landscape" — the exact
  /// conflation that made the bottom-nav auto-hide and forced-Landscape
  /// Now Playing layout fire on every normal-shaped Windows window by
  /// default (see Task 2). `true` on touch-primary platforms, where
  /// `Orientation` genuinely does reflect a physical rotation.
  static bool get isRotatable => isTouchPrimary;

  /// Whether right-click is a natural alternative to long-press/touch
  /// gestures on this platform. Same value as [isDesktopPrimary] today —
  /// a separate named flag because the *reason* a call site checks this
  /// (offering a right-click context-menu alternative to a touch-only
  /// gesture) is conceptually distinct from "is this a desktop platform,"
  /// even though the two happen to coincide for every platform Omnis
  /// ships today.
  static bool get supportsRightClick => isDesktopPrimary;

  /// Whether the platform exposes a real "choose this specific output
  /// device" API — a genuine OS-capability fact (Android's
  /// `AudioDeviceInfo`/`AndroidAudioManager` surface), not an
  /// input-model/UI-adaptivity decision, but named here for discoverability
  /// alongside every other capability flag in this class. See
  /// `output_device_controller.dart` for the one real implementation this
  /// backs.
  static bool get supportsOutputDeviceSelection =>
      !kIsWeb && Platform.isAndroid;
}
