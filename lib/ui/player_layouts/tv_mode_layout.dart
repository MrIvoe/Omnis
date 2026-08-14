import 'package:flutter/material.dart';
import 'package:omnis/ui/player_layouts/player_layout.dart';
import 'package:omnis/ui/player_layouts/player_widgets.dart';

/// Large artwork, large text, large controls, fully navigable with a
/// D-pad or keyboard — the UI spec's §44 "TV" requirement almost
/// verbatim ("Large: Artwork, Text, Controls, Remote navigation. No
/// mouse assumptions.").
///
/// Deliberately does **not** hand-roll arrow-key/D-pad focus handling:
/// Flutter's default focus traversal (`FocusTraversalGroup` +
/// `DefaultFocusTraversalPolicy`, active automatically inside any
/// `MaterialApp`) already moves focus between focusable widgets on
/// arrow-key input, and Android already maps a real D-pad's
/// `KEYCODE_DPAD_*` events to those same logical arrow keys before they
/// ever reach Flutter — writing custom key handling here would just be
/// reimplementing what the framework already does for free, and would
/// risk fighting it. This layout's actual job is arranging real,
/// individually-focusable `IconButton`s in a plain, linear (D-pad
/// traversal doesn't reason about 2D layout the way a mouse does) row,
/// sized for viewing from a couch rather than held in a hand, with
/// `autofocus` on Play/Pause so a remote has something to move away
/// from the moment this screen appears — never landing with nothing
/// focused at all, which is a real, common first-run TV-app bug this
/// deliberately avoids.
class TvModeLayout extends PlayerLayout {
  @override
  String get id => 'tv_mode';

  @override
  String get name => 'TV Mode';

  @override
  String get description =>
      'Large artwork, text, and controls for viewing from a distance — '
      'navigable with a D-pad or keyboard.';

  @override
  IconData get icon => Icons.tv_outlined;

  @override
  Widget build(BuildContext context, PlayerLayoutData data) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Center(
        // A real TV is a large display, but this must still degrade
        // gracefully on anything smaller (a phone/tablet preview, a
        // resized desktop window) rather than overflow — the same
        // SingleChildScrollView guard every other layout with fixed-size
        // content (LandscapeLayout, TopControlsLayout) already uses.
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PlayerAlbumArt(data: data, size: 320, iconSize: 140),
              const SizedBox(height: 32),
              Text(
                data.track.title,
                style: theme.textTheme.displaySmall,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              Text(
                data.track.artists.join(', '),
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: 480,
                child: PlayerProgressBar(data: data, interactive: false),
              ),
              const SizedBox(height: 24),
              // A real 1920px+ TV has plenty of room for three 96px
              // buttons at fixed spacing, but this layout must still
              // render sanely on anything narrower (a phone/tablet
              // preview, a resized desktop window) — a real phone's
              // logical width (~360-400dp) is nowhere near this
              // session's widget-test default viewport (800px), and
              // fixed-size buttons only overflowed on the former, not
              // the latter: caught on a real device, not by the test
              // suite. Sizing the buttons as a function of the actual
              // available width (capped at the original TV-scale sizes)
              // is what makes this genuinely fit either way, rather than
              // picking one more magic number that happens to work on
              // today's specific screen.
              LayoutBuilder(
                builder: (context, constraints) {
                  const gap = 24.0;
                  const iconPadding = 32.0; // IconButton's own 16px * 2
                  // Play/Pause is meant to render noticeably larger than
                  // Previous/Next (sizeRatio), which means it also needs
                  // proportionally more of the row's total width budget
                  // — solving for that directly (rather than sizing all
                  // three from the same per-button share and scaling
                  // Play/Pause up afterwards) is what actually keeps the
                  // row's real total width at or under what's available,
                  // instead of silently overflowing by whatever extra
                  // width that afterwards-scaling added.
                  const sizeRatio = 96 / 72;
                  final smallButtonWidth =
                      (constraints.maxWidth - 2 * gap) / (2 + sizeRatio);
                  final largeButtonWidth = smallButtonWidth * sizeRatio;
                  final iconSize =
                      (smallButtonWidth - iconPadding).clamp(24.0, 72.0);
                  final playPauseIconSize =
                      (largeButtonWidth - iconPadding).clamp(32.0, 96.0);
                  return FocusTraversalGroup(
                    policy: OrderedTraversalPolicy(),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        FocusTraversalOrder(
                          order: const NumericFocusOrder(1),
                          child: _TvButton(
                            key: const ValueKey('tv_mode_previous'),
                            icon: Icons.skip_previous,
                            tooltip: 'Previous',
                            onPressed: data.onPrevious,
                            size: iconSize,
                          ),
                        ),
                        const SizedBox(width: gap),
                        FocusTraversalOrder(
                          order: const NumericFocusOrder(2),
                          child: _TvButton(
                            key: const ValueKey('tv_mode_play_pause'),
                            icon: data.buffering
                                ? Icons.hourglass_top
                                : (data.playing
                                    ? Icons.pause_circle_filled
                                    : Icons.play_circle_fill),
                            tooltip: data.buffering
                                ? 'Buffering'
                                : (data.playing ? 'Pause' : 'Play'),
                            onPressed:
                                data.buffering ? null : data.onPlayPause,
                            size: playPauseIconSize,
                            autofocus: true,
                          ),
                        ),
                        const SizedBox(width: gap),
                        FocusTraversalOrder(
                          order: const NumericFocusOrder(3),
                          child: _TvButton(
                            key: const ValueKey('tv_mode_next'),
                            icon: Icons.skip_next,
                            tooltip: 'Next',
                            onPressed: data.onNext,
                            size: iconSize,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A large, explicitly focusable transport button — [Focus]'s own
/// highlight (a themed outline drawn automatically whenever this widget
/// holds keyboard/D-pad focus, distinct from a mouse hover) is what
/// makes "where is focus right now" visible at TV viewing distance
/// without any extra code here; [IconButton] already draws it, this
/// only needs to size and space things generously enough to see it.
class _TvButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;
  final bool autofocus;

  const _TvButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = 72,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      autofocus: autofocus,
      iconSize: size,
      icon: Icon(icon),
      tooltip: tooltip,
      onPressed: onPressed,
      padding: const EdgeInsets.all(16),
    );
  }
}
