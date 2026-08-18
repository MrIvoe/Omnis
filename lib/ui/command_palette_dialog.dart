import 'package:flutter/material.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/command_palette.dart';
import 'package:omnis_plugin_api/playlist.dart';

/// Opens the item 48/spec §38 command palette, now also §37's "search
/// everywhere" overlay (see `command_palette.dart`'s own doc comment for
/// exactly what's covered). [actions] maps a [PaletteCommand.id] to what
/// running it actually does — kept as a plain `Map` supplied by the
/// caller (`HomePage`) rather than baked into this dialog, so this file
/// stays free of `MainCore`/`AudioEngine`/`AppSettings` dependencies, the
/// same "pure UI shell, caller owns the wiring" split `showDialog`-based
/// helpers elsewhere in this app use. [tracks]/[playlists]/[moods] default
/// to empty — an empty query only ever shows commands regardless, so a
/// caller that hasn't wired the rest yet (or a test) still gets the
/// original command-only behavior. A command with no entry in [actions]
/// is simply not runnable — its row still renders (so the full spec-named
/// list stays visible/searchable) but tapping it does nothing, rather
/// than throwing; likewise a track/playlist/mood result with no matching
/// `onSelect*` callback just doesn't act on tap.
Future<void> showCommandPalette(
  BuildContext context, {
  required Map<String, VoidCallback> actions,
  List<BaseTrack> tracks = const [],
  List<Playlist> playlists = const [],
  List<String> moods = const [],
  ValueChanged<BaseTrack>? onSelectTrack,
  ValueChanged<Playlist>? onSelectPlaylist,
  ValueChanged<String>? onSelectMood,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _CommandPaletteDialog(
      actions: actions,
      tracks: tracks,
      playlists: playlists,
      moods: moods,
      onSelectTrack: onSelectTrack,
      onSelectPlaylist: onSelectPlaylist,
      onSelectMood: onSelectMood,
    ),
  );
}

class _CommandPaletteDialog extends StatefulWidget {
  final Map<String, VoidCallback> actions;
  final List<BaseTrack> tracks;
  final List<Playlist> playlists;
  final List<String> moods;
  final ValueChanged<BaseTrack>? onSelectTrack;
  final ValueChanged<Playlist>? onSelectPlaylist;
  final ValueChanged<String>? onSelectMood;

  const _CommandPaletteDialog({
    required this.actions,
    required this.tracks,
    required this.playlists,
    required this.moods,
    required this.onSelectTrack,
    required this.onSelectPlaylist,
    required this.onSelectMood,
  });

  @override
  State<_CommandPaletteDialog> createState() => _CommandPaletteDialogState();
}

class _CommandPaletteDialogState extends State<_CommandPaletteDialog> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static IconData _iconFor(GlobalSearchResultKind kind) => switch (kind) {
        GlobalSearchResultKind.command => Icons.flash_on,
        GlobalSearchResultKind.track => Icons.music_note,
        GlobalSearchResultKind.playlist => Icons.playlist_play,
        GlobalSearchResultKind.mood => Icons.mood,
      };

  static String _labelFor(GlobalSearchResultKind kind) => switch (kind) {
        GlobalSearchResultKind.command => 'Commands',
        GlobalSearchResultKind.track => 'Songs',
        GlobalSearchResultKind.playlist => 'Playlists',
        GlobalSearchResultKind.mood => 'Moods',
      };

  void _select(GlobalSearchResult result) {
    Navigator.of(context).pop();
    switch (result.kind) {
      case GlobalSearchResultKind.command:
        widget.actions[result.actionId]?.call();
      case GlobalSearchResultKind.track:
        final track = widget.tracks
            .where((t) => t.id == result.actionId)
            .firstOrNull;
        if (track != null) widget.onSelectTrack?.call(track);
      case GlobalSearchResultKind.playlist:
        final playlist = widget.playlists
            .where((p) => p.id == result.actionId)
            .firstOrNull;
        if (playlist != null) widget.onSelectPlaylist?.call(playlist);
      case GlobalSearchResultKind.mood:
        widget.onSelectMood?.call(result.actionId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final results = searchEverywhere(
      query: _query,
      tracks: widget.tracks,
      playlists: widget.playlists,
      moods: widget.moods,
    );

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 480),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _controller,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search commands, songs, playlists, moods…',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) => setState(() => _query = value),
                onSubmitted: (_) {
                  if (results.isNotEmpty) _select(results.first);
                },
              ),
              const SizedBox(height: 8),
              Flexible(
                child: results.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text('Nothing matches "$_query".'),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: results.length,
                        itemBuilder: (context, index) {
                          final result = results[index];
                          // A section header before this result's group's
                          // first row — comparing against the previous
                          // result's kind rather than tracking indices
                          // separately, since `searchEverywhere` already
                          // groups same-kind results contiguously.
                          final showHeader = index == 0 ||
                              results[index - 1].kind != result.kind;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (showHeader)
                                Padding(
                                  padding: EdgeInsets.fromLTRB(
                                      16, index == 0 ? 4 : 12, 16, 4),
                                  child: Text(
                                    _labelFor(result.kind),
                                    style: theme.textTheme.labelSmall,
                                  ),
                                ),
                              ListTile(
                                dense: true,
                                leading: Icon(_iconFor(result.kind)),
                                title: Text(result.title),
                                subtitle: result.subtitle != null
                                    ? Text(result.subtitle!)
                                    : null,
                                onTap: () => _select(result),
                              ),
                            ],
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
