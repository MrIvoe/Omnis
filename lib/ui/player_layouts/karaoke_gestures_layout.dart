import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:omnis/plugin_api/lyric_line.dart';
import 'package:omnis/plugin_api/service_interfaces.dart';
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
    // `ISyncedLyricsProvider` is a separate, optional capability a
    // registered `ILyricsProvider` may or may not also implement — see
    // that interface's own doc. `null` means "nothing synced for this
    // track" — this layout's whole premise is lyrics-as-primary-content,
    // so whenever a synced list genuinely exists it gets the biggest,
    // most prominent version of the scrolling+highlighting treatment
    // `PlayerLyricsPanel` also uses, rather than only ever showing one
    // line the way this layout used to.
    List<LyricLine>? syncedLines;
    if (lyricsPlugin is ISyncedLyricsProvider) {
      syncedLines =
          (lyricsPlugin as ISyncedLyricsProvider).syncedLyricsFor(data.track);
    }

    // Unlike full_art_gestures_layout, this layout's primary content (the
    // lyric line) is already real, readable text — so this uses `hint`,
    // not `label`, to add the tap/swipe affordance without replacing what
    // a screen reader would otherwise read from the lyric/track info text
    // nested inside.
    return Semantics(
      hint: 'Double tap to play or pause. Swipe to skip.',
      onTap: data.buffering ? null : data.onPlayPause,
      customSemanticsActions: {
        const CustomSemanticsAction(label: 'Next track'): data.onNext,
        const CustomSemanticsAction(label: 'Previous track'): data.onPrevious,
      },
      child: GestureDetector(
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
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: syncedLines != null && syncedLines.isNotEmpty
                    ? SyncedLyricsView(
                        lines: syncedLines,
                        position: data.position,
                        lineExtent: 72,
                        activeStyle: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                        inactiveStyle: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color:
                              theme.colorScheme.onSurface.withValues(alpha: 0.35),
                        ),
                      )
                    : Center(
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
            ExcludeSemantics(
              child: Icon(
                data.buffering
                    ? Icons.hourglass_top
                    : (data.playing
                        ? Icons.pause_circle_outline
                        : Icons.play_circle_outline),
                size: 36,
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
