import 'dart:async';

import 'package:flutter/material.dart';
import 'package:omnis/core/audio_engine.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/ui/widgets/track_artwork.dart';

/// UI_SPEC §40/§41's "Queue" panel — reachable from the mini-player and
/// Now Playing, showing NOW PLAYING pinned at top and NEXT (the rest of
/// the live queue) as a drag-to-reorder list, without needing to leave
/// whatever screen the user is already on.
///
/// The underlying queue-manipulation logic (`AudioEngine.moveTrack`/
/// `removeTrack`/`playAt`) already existed and was already fully tested —
/// this closes a pure *reachability* gap: before this, the only UI that
/// called it was a full-page "Queue" entry buried inside the Playlist
/// tab's own smart-lists section (`lib/ui/playlist_page.dart`), not
/// discoverable from the mini-player or Now Playing the way the spec
/// describes. That fuller page (snapshot/save-as-playlist/shuffle-
/// remaining/remove-duplicates) still exists and stays the place for
/// those bulk actions — this panel is deliberately the lighter-weight,
/// "quick reorder without leaving what I'm doing" surface, not a
/// replacement.
///
/// A HISTORY section (also named in §41) is a deliberately scoped-out
/// remainder: `IPlayHistoryProvider.recentlyPlayed()` only returns
/// `PlayRecord`s (track id/title/artist/timestamp, not a full
/// `BaseTrack`), so showing it here as real, tappable rows would need a
/// library id-lookup step this panel doesn't have — `PlaylistPage`'s own
/// "Recently Played" smart list already does that resolution and remains
/// the real place to see play history today.
class QueuePanel extends StatefulWidget {
  final AudioEngine engine;

  const QueuePanel({super.key, required this.engine});

  /// Opens the panel as a right-sliding-in bottom sheet — full available
  /// height so a long queue has real room to scroll, matching the
  /// existing `EqualizerSheet.show`/`LyricEditDialog.show` "isScrollControlled
  /// modal sheet" convention this app's other player-adjacent panels
  /// already use.
  static Future<void> show(BuildContext context, AudioEngine engine) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => QueuePanel(engine: engine),
    );
  }

  @override
  State<QueuePanel> createState() => _QueuePanelState();
}

class _QueuePanelState extends State<QueuePanel> {
  StreamSubscription<List<BaseTrack>>? _queueSub;
  StreamSubscription<BaseTrack?>? _trackSub;

  @override
  void initState() {
    super.initState();
    _queueSub = widget.engine.queueStream.listen((_) {
      if (mounted) setState(() {});
    });
    _trackSub = widget.engine.trackStream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _queueSub?.cancel();
    _trackSub?.cancel();
    super.dispose();
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    final currentIndex = widget.engine.currentIndex;
    final splitAt = currentIndex < 0 ? 0 : currentIndex + 1;
    // `oldIndex`/`newIndex` are positions within the NEXT list (already
    // offset past NOW PLAYING) — offset both by `splitAt` to translate to
    // real queue indices, then hand the raw pair straight to `moveTrack`,
    // which already does its own Flutter-reorder-convention adjustment
    // internally (via `QueueOperations.reorder`) — the same "pass the
    // raw values straight through" contract `playlist_page.dart`'s own
    // `_reorderQueue` relies on; re-adjusting here too would double-apply
    // the off-by-one correction.
    await widget.engine.moveTrack(splitAt + oldIndex, splitAt + newIndex);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final queue = widget.engine.queue;
    final currentIndex = widget.engine.currentIndex;
    final current =
        currentIndex >= 0 && currentIndex < queue.length ? queue[currentIndex] : null;
    final splitAt = currentIndex < 0 ? 0 : currentIndex + 1;
    final next = queue.length > splitAt ? queue.sublist(splitAt) : const <BaseTrack>[];

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: Row(
              children: [
                Text('Queue', style: theme.textTheme.titleLarge),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          if (current == null)
            Expanded(
              child: Center(
                child: Text('Nothing playing.', style: theme.textTheme.bodyMedium),
              ),
            )
          else
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Text('NOW PLAYING', style: theme.textTheme.labelSmall),
                  ),
                  ListTile(
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: TrackArtwork(
                          track: current, width: 44, height: 44, iconSize: 20),
                    ),
                    title: Text(current.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(current.artists.join(', '),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: Icon(Icons.graphic_eq, color: theme.colorScheme.primary),
                  ),
                  if (next.isNotEmpty) ...[
                    const Divider(),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Text('NEXT (${next.length})',
                          style: theme.textTheme.labelSmall),
                    ),
                    ReorderableListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: next.length,
                      onReorder: _reorder,
                      itemBuilder: (context, i) {
                        final track = next[i];
                        return Dismissible(
                          key: ValueKey('queue_next:${track.id}:$i'),
                          direction: DismissDirection.endToStart,
                          background: const ColoredBox(
                            color: Colors.transparent,
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: Padding(
                                padding: EdgeInsets.only(right: 16),
                                child: Icon(Icons.delete),
                              ),
                            ),
                          ),
                          onDismissed: (_) =>
                              widget.engine.removeTrack(splitAt + i),
                          child: ListTile(
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: TrackArtwork(
                                  track: track, width: 44, height: 44, iconSize: 20),
                            ),
                            title: Text(track.title,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(track.artists.join(', '),
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            trailing: const Icon(Icons.drag_handle),
                            onTap: () => widget.engine.playAt(splitAt + i),
                          ),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
