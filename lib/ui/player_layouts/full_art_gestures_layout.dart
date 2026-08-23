import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:omnis/core/platform_capabilities.dart';
import 'package:omnis/ui/player_layouts/player_layout.dart';
import 'package:omnis/ui/player_layouts/player_widgets.dart';
import 'package:omnis/ui/plugin_slot_view.dart';

/// Full-bleed artwork with no visible buttons at all: tap anywhere to
/// play/pause, swipe left/right to skip. The whole point is that it
/// doesn't look like a conventional player — see [definesOwnGestures].
class FullArtGesturesLayout extends PlayerLayout {
  @override
  String get id => 'full_art_gestures';

  @override
  String get name => 'Full Art + Gestures';

  @override
  String get description =>
      'Full-bleed artwork, no visible buttons — tap to play/pause, swipe '
      'to skip.';

  @override
  IconData get icon => Icons.touch_app_outlined;

  @override
  bool get definesOwnGestures => true;

  @override
  Widget build(BuildContext context, PlayerLayoutData data) {
    final theme = Theme.of(context);
    // Tap and swipe-to-skip have no standard screen-reader equivalent — a
    // GestureDetector's onTap alone gets picked up as a semantic tap
    // action, but the horizontal-drag skip gesture wouldn't be reachable
    // at all without the explicit customSemanticsActions below, and
    // neither would have a spoken label without wrapping the whole
    // gesture area in one Semantics node (the layout has no visible
    // buttons for a screen reader to fall back on, by design).
    return Semantics(
      button: true,
      label: data.buffering
          ? 'Now playing. Buffering.'
          : (data.playing
              ? 'Now playing. Double tap to pause.'
              : 'Now playing. Double tap to play.'),
      onTap: data.buffering ? null : data.onPlayPause,
      customSemanticsActions: {
        const CustomSemanticsAction(label: 'Next track'): data.onNext,
        const CustomSemanticsAction(label: 'Previous track'): data.onPrevious,
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: data.onPlayPause,
        // Swipe-to-skip is a touch-primary affordance; a mouse "drag" isn't
        // a gesture desktop-primary users reach for, so this is `null`
        // there rather than a handler nothing points to using — a mouse
        // click is still a real tap, so `onTap` stays active on every
        // platform.
        onHorizontalDragEnd: PlatformCapabilities.isDesktopPrimary
            ? null
            : (details) {
                switch (swipeSkipActionFor(details.primaryVelocity)) {
                  case SwipeSkipAction.next:
                    data.onNext();
                  case SwipeSkipAction.previous:
                    data.onPrevious();
                  case null:
                    break;
                }
              },
        child: Stack(
          fit: StackFit.expand,
          children: [
            ExcludeSemantics(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      theme.colorScheme.primaryContainer,
                      theme.colorScheme.surface,
                    ],
                  ),
                ),
              ),
            ),
            ExcludeSemantics(
              child: Center(
                child: Icon(
                  Icons.album,
                  size: 220,
                  color:
                      theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.5),
                ),
              ),
            ),
            Positioned(
              top: 12,
              left: 0,
              right: 0,
              child: Center(
                child: PluginSlotView(
                  pluginManager: data.pluginManager,
                  locationId: 'now_playing_overlay',
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      theme.colorScheme.scrim.withValues(alpha: 0.35),
                    ],
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PlayerTrackInfo(
                        data: data, color: theme.colorScheme.onSurface),
                    const SizedBox(height: 12),
                    PlayerProgressBar(data: data, interactive: false),
                    const SizedBox(height: 8),
                    // A state indicator, not a tap target of its own — the
                    // whole screen is already the tap target, and its state
                    // is already spoken by the outer Semantics label above.
                    ExcludeSemantics(
                      child: Icon(
                        data.buffering
                            ? Icons.hourglass_top
                            : (data.playing
                                ? Icons.pause_circle_outline
                                : Icons.play_circle_outline),
                        size: 40,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
