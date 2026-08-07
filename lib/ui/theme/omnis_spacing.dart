import 'package:flutter/widgets.dart';

/// Named spacing constants for every gap/padding value added in `lib/ui/`
/// from here on, so a screen reads as points on one fixed scale instead of
/// each widget inventing its own magic number (`SizedBox(height: 13)` next
/// to `SizedBox(height: 14)` next to `SizedBox(height: 12)` for what was
/// meant to be the same gap).
class OmnisSpacing {
  OmnisSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;

  /// Pre-built `SizedBox`es for the common case of a fixed gap in a
  /// `Column`/`Row` — `OmnisSpacing.gapMd` instead of
  /// `const SizedBox(height: OmnisSpacing.md)` at every call site.
  static const gapXs = SizedBox(width: xs, height: xs);
  static const gapSm = SizedBox(width: sm, height: sm);
  static const gapMd = SizedBox(width: md, height: md);
  static const gapLg = SizedBox(width: lg, height: lg);
  static const gapXl = SizedBox(width: xl, height: xl);

  /// `EdgeInsets.all(md)` etc. — the other common shape, for `Padding`.
  static const paddingXs = EdgeInsets.all(xs);
  static const paddingSm = EdgeInsets.all(sm);
  static const paddingMd = EdgeInsets.all(md);
  static const paddingLg = EdgeInsets.all(lg);
  static const paddingXl = EdgeInsets.all(xl);
}
