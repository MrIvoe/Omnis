import 'package:flutter/material.dart';
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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: data.onPlayPause,
      onHorizontalDragEnd: (details) {
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
          DecoratedBox(
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
          Center(
            child: Icon(
              Icons.album,
              size: 220,
              color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.5),
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
                  PlayerTrackInfo(data: data, color: theme.colorScheme.onSurface),
                  const SizedBox(height: 12),
                  PlayerProgressBar(data: data, interactive: false),
                  const SizedBox(height: 8),
                  // A state indicator, not a tap target of its own — the
                  // whole screen is already the tap target.
                  Icon(
                    data.buffering
                        ? Icons.hourglass_top
                        : (data.playing
                            ? Icons.pause_circle_outline
                            : Icons.play_circle_outline),
                    size: 40,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
