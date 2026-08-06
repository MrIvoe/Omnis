import 'package:flutter/material.dart';
import 'package:omnis/ui/player_layouts/player_layout.dart';
import 'package:omnis/ui/player_layouts/player_widgets.dart';
import 'package:omnis/ui/plugin_slot_view.dart';

/// Playback buttons pinned near the top of the screen, artwork and info
/// below — for anyone who wants the controls to land where a thumb
/// already rests instead of at the bottom of a scroll.
class TopControlsLayout extends PlayerLayout {
  @override
  String get id => 'top_controls';

  @override
  String get name => 'Top Controls';

  @override
  String get description =>
      'Playback buttons pinned to the top, artwork and info below.';

  @override
  IconData get icon => Icons.vertical_align_top;

  @override
  Widget build(BuildContext context, PlayerLayoutData data) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Column(
        children: [
          PlayerControlsRow(data: data),
          const SizedBox(height: 8),
          PlayerExtrasRow(data: data),
          const SizedBox(height: 16),
          PluginSlotView(
            pluginManager: data.pluginManager,
            locationId: 'now_playing_overlay',
          ),
          PlayerAlbumArt(data: data),
          const SizedBox(height: 24),
          PlayerTrackInfo(data: data),
          const SizedBox(height: 16),
          if (data.settings.showLyrics) ...[
            PlayerLyricsPanel(data: data),
            const SizedBox(height: 16),
          ],
          PlayerProgressBar(data: data),
          PlayerCrossfadeStatus(data: data),
          const SizedBox(height: 12),
          PlayerSleepTimerRow(data: data),
          const SizedBox(height: 12),
          PluginSlotView(
            pluginManager: data.pluginManager,
            locationId: 'now_playing_bottom',
            direction: Axis.vertical,
          ),
        ],
      ),
    );
  }
}
