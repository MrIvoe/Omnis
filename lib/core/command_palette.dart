/// Item 48/spec §38's "no global Ctrl+K search or command palette" gap —
/// the fixed-action half of it. §37's sibling "search everywhere" overlay
/// (Songs/Artists/Albums/Playlists/Moods/Settings/Commands) is a materially
/// bigger lift needing to query the library/mood/playlist stores, not just
/// execute a fixed action list, and item 10 (Search) already has a
/// full-text library search surface elsewhere in the app — deliberately
/// left open as this gap's documented remainder, not attempted here.
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
