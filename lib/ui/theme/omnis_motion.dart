import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:omnis/core/app_settings.dart';

/// Single source of truth for animation durations/curves and haptic
/// feedback, so every animation and every haptic tap in the app is
/// consistent instead of each screen inventing its own timing — and so
/// every one of them can be turned off together, from one place, via
/// [AppSettings.reduceMotionEnabled] / [AppSettings.hapticFeedbackEnabled].
///
/// There's no `BuildContext`-based lookup here (no `InheritedWidget`,
/// no Provider/Riverpod in this project — see `AppSettings`'s own doc
/// comment) — every animation just reads the same
/// `AppSettings.instance` singleton everything else in `lib/ui/` already
/// does.
class OmnisMotion {
  OmnisMotion._();

  static const fast = Duration(milliseconds: 150);
  static const medium = Duration(milliseconds: 300);
  static const slow = Duration(milliseconds: 450);

  static const standardCurve = Curves.easeInOutCubic;
  static const emphasizedCurve = Curves.easeOutBack;

  /// Set by whatever applies the active theme (built-in preset or a
  /// declarative import's `motion.style`) — `0.6` for `snappy`, `1.0` for
  /// `standard`, `1.6` for `gentle`. Deliberately a plain multiplier on a
  /// plain `double`, not a `ThemeMotionStyle` field here: that enum lives
  /// in `lib/ui/theme/declarative/`, and this token file must not depend
  /// on the declarative layer built on top of it — dependencies point
  /// one way only.
  static double styleMultiplier = 1.0;

  /// [base] scaled by [styleMultiplier], or [Duration.zero] when the user
  /// has reduce-motion on.
  ///
  /// `Duration.zero` rather than merely "shorter": most Flutter animation
  /// widgets (`AnimatedSwitcher`, `AnimatedContainer`, `AnimatedSize`)
  /// treat a zero duration as "jump straight to the end state" — which is
  /// exactly what "reduce motion" is supposed to mean, not just "make it
  /// quick."
  static Duration durationFor(Duration base) {
    if (AppSettings.instance.reduceMotionEnabled) return Duration.zero;
    if (styleMultiplier == 1.0) return base;
    return base * styleMultiplier;
  }
}

/// Gated haptic feedback — every call site in `lib/ui/` should go through
/// here rather than `HapticFeedback` directly, so
/// [AppSettings.hapticFeedbackEnabled] is checked in exactly one place
/// instead of being copy-pasted at every tap/scrub/toggle that wants a
/// buzz.
class OmnisHaptics {
  OmnisHaptics._();

  /// A light tick — scrubbing the seek bar, toggling a favorite,
  /// reordering the queue.
  static void selectionClick() {
    if (AppSettings.instance.hapticFeedbackEnabled) {
      HapticFeedback.selectionClick();
    }
  }

  /// A firmer thud — a meaningful action completed (plugin installed,
  /// sleep timer set).
  static void mediumImpact() {
    if (AppSettings.instance.hapticFeedbackEnabled) {
      HapticFeedback.mediumImpact();
    }
  }
}
