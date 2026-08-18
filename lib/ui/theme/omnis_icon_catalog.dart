import 'package:flutter/material.dart';
import 'package:omnis/ui/theme/omnis_icon_style.dart';

/// The closed set of glyphs [OmnisIconStyle.current] can restyle — one
/// [ThemedIcon] per icon used at a "high-visibility" call site (the home
/// shell's bottom nav/rail, Now Playing's transport row, and the Library
/// page's view-mode/display-mode controls), each hand-verified against
/// this project's own bundled Flutter SDK (3.27.4) to actually have all
/// four `Icons.xxx`/`_outlined`/`_rounded`/`_sharp` renderings — not every
/// Material glyph does, so this catalog is deliberately a curated subset
/// rather than every `Icons.*` reference in `lib/ui/`.
///
/// Every constant here references real `Icons.xxx` fields directly (never
/// built from a string), which is what lets Flutter's icon tree-shaker
/// keep exactly these glyphs and nothing else in a release build.
class OmnisIconCatalog {
  OmnisIconCatalog._();

  // --- Home shell bottom nav / side rail (`home_page.dart`'s
  //     `destinations` list) ---
  static const home = ThemedIcon(
    filled: Icons.home,
    outlined: Icons.home_outlined,
    rounded: Icons.home_rounded,
    sharp: Icons.home_sharp,
  );
  static const libraryMusic = ThemedIcon(
    filled: Icons.library_music,
    outlined: Icons.library_music_outlined,
    rounded: Icons.library_music_rounded,
    sharp: Icons.library_music_sharp,
  );
  static const playlistPlay = ThemedIcon(
    filled: Icons.playlist_play,
    outlined: Icons.playlist_play_outlined,
    rounded: Icons.playlist_play_rounded,
    sharp: Icons.playlist_play_sharp,
  );
  static const mood = ThemedIcon(
    filled: Icons.mood,
    outlined: Icons.mood_outlined,
    rounded: Icons.mood_rounded,
    sharp: Icons.mood_sharp,
  );
  static const cloudQueue = ThemedIcon(
    filled: Icons.cloud_queue,
    outlined: Icons.cloud_queue_outlined,
    rounded: Icons.cloud_queue_rounded,
    sharp: Icons.cloud_queue_sharp,
  );
  static const settings = ThemedIcon(
    filled: Icons.settings,
    outlined: Icons.settings_outlined,
    rounded: Icons.settings_rounded,
    sharp: Icons.settings_sharp,
  );

  // --- Now Playing transport row (`PlayerControlsRow` in
  //     `lib/ui/player_layouts/player_widgets.dart`). Play/pause itself
  //     isn't here: it's rendered with `AnimatedIcon`/`AnimatedIcons.
  //     play_pause`, Flutter's built-in glyph-morph primitive, which is
  //     a wholly separate mechanism from `Icons.xxx` style suffixes and
  //     has no outlined/rounded/sharp counterpart to switch to. ---
  static const skipPrevious = ThemedIcon(
    filled: Icons.skip_previous,
    outlined: Icons.skip_previous_outlined,
    rounded: Icons.skip_previous_rounded,
    sharp: Icons.skip_previous_sharp,
  );
  static const skipNext = ThemedIcon(
    filled: Icons.skip_next,
    outlined: Icons.skip_next_outlined,
    rounded: Icons.skip_next_rounded,
    sharp: Icons.skip_next_sharp,
  );
  static const shuffle = ThemedIcon(
    filled: Icons.shuffle,
    outlined: Icons.shuffle_outlined,
    rounded: Icons.shuffle_rounded,
    sharp: Icons.shuffle_sharp,
  );
  static const repeat = ThemedIcon(
    filled: Icons.repeat,
    outlined: Icons.repeat_outlined,
    rounded: Icons.repeat_rounded,
    sharp: Icons.repeat_sharp,
  );
  static const repeatOne = ThemedIcon(
    filled: Icons.repeat_one,
    outlined: Icons.repeat_one_outlined,
    rounded: Icons.repeat_one_rounded,
    sharp: Icons.repeat_one_sharp,
  );
  static const replay10 = ThemedIcon(
    filled: Icons.replay_10,
    outlined: Icons.replay_10_outlined,
    rounded: Icons.replay_10_rounded,
    sharp: Icons.replay_10_sharp,
  );
  static const forward10 = ThemedIcon(
    filled: Icons.forward_10,
    outlined: Icons.forward_10_outlined,
    rounded: Icons.forward_10_rounded,
    sharp: Icons.forward_10_sharp,
  );
  static const replay30 = ThemedIcon(
    filled: Icons.replay_30,
    outlined: Icons.replay_30_outlined,
    rounded: Icons.replay_30_rounded,
    sharp: Icons.replay_30_sharp,
  );
  static const forward30 = ThemedIcon(
    filled: Icons.forward_30,
    outlined: Icons.forward_30_outlined,
    rounded: Icons.forward_30_rounded,
    sharp: Icons.forward_30_sharp,
  );

  // --- Library page (`lib/ui/library_page.dart`): the
  //     songs/albums/artists/genres/folders view-mode `SegmentedButton`,
  //     plus the grid/list display-mode toggle. ---
  static const musicNote = ThemedIcon(
    filled: Icons.music_note,
    outlined: Icons.music_note_outlined,
    rounded: Icons.music_note_rounded,
    sharp: Icons.music_note_sharp,
  );
  static const album = ThemedIcon(
    filled: Icons.album,
    outlined: Icons.album_outlined,
    rounded: Icons.album_rounded,
    sharp: Icons.album_sharp,
  );
  static const person = ThemedIcon(
    filled: Icons.person,
    outlined: Icons.person_outlined,
    rounded: Icons.person_rounded,
    sharp: Icons.person_sharp,
  );
  static const tag = ThemedIcon(
    filled: Icons.tag,
    outlined: Icons.tag_outlined,
    rounded: Icons.tag_rounded,
    sharp: Icons.tag_sharp,
  );
  static const folder = ThemedIcon(
    filled: Icons.folder,
    outlined: Icons.folder_outlined,
    rounded: Icons.folder_rounded,
    sharp: Icons.folder_sharp,
  );
  static const gridView = ThemedIcon(
    filled: Icons.grid_view,
    outlined: Icons.grid_view_outlined,
    rounded: Icons.grid_view_rounded,
    sharp: Icons.grid_view_sharp,
  );
  static const viewList = ThemedIcon(
    filled: Icons.view_list,
    outlined: Icons.view_list_outlined,
    rounded: Icons.view_list_rounded,
    sharp: Icons.view_list_sharp,
  );
}
