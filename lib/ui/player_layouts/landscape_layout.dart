import 'package:flutter/material.dart';
import 'package:omnis/ui/player_layouts/player_layout.dart';
import 'package:omnis/ui/player_layouts/player_widgets.dart';
import 'package:omnis/ui/plugin_slot_view.dart';

/// Side-by-side artwork and info, with playback controls pinned to a
/// bottom bar spanning the full width — suited to a wide, short viewport.
/// Selectable explicitly, and also used automatically by the "portrait"
/// layouts (Standard, Top Controls) while the device is rotated, if
/// `AppSettings.autoLandscapeLayout` is on (see `NowPlayingPage`).
class LandscapeLayout extends PlayerLayout {
  @override
  String get id => 'landscape';

  @override
  String get name => 'Landscape';

  @override
  String get description =>
      'Side-by-side artwork and info; controls pinned to the bottom bar.';

  @override
  IconData get icon => Icons.stay_current_landscape;

  @override
  Widget build(BuildContext context, PlayerLayoutData data) {
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                PlayerAlbumArt(data: data, size: 160, iconSize: 72),
                const SizedBox(width: 24),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        PluginSlotView(
                          pluginManager: data.pluginManager,
                          locationId: 'now_playing_overlay',
                        ),
                        PlayerTrackInfo(data: data, align: TextAlign.left),
                        const SizedBox(height: 12),
                        if (data.settings.showLyrics)
                          PlayerLyricsPanel(data: data),
                        const SizedBox(height: 12),
                        PlayerProgressBar(data: data),
                        PlayerCrossfadeStatus(data: data),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                PlayerExtrasRow(data: data),
                const SizedBox(height: 4),
                PlayerControlsRow(data: data),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
