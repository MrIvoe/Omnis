import 'package:flutter/material.dart';
import 'package:omnis/ui/theme/omnis_motion.dart';

/// Wraps a single settings row so it can be flashed briefly — the
/// "this is the setting you searched for" cue once `SettingsPage`'s
/// search scrolls a matched row into view. Exposes an imperative
/// [SettingsHighlightState.flash] (reached via a `GlobalKey`) rather than
/// a `bool` prop, matching how `GlobalKey<AnimatedListState>` etc. work —
/// the caller decides *when* to flash (after the scroll finishes), not
/// just whether to.
///
/// Distinct from `library_shimmer.dart`'s loading sweep: that's a
/// continuous, repeating animation; this is a one-shot decay from a
/// highlighted background back to transparent.
class SettingsHighlight extends StatefulWidget {
  final Widget child;

  const SettingsHighlight({super.key, required this.child});

  @override
  State<SettingsHighlight> createState() => SettingsHighlightState();
}

class SettingsHighlightState extends State<SettingsHighlight>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, value: 0.0);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Flashes the highlight once. Safe to call more than once — a second
  /// call restarts from full intensity rather than stacking.
  void flash() {
    _controller.stop();
    _controller.value = 1.0;
    final decayDuration = OmnisMotion.durationFor(OmnisMotion.slow);
    if (decayDuration == Duration.zero) {
      // Reduced motion: hold at full intensity briefly instead of
      // animating the decay — still real feedback that this is the
      // searched-for row, just not an animation.
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) _controller.value = 0.0;
      });
    } else {
      _controller.animateTo(
        0.0,
        duration: decayDuration,
        curve: OmnisMotion.standardCurve,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final highlightColor = Theme.of(context).colorScheme.primaryContainer;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => DecoratedBox(
        decoration: BoxDecoration(
          color: Color.lerp(
              Colors.transparent, highlightColor, _controller.value),
          borderRadius: BorderRadius.circular(12),
        ),
        child: child,
      ),
      child: widget.child,
    );
  }
}

/// Scrolls [key]'s row into view, then flashes it — call once from a
/// settings page's `initState()` when it was opened with a specific
/// field to highlight (from `SettingsPage`'s search). Deferred to a
/// post-frame callback since the row isn't laid out yet during
/// `initState()` itself.
void scrollToAndFlashSetting(GlobalKey<SettingsHighlightState>? key) {
  if (key == null) return;
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    final rowContext = key.currentContext;
    if (rowContext == null) return;
    await Scrollable.ensureVisible(
      rowContext,
      duration: OmnisMotion.durationFor(OmnisMotion.medium),
      curve: OmnisMotion.standardCurve,
    );
    key.currentState?.flash();
  });
}
