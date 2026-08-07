import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/ui/widgets/track_artwork.dart' show ArtworkProvider;

/// What renders behind Now Playing's controls — `Positioned.fill`'d
/// beneath the active [PlayerLayout]'s body in the same `Scaffold`, so it
/// works for every layout without each one needing its own background
/// logic. `solid` renders nothing (today's plain scaffold-colored
/// background, unchanged), so this is purely additive.
class NowPlayingBackground extends StatelessWidget {
  final BaseTrack track;

  const NowPlayingBackground({super.key, required this.track});

  @override
  Widget build(BuildContext context) {
    final settings = AppSettings.instance;
    final style = settings.nowPlayingBackgroundStyle;
    final theme = Theme.of(context);

    switch (style) {
      case NowPlayingBackgroundStyle.solid:
        return const SizedBox.shrink();

      case NowPlayingBackgroundStyle.gradient:
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                theme.colorScheme.primary.withValues(alpha: 0.18),
                theme.colorScheme.surface,
              ],
            ),
          ),
        );

      case NowPlayingBackgroundStyle.blurredArt:
        // Falls back to the gradient rather than nothing when
        // transparency is reduced — a user who turned off blur
        // specifically didn't necessarily ask to go back to plain solid
        // too; the gradient still reflects "something's playing" without
        // any `BackdropFilter` cost.
        if (settings.reduceTransparencyEnabled) {
          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  theme.colorScheme.primary.withValues(alpha: 0.18),
                  theme.colorScheme.surface,
                ],
              ),
            ),
          );
        }
        return FutureBuilder<Uint8List?>(
          future: ArtworkProvider.forTrack(track),
          builder: (context, snapshot) {
            final bytes = snapshot.data;
            if (bytes == null || bytes.isEmpty) {
              return DecoratedBox(
                decoration: BoxDecoration(color: theme.colorScheme.surface),
              );
            }
            return Stack(
              fit: StackFit.expand,
              children: [
                Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true),
                BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                  child: Container(
                    color: theme.colorScheme.surface.withValues(alpha: 0.55),
                  ),
                ),
              ],
            );
          },
        );
    }
  }
}
