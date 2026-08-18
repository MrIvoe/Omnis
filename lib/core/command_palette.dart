import 'package:omnis/core/base_track.dart';
import 'package:omnis_plugin_api/playlist.dart';

/// Item 48/spec §38's "no global Ctrl+K search or command palette" gap —
/// the fixed-action half of it, plus §37's sibling "search everywhere"
/// overlay (Songs/Playlists/Moods/Commands — see [searchEverywhere]'s own
/// doc comment for why Artists/Albums/Settings are a deliberately scoped
/// remainder, not silently dropped).
///
/// Pure data/matching only — action callbacks live in the UI layer
/// (`lib/ui/command_palette_dialog.dart`/`lib/ui/home_page.dart`), the same
/// split `settings_page.dart`'s own `_SearchableSetting` (data) vs. its
/// `navigate` closures (UI) already establishes.
class PaletteCommand {
  final String id;
  final String title;
  final List<String> keywords;

  const PaletteCommand({
    required this.id,
    required this.title,
    this.keywords = const [],
  });
}

/// The spec-named command list §38 asks for, minus three deliberately
/// deferred (documented in the closing build-log entry, not silently
/// dropped): "Add to playlist" (needs a target track — the palette has no
/// natural "current track" concept beyond whatever's currently playing,
/// and silently defaulting to that is a real product decision, not an
/// obvious wiring task), "Create mood" (needs the Moods tab's own creation
/// flow), and "Toggle visualizer" (local `State` tied to a loaded
/// `VisualizerPlugin` instance on the Now Playing page — only meaningful,
/// and only reachable, while already there; `HomePage`, where this
/// palette lives, has no access to that state).
const List<PaletteCommand> paletteCommands = [
  PaletteCommand(id: 'play', title: 'Play'),
  PaletteCommand(id: 'pause', title: 'Pause'),
  PaletteCommand(id: 'next', title: 'Next', keywords: ['skip']),
  PaletteCommand(id: 'previous', title: 'Previous', keywords: ['back']),
  PaletteCommand(id: 'shuffle', title: 'Shuffle'),
  PaletteCommand(
      id: 'open_settings', title: 'Open settings', keywords: ['preferences']),
  PaletteCommand(
      id: 'enable_driving_mode',
      title: 'Enable driving mode',
      keywords: ['car mode', 'driving']),
  PaletteCommand(id: 'open_lyrics', title: 'Open lyrics', keywords: ['sing']),
  PaletteCommand(
      id: 'change_theme', title: 'Change theme', keywords: ['appearance']),
  PaletteCommand(id: 'customize_home', title: 'Customize home'),
  PaletteCommand(
      id: 'scan_library', title: 'Scan library', keywords: ['rescan']),
];

/// Ranks [commands] against [query] — empty/whitespace-only returns every
/// command, in [paletteCommands]'s own fixed order. A non-empty query
/// keeps only commands whose title or any keyword contains it
/// (case-insensitive), with a title *starting with* the query ranked above
/// one that merely contains it elsewhere — a small, honestly-scoped
/// ranking, not a full fuzzy-match library, the same plain-`.contains()`
/// restraint `settings_page.dart`'s own search already takes.
List<PaletteCommand> matchCommands(
  String query, [
  List<PaletteCommand> commands = paletteCommands,
]) {
  final trimmed = query.trim().toLowerCase();
  if (trimmed.isEmpty) return List.of(commands);

  final matches = <PaletteCommand>[];
  for (final command in commands) {
    final title = command.title.toLowerCase();
    final matchesTitle = title.contains(trimmed);
    final matchesKeyword =
        command.keywords.any((k) => k.toLowerCase().contains(trimmed));
    if (matchesTitle || matchesKeyword) matches.add(command);
  }

  matches.sort((a, b) {
    final aStarts = a.title.toLowerCase().startsWith(trimmed);
    final bStarts = b.title.toLowerCase().startsWith(trimmed);
    if (aStarts != bStarts) return aStarts ? -1 : 1;
    return 0;
  });
  return matches;
}

/// What kind of thing a [GlobalSearchResult] points at — the dialog
/// groups results by this and the caller (`home_page.dart`) dispatches on
/// it to decide what "select this result" actually does.
enum GlobalSearchResultKind { command, track, playlist, mood }

/// One row in the §37 "search everywhere" overlay. [actionId] is
/// kind-specific: a [PaletteCommand.id] for [GlobalSearchResultKind.command],
/// a [BaseTrack.id] for [GlobalSearchResultKind.track], a [Playlist.id] for
/// [GlobalSearchResultKind.playlist], or the mood/preset query string
/// itself for [GlobalSearchResultKind.mood] — the same string
/// `IQueueBuilder.buildQueueFor` already takes.
class GlobalSearchResult {
  final GlobalSearchResultKind kind;
  final String title;
  final String? subtitle;
  final String actionId;

  const GlobalSearchResult({
    required this.kind,
    required this.title,
    this.subtitle,
    required this.actionId,
  });
}

/// §37's "search everywhere" overlay: one query across Commands, Songs,
/// Playlists, and Moods/presets. Deliberately **not** Artists/Albums
/// (there's no dedicated "browse by artist/album" result view to land on
/// — item 10's own full-text library search already finds a track by
/// artist/album name, which is where a search for either would end up
/// anyway) or Settings (`settings_page.dart`'s `_SearchableSetting` index
/// is tightly coupled to that page's own `BuildContext`-bound `navigate`
/// closures — pulling it out into a caller-agnostic data list is a real,
/// separately-sized refactor of that file, not attempted here; "Open
/// settings" already surfaces as a [PaletteCommand], and that page has its
/// own search bar once you're there).
///
/// An empty [query] returns every command in [commands]' own order and
/// nothing else — identical to [matchCommands]' own empty-query behavior,
/// so a freshly-opened palette with nothing typed looks exactly as it did
/// before this function existed. A non-empty query keeps command-matching
/// exactly as [matchCommands] already does, and additionally keeps up to
/// [limitPerCategory] tracks/playlists/moods whose name contains it
/// case-insensitively (a track also matches on artist name) — the same
/// plain-`.contains()` restraint every other search surface in this
/// codebase takes, not a fuzzy-match library.
List<GlobalSearchResult> searchEverywhere({
  required String query,
  List<PaletteCommand> commands = paletteCommands,
  List<BaseTrack> tracks = const [],
  List<Playlist> playlists = const [],
  List<String> moods = const [],
  int limitPerCategory = 5,
}) {
  final results = <GlobalSearchResult>[
    for (final c in matchCommands(query, commands))
      GlobalSearchResult(
          kind: GlobalSearchResultKind.command,
          title: c.title,
          actionId: c.id),
  ];

  final trimmed = query.trim().toLowerCase();
  if (trimmed.isEmpty) return results;

  final matchedTracks = tracks.where((t) =>
      t.title.toLowerCase().contains(trimmed) ||
      t.artists.any((a) => a.toLowerCase().contains(trimmed)));
  for (final t in matchedTracks.take(limitPerCategory)) {
    results.add(GlobalSearchResult(
      kind: GlobalSearchResultKind.track,
      title: t.title,
      subtitle: t.artists.isNotEmpty ? t.artists.join(', ') : null,
      actionId: t.id,
    ));
  }

  final matchedPlaylists =
      playlists.where((p) => p.name.toLowerCase().contains(trimmed));
  for (final p in matchedPlaylists.take(limitPerCategory)) {
    results.add(GlobalSearchResult(
      kind: GlobalSearchResultKind.playlist,
      title: p.name,
      actionId: p.id,
    ));
  }

  final matchedMoods = moods.where((m) => m.toLowerCase().contains(trimmed));
  for (final m in matchedMoods.take(limitPerCategory)) {
    results.add(GlobalSearchResult(
      kind: GlobalSearchResultKind.mood,
      title: m,
      actionId: m,
    ));
  }

  return results;
}
