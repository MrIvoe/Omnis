import 'package:flutter/material.dart';
import 'package:omnis/ui/player_layouts/player_layout.dart';
import 'package:omnis/ui/player_layouts/player_widgets.dart';

/// Oversized controls on one edge of the screen for safe reach while
/// driving, per [PlayerLayoutData.settings]'s `carModeControlsOnRight`.
/// Deliberately drops everything else this app can show on Now Playing —
/// equalizer, visualizer, sleep timer, lyrics, plugin slots — matching the
/// "as few things to look at as possible" ethos real car UIs use, not an
/// oversight.
class CarModeLayout extends PlayerLayout {
  @override
  String get id => 'car_mode';

  @override
  String get name => 'Car Mode';

  @override
  String get description =>
      'Oversized controls on one edge for safe reach while driving. '
      'Nothing else on screen.';

  @override
  IconData get icon => Icons.directions_car_filled_outlined;

  @override
  Widget build(BuildContext context, PlayerLayoutData data) {
    final theme = Theme.of(context);
    final rightSide = data.settings.carModeControlsOnRight;

    final rail = Container(
      width: 120,
      color: theme.colorScheme.surfaceContainerHighest,
      child: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _CarButton(
              icon: Icons.skip_previous,
              tooltip: 'Previous',
              onPressed: data.onPrevious,
            ),
            _CarButton(
              icon: data.buffering
                  ? Icons.hourglass_top
                  : (data.playing
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_fill),
              tooltip: data.buffering
                  ? 'Buffering'
                  : (data.playing ? 'Pause' : 'Play'),
              onPressed: data.buffering ? null : data.onPlayPause,
              size: 84,
            ),
            _CarButton(
              icon: Icons.skip_next,
              tooltip: 'Next',
              onPressed: data.onNext,
            ),
          ],
        ),
      ),
    );

    final info = Expanded(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PlayerAlbumArt(data: data, size: 140, iconSize: 64),
              const SizedBox(height: 24),
              Text(
                data.track.title,
                style: theme.textTheme.headlineMedium,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Text(
                data.track.artists.join(', '),
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              PlayerProgressBar(data: data, interactive: false),
            ],
          ),
        ),
      ),
    );

    return Row(children: rightSide ? [info, rail] : [rail, info]);
  }
}

class _CarButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;

  const _CarButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = 64,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      iconSize: size,
      icon: Icon(icon),
      tooltip: tooltip,
      onPressed: onPressed,
      padding: const EdgeInsets.all(16),
    );
  }
}
