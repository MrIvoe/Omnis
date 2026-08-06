import 'package:omnis/ui/player_layouts/car_mode_layout.dart';
import 'package:omnis/ui/player_layouts/full_art_gestures_layout.dart';
import 'package:omnis/ui/player_layouts/karaoke_gestures_layout.dart';
import 'package:omnis/ui/player_layouts/landscape_layout.dart';
import 'package:omnis/ui/player_layouts/player_layout.dart';
import 'package:omnis/ui/player_layouts/standard_layout.dart';
import 'package:omnis/ui/player_layouts/top_controls_layout.dart';

/// The registry of selectable Now Playing layouts.
///
/// **This is the only file to edit when adding a layout**: write a class
/// extending [PlayerLayout] in `lib/ui/player_layouts/`, then add an
/// instance to the list below.
List<PlayerLayout> createPlayerLayouts() => [
      StandardLayout(),
      TopControlsLayout(),
      LandscapeLayout(),
      FullArtGesturesLayout(),
      KaraokeGesturesLayout(),
      CarModeLayout(),
    ];

/// Look up a layout by its persisted id, falling back to the first
/// registered layout (Standard) when the stored id doesn't match anything
/// — e.g. a layout that was since removed, or a preference from an older
/// build.
PlayerLayout resolvePlayerLayout(String id) {
  final layouts = createPlayerLayouts();
  for (final layout in layouts) {
    if (layout.id == id) return layout;
  }
  return layouts.first;
}
