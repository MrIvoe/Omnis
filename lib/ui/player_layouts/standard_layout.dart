import 'package:flutter/material.dart';
import 'package:omnis/plugins/visualizer_plugin.dart';
import 'package:omnis/ui/player_layouts/player_layout.dart';
import 'package:omnis/ui/player_layouts/player_widgets.dart';
import 'package:omnis/ui/plugin_slot_view.dart';
import 'package:omnis/ui/widgets/track_artwork.dart';

/// The default Now Playing arrangement: album art fills the screen as a
/// background layer — darkened with a scrim so text and controls stay
/// readable over any image — with track info and playback controls fixed
/// on top of it. Nothing here scrolls except the lyrics panel, which can
/// hold a whole song's worth of text; every other piece of Now Playing
/// stays put so the screen reads as one focused view, not something you
/// scroll through to find the controls.
class StandardLayout extends PlayerLayout {
  @override
  String get id => 'standard';

  @override
  String get name => 'Standard';

  @override
  String get description =>
      'Album art fills the background; controls and info stay fixed on '
      'top. Only the lyrics scroll.';

  @override
  IconData get icon => Icons.view_agenda_outlined;

  @override
  Widget build(BuildContext context, PlayerLayoutData data) {
    final theme = Theme.of(context);
    final showLyrics = data.settings.showLyrics;
    final showArt = data.settings.showAlbumArt;

    // White-on-scrim text/controls read reliably over any embedded
    // artwork — light or dark app theme, bright or dark photo — the same
    // way a lock-screen media background works. Nested shared widgets
    // (PlayerTrackInfo, PlayerProgressBar's Slider, PlayerControlsRow,
    // PlayerLyricsPanel) inherit this via Theme rather than each needing
    // their own color plumbing.
    final overlayTheme = theme.copyWith(
      colorScheme: theme.colorScheme.copyWith(
        onSurface: Colors.white,
        primary: Colors.white,
      ),
      iconTheme: const IconThemeData(color: Colors.white),
      textTheme: theme.textTheme.apply(
        bodyColor: Colors.white,
        displayColor: Colors.white,
      ),
      sliderTheme: theme.sliderTheme.copyWith(
        activeTrackColor: Colors.white,
        thumbColor: Colors.white,
        inactiveTrackColor: Colors.white24,
        overlayColor: Colors.white24,
      ),
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        if (showArt)
          Positioned.fill(
            child: TrackArtwork(track: data.track, fit: BoxFit.cover),
          )
        else
          Positioned.fill(
            child: ColoredBox(color: theme.colorScheme.primaryContainer),
          ),
        // Darkens top-to-bottom so the app bar and bottom controls both
        // stay legible regardless of what's brightest in the artwork.
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.45),
                  Colors.black.withValues(alpha: 0.35),
                  Colors.black.withValues(alpha: 0.65),
                ],
                stops: const [0.0, 0.45, 1.0],
              ),
            ),
          ),
        ),
        Theme(
          data: overlayTheme,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: Column(
                children: [
                  PluginSlotView(
                    pluginManager: data.pluginManager,
                    locationId: 'now_playing_overlay',
                  ),
                  const SizedBox(height: 8),
                  PlayerTrackInfo(data: data, color: Colors.white),
                  const SizedBox(height: 12),
                  Expanded(
                    child: showLyrics
                        ? Column(
                            children: [
                              Expanded(
                                child: PlayerLyricsPanel(
                                  data: data,
                                  style: (data.settings.karaokeMode
                                          ? theme.textTheme.titleMedium
                                              ?.copyWith(
                                                  fontWeight: FontWeight.bold)
                                          : theme.textTheme.bodyMedium)
                                      ?.copyWith(color: Colors.white),
                                ),
                              ),
                              if (data.visualizerPlugin != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: VisualizerBars(
                                      plugin: data.visualizerPlugin!),
                                ),
                            ],
                          )
                        : (data.visualizerPlugin != null
                            ? Center(
                                child: VisualizerBars(
                                    plugin: data.visualizerPlugin!),
                              )
                            : const SizedBox.shrink()),
                  ),
                  const SizedBox(height: 8),
                  PlayerProgressBar(data: data),
                  PlayerCrossfadeStatus(data: data),
                  const SizedBox(height: 4),
                  PlayerExtrasRow(data: data),
                  const SizedBox(height: 8),
                  PlayerControlsRow(data: data),
                  const SizedBox(height: 4),
                  PlayerSleepTimerRow(data: data),
                  PluginSlotView(
                    pluginManager: data.pluginManager,
                    locationId: 'now_playing_bottom',
                    direction: Axis.vertical,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
