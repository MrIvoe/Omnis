import 'package:flutter/material.dart';
import 'package:omnis/ui/player_layouts/player_layout.dart';
import 'package:omnis/ui/player_layouts/player_widgets.dart';
import 'package:omnis/ui/plugin_slot_view.dart';

/// Big synced lyrics dominate the screen; tap to play/pause, swipe to
/// skip. Distinct from the "Lyrics view" switch in Settings (which shows
/// a small lyric box inside any other layout) — this is a whole layout
/// built around the lyric being the primary content.
class KaraokeGesturesLayout extends PlayerLayout {
  @override
  String get id => 'karaoke_gestures';

  @override
  String get name => 'Karaoke Gestures';

  @override
  String get description =>
      'Big synced lyrics with the current line highlighted — tap to '
      'play/pause, swipe to skip.';

  @override
  IconData get icon => Icons.mic_external_on_outlined;

  @override
  bool get definesOwnGestures => true;

  @override
  Widget build(BuildContext context, PlayerLayoutData data) {
    final theme = Theme.of(context);
    final lyricsPlugin = data.lyricsPlugin;
    final text = lyricsPlugin == null
        ? 'The Lyrics plugin is disabled — enable it in Settings.'
        : (data.lyricText ??
            'No lyrics added for this track yet — swipe for the next one, '
                'or add lyrics from another layout.');

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
      child: Column(
        children: [
          const SizedBox(height: 8),
          PluginSlotView(
            pluginManager: data.pluginManager,
            locationId: 'now_playing_overlay',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: PlayerTrackInfo(data: data, large: false),
          ),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: PlayerProgressBar(data: data, interactive: false),
          ),
          const SizedBox(height: 16),
          Icon(
            data.buffering
                ? Icons.hourglass_top
                : (data.playing
                    ? Icons.pause_circle_outline
                    : Icons.play_circle_outline),
            size: 36,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
