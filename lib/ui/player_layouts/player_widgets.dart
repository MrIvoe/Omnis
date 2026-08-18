import 'package:flutter/material.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/plugin_api/lyric_line.dart';
import 'package:omnis/plugin_api/service_interfaces.dart';
import 'package:omnis/ui/player_layouts/player_layout.dart';
import 'package:omnis/ui/theme/omnis_icon_catalog.dart';
import 'package:omnis/ui/theme/omnis_motion.dart';
import 'package:omnis/ui/widgets/seek_position_visualizer.dart';
import 'package:omnis/ui/widgets/track_artwork.dart';
import 'package:omnis/ui/widgets/waveform_seek_bar.dart';

/// Shared building blocks every [PlayerLayout] composes differently.
/// Keeping these here means a new layout is mostly arrangement, not
/// reimplementation.

class PlayerAlbumArt extends StatelessWidget {
  final PlayerLayoutData data;
  final double size;
  final double iconSize;

  const PlayerAlbumArt({
    super.key,
    required this.data,
    this.size = 220,
    this.iconSize = 96,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!data.settings.showAlbumArt) {
      return Icon(Icons.music_note,
          size: iconSize * 0.75, color: theme.colorScheme.primary);
    }
    return Transform.scale(
      scale: data.settings.albumArtScale,
      // Matches MiniPlayerBar's own Hero tag on this exact string — the
      // shared-element flight from the mini-player to this, the full
      // Now Playing screen, when reached via the real pushed route
      // MiniPlayerBar uses (not the old bottom-nav-tab embedding, which
      // has no route boundary for Hero to animate across).
      child: Hero(
        tag: 'now_playing_art',
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: theme.colorScheme.shadow.withValues(alpha: 0.15),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          // Keyed by track id so a track change swaps in a fresh
          // `TrackArtwork` — a hard cut before this — via a fade+scale
          // crossfade instead. Every bundled layout goes through
          // `PlayerAlbumArt`, so this one change covers all six at once.
          child: AnimatedSwitcher(
            duration: OmnisMotion.durationFor(OmnisMotion.medium),
            switchInCurve: OmnisMotion.standardCurve,
            switchOutCurve: OmnisMotion.standardCurve,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween(begin: 0.94, end: 1.0).animate(animation),
                child: child,
              ),
            ),
            child: TrackArtwork(
              key: ValueKey(data.track.id),
              track: data.track,
              width: size,
              height: size,
              borderRadius: BorderRadius.circular(24),
              iconSize: iconSize,
            ),
          ),
        ),
      ),
    );
  }
}

class PlayerTrackInfo extends StatelessWidget {
  final PlayerLayoutData data;
  final TextAlign align;
  final bool large;
  final Color? color;

  const PlayerTrackInfo({
    super.key,
    required this.data,
    this.align = TextAlign.center,
    this.large = true,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: align == TextAlign.center
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Text(
          data.track.title,
          style: (large
                  ? theme.textTheme.headlineSmall
                  : theme.textTheme.titleMedium)
              ?.copyWith(color: color),
          textAlign: align,
        ),
        const SizedBox(height: 4),
        Text(
          data.track.artists.join(', '),
          style: theme.textTheme.bodyLarge
              ?.copyWith(color: color?.withValues(alpha: 0.8)),
          textAlign: align,
        ),
      ],
    );
  }
}

/// The playback position bar. [interactive] false renders a slim,
/// non-interactive line instead of a draggable [Slider] — used by the
/// gesture-first and car-mode layouts, which deliberately keep few or no
/// tap targets beyond their primary gesture/control scheme.
class PlayerProgressBar extends StatelessWidget {
  final PlayerLayoutData data;
  final bool interactive;

  const PlayerProgressBar({
    super.key,
    required this.data,
    this.interactive = true,
  });

  @override
  Widget build(BuildContext context) {
    final total = data.duration ?? Duration.zero;
    final hasLength = total.inMilliseconds > 0;
    final value = hasLength
        ? data.position.inMilliseconds.clamp(0, total.inMilliseconds).toDouble()
        : 0.0;
    final max = hasLength ? total.inMilliseconds.toDouble() : 1.0;

    if (!interactive) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: LinearProgressIndicator(
          value: hasLength ? value / max : 0,
          minHeight: 3,
        ),
      );
    }

    final waveform = data.waveform;
    final progress = hasLength ? value / max : 0.0;
    return Column(
      children: [
        Stack(
          children: [
            // A waveform only exists for a local track once WaveformStore
            // has finished extracting/loading it — every other case
            // (streaming track, unsupported platform, still computing)
            // falls back to the plain Slider rather than distinguishing
            // why.
            if (waveform != null)
              WaveformSeekBar(
                waveform: waveform,
                position: data.position,
                duration: total,
                onSeek: data.onSeek,
                onSeekEnd: () => OmnisHaptics.selectionClick(),
              )
            else
              Slider(
                value: value,
                max: max,
                onChanged: (v) =>
                    data.onSeek(Duration(milliseconds: v.round())),
                onChangeEnd: (_) => OmnisHaptics.selectionClick(),
              ),
            // Overlaid, not stretched across the bar's history — live
            // capture only ever has a reading for the current instant, so
            // this pins a small live spectrum cluster to the playhead
            // rather than pretending to visualize the whole track.
            // IgnorePointer so it never steals the seek gesture from the
            // widget underneath.
            if (data.visualizerPlugin != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: SeekPositionVisualizer(
                    provider: data.visualizerPlugin,
                    progress: progress,
                  ),
                ),
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(data.formatDuration(data.position)),
              Text(data.formatDuration(total)),
            ],
          ),
        ),
      ],
    );
  }
}

class PlayerControlsRow extends StatefulWidget {
  final PlayerLayoutData data;
  final double iconSize;
  final double playIconSize;
  final Color? color;

  const PlayerControlsRow({
    super.key,
    required this.data,
    this.iconSize = 40,
    this.playIconSize = 56,
    this.color,
  });

  @override
  State<PlayerControlsRow> createState() => _PlayerControlsRowState();
}

class _PlayerControlsRowState extends State<PlayerControlsRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _playPauseController;

  @override
  void initState() {
    super.initState();
    _playPauseController = AnimationController(
      vsync: this,
      duration: OmnisMotion.fast,
      value: widget.data.playing ? 1 : 0,
    );
  }

  @override
  void didUpdateWidget(PlayerControlsRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.data.playing == oldWidget.data.playing) return;
    // Duration is read fresh on every transition (not fixed at
    // construction) so a mid-session change to "reduce motion" takes
    // effect on the very next tap, not just after a widget rebuild.
    _playPauseController.duration = OmnisMotion.durationFor(OmnisMotion.fast);
    if (widget.data.playing) {
      _playPauseController.forward();
    } else {
      _playPauseController.reverse();
    }
  }

  @override
  void dispose() {
    _playPauseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final iconSize = widget.iconSize;
    final playIconSize = widget.playIconSize;
    final color = widget.color;
    final theme = Theme.of(context);
    final layout = data.settings.buttonLayout;
    final compact = layout != ButtonLayout.standard;
    final activeColor = color ?? theme.colorScheme.primary;
    final inactiveColor =
        (color ?? theme.colorScheme.onSurface).withValues(alpha: 0.6);

    Widget iconButton(IconData icon,
        {required VoidCallback onPressed,
        required double size,
        required String tooltip,
        Color? iconColor}) {
      return IconButton(
        iconSize: size,
        icon: Icon(icon, color: iconColor ?? color),
        tooltip: tooltip,
        onPressed: onPressed,
      );
    }

    final shuffleRepeatSize = compact ? iconSize * 0.55 : iconSize * 0.65;
    final playSize = compact ? playIconSize * 0.8 : playIconSize;
    final seekIncrement = data.settings.seekIncrementSeconds;
    final seekIcons = switch (seekIncrement) {
      15 => (
          OmnisIconCatalog.replay10.resolve(),
          OmnisIconCatalog.forward10.resolve()
        ), // no dedicated 15s glyph
      30 => (
          OmnisIconCatalog.replay30.resolve(),
          OmnisIconCatalog.forward30.resolve()
        ),
      _ => (
          OmnisIconCatalog.replay10.resolve(),
          OmnisIconCatalog.forward10.resolve()
        ),
    };
    void skip(int deltaSeconds) {
      final current = data.position;
      var target = current + Duration(seconds: deltaSeconds);
      if (target < Duration.zero) target = Duration.zero;
      final total = data.duration;
      if (total != null && target > total) target = total;
      data.onSeek(target);
      OmnisHaptics.selectionClick();
    }

    // Single combined play-mode icon, replacing separate shuffle and
    // repeat toggles: off -> repeat all -> repeat one -> shuffle -> off
    // (see `ShuffleRepeatPlugin.cyclePlayMode`). Shuffle takes priority in
    // the glyph choice since the two states are mutually exclusive by the
    // time this renders.
    final playModeIcon = data.shuffleEnabled
        ? OmnisIconCatalog.shuffle.resolve()
        : data.repeatMode == RepeatMode.one
            ? OmnisIconCatalog.repeatOne.resolve()
            : OmnisIconCatalog.repeat.resolve();
    final playModeActive =
        data.shuffleEnabled || data.repeatMode != RepeatMode.off;
    final playModeTooltip = data.shuffleEnabled
        ? 'Shuffle'
        : switch (data.repeatMode) {
            RepeatMode.all => 'Repeat all',
            RepeatMode.one => 'Repeat one',
            RepeatMode.off => 'Sequential',
          };

    // Wrapped in FittedBox(scaleDown) rather than left as a bare Row:
    // the Standard layout's full button set (play-mode/prev/seek-back/
    // play-pause/seek-forward/next, each with its own fixed IconButton
    // tap-target minimum plus the fixed gaps below) has a real,
    // documented overflow of a few pixels on a real phone's ~360dp
    // width — item 47's TV-mode verification found this and explicitly
    // left it unfixed as out of scope at the time. `scaleDown` is a
    // no-op whenever the row already fits (every wider screen, and
    // every existing widget test here, which all render at the
    // default 800px test viewport), and shrinks the whole row
    // uniformly by the few percent needed on a genuinely narrow
    // screen instead of clipping/overflowing by a few pixels — simpler
    // than hand-computing per-button proportional widths the way
    // `TvModeLayout`'s own three-button row does, since this row can
    // have anywhere from 3 to 6 buttons across three `ButtonLayout`
    // variants and doesn't need TV mode's "Play/Pause deliberately
    // much larger than its neighbors" width budgeting.
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (layout == ButtonLayout.standard)
            iconButton(playModeIcon,
                onPressed: data.onCyclePlayMode,
                size: shuffleRepeatSize,
                tooltip: playModeTooltip,
                iconColor: playModeActive ? activeColor : inactiveColor),
          if (layout != ButtonLayout.minimal)
            iconButton(OmnisIconCatalog.skipPrevious.resolve(),
                onPressed: data.onPrevious,
                size: compact ? iconSize * 0.8 : iconSize,
                tooltip: 'Previous'),
          if (layout == ButtonLayout.standard) ...[
            iconButton(seekIcons.$1,
                onPressed: () => skip(-seekIncrement),
                size: shuffleRepeatSize,
                tooltip: 'Back $seekIncrement seconds'),
            const SizedBox(width: 4),
          ],
          const SizedBox(width: 16),
          data.buffering
              ? Semantics(
                  label: 'Buffering',
                  child: SizedBox(
                    width: playIconSize - 8,
                    height: playIconSize - 8,
                    child: CircularProgressIndicator(color: color),
                  ),
                )
              // `AnimatedIcon` morphs the glyph itself (play triangle <->
              // pause bars) instead of the old hard swap between two
              // separate `Icons.*_circle_filled` icons.
              : IconButton(
                  iconSize: playSize,
                  icon: AnimatedIcon(
                    icon: AnimatedIcons.play_pause,
                    progress: _playPauseController,
                    size: playSize,
                    color: color ?? theme.colorScheme.onSurface,
                  ),
                  tooltip: data.playing ? 'Pause' : 'Play',
                  onPressed: data.onPlayPause,
                ),
          const SizedBox(width: 16),
          if (layout == ButtonLayout.standard) ...[
            const SizedBox(width: 4),
            iconButton(seekIcons.$2,
                onPressed: () => skip(seekIncrement),
                size: shuffleRepeatSize,
                tooltip: 'Forward $seekIncrement seconds'),
          ],
          if (layout != ButtonLayout.minimal)
            iconButton(OmnisIconCatalog.skipNext.resolve(),
                onPressed: data.onNext,
                size: compact ? iconSize * 0.8 : iconSize,
                tooltip: 'Next'),
        ],
      ),
    );
  }
}

/// Shows the current track's lyrics. When the registered provider has
/// synced (time-stamped) lyrics for this track, every line renders at
/// once in a [SyncedLyricsView] — Spotify-style — with the active line
/// highlighted and kept scrolled into view. Otherwise this falls back to
/// `LyricsPlugin.currentLyricFor`'s existing behavior: the *whole* stored
/// lyric block for a plain (untimed) lyric, not one line at a time — a
/// full song's lyrics can easily be taller than the screen, so the text
/// scrolls internally on its own rather than pushing the rest of Now
/// Playing off-screen or clipping silently. This is the one part of Now
/// Playing that's meant to scroll; everything around it stays fixed (see
/// [StandardLayout]).
class PlayerLyricsPanel extends StatelessWidget {
  final PlayerLayoutData data;
  final Color? color;
  final FontWeight? fontWeight;

  const PlayerLyricsPanel({
    super.key,
    required this.data,
    this.color,
    this.fontWeight,
  });

  /// Maps [LyricsTextSize] to an existing `Theme.textTheme` style rather
  /// than a raw font-size multiplier, so lyrics stay visually consistent
  /// with the rest of the screen at every step.
  static TextStyle? _sizeStyle(ThemeData theme, LyricsTextSize size) {
    final textTheme = theme.textTheme;
    return switch (size) {
      LyricsTextSize.small => textTheme.bodySmall,
      LyricsTextSize.medium => textTheme.bodyMedium,
      LyricsTextSize.large => textTheme.titleMedium,
      LyricsTextSize.extraLarge => textTheme.headlineSmall,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plugin = data.lyricsPlugin;
    final baseStyle =
        _sizeStyle(theme, data.settings.lyricsTextSize) ?? theme.textTheme.bodyMedium;
    final effectiveStyle =
        baseStyle?.copyWith(color: color, fontWeight: fontWeight);
    // `ISyncedLyricsProvider` is a separate, optional capability a
    // registered `ILyricsProvider` may or may not also implement — see
    // that interface's own doc for why it isn't just a method on
    // `ILyricsProvider` itself. `null` (not just empty) is its explicit
    // "nothing synced for this track" signal. Only a non-null, non-empty
    // list switches this panel into the scrolling-list rendering;
    // anything else falls back to today's single-block text exactly as
    // before.
    List<LyricLine>? syncedLines;
    if (plugin is ISyncedLyricsProvider) {
      syncedLines = (plugin as ISyncedLyricsProvider).syncedLyricsFor(data.track);
    }

    final Widget body;
    if (syncedLines != null && syncedLines.isNotEmpty) {
      final activeColor = color ?? theme.colorScheme.primary;
      final inactiveColor = (color ?? theme.colorScheme.onSurface)
          .withValues(alpha: 0.55);
      body = SyncedLyricsView(
        lines: syncedLines,
        position: data.position,
        activeStyle: effectiveStyle?.copyWith(
          color: activeColor,
          fontWeight: FontWeight.bold,
        ),
        inactiveStyle: effectiveStyle?.copyWith(color: inactiveColor),
      );
    } else {
      final text = plugin == null
          ? 'The Lyrics plugin is disabled — enable it in Settings.'
          : (data.lyricText ?? 'No lyrics added for this track yet.');
      body = SingleChildScrollView(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: effectiveStyle,
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(12),
            ),
            child: body,
          ),
        ),
        if (plugin != null)
          IconButton(
            tooltip: 'Edit lyrics',
            icon: const Icon(Icons.edit_note),
            onPressed: data.onEditLyrics,
          ),
      ],
    );
  }
}

/// The synced-lyric line active at [position], mirroring
/// `LyricsPlugin.currentLyricFor`'s own comparison *exactly* (in the
/// `Omnis-Plugins` repo's `lyrics_plugin.dart`) so the scrolling list and
/// any single-line block computed the same way never disagree: the last
/// line whose timestamp is at or before [position], or `null` when
/// nothing has started yet (a position before the first synced line's own
/// timestamp — an intro before the lyrics begin must not highlight that
/// first line early).
int? activeLyricLineIndex(List<LyricLine> lines, Duration position) {
  if (lines.isEmpty) return null;
  if (position < lines.first.timestamp) return null;
  final index = lines.lastIndexWhere((line) => line.timestamp <= position);
  // Unreachable given the guard above (mirrors `currentLyricFor`'s own
  // defensive `orElse` for the same reason), but kept rather than assuming
  // `lastIndexWhere` can never return -1 here.
  return index >= 0 ? index : 0;
}

/// Renders one synced lyric line: word-by-word highlighted up to
/// [position] when [line.wordTimings] is populated (lrclib.net's
/// "enhanced" per-word LRC — see `LyricLine.wordTimings`'s own doc for
/// why this is usually `null` today), or as one plain styled block
/// otherwise. Deliberately never interpolates word timing when
/// [LyricLine.wordTimings] is `null` — an evenly-spaced guess reads as a
/// bug, not a feature, so an inactive or timing-less line always falls
/// back to whole-line styling.
class LyricLineText extends StatelessWidget {
  final LyricLine line;
  final Duration position;
  final bool active;
  final TextStyle? activeStyle;
  final TextStyle? inactiveStyle;
  final TextAlign textAlign;

  const LyricLineText({
    super.key,
    required this.line,
    required this.position,
    required this.active,
    this.activeStyle,
    this.inactiveStyle,
    this.textAlign = TextAlign.center,
  });

  @override
  Widget build(BuildContext context) {
    final wordTimings = line.wordTimings;
    if (active && wordTimings != null && wordTimings.isNotEmpty) {
      final sungStyle = activeStyle?.copyWith(
        decoration: TextDecoration.underline,
        decorationColor: activeStyle?.color,
      );
      final upcomingStyle = (activeStyle ?? inactiveStyle)?.copyWith(
        color: (activeStyle ?? inactiveStyle)
            ?.color
            ?.withValues(alpha: 0.5),
      );
      return Text.rich(
        TextSpan(children: [
          for (var i = 0; i < wordTimings.length; i++)
            TextSpan(
              text: i == wordTimings.length - 1
                  ? wordTimings[i].$2
                  : '${wordTimings[i].$2} ',
              style: wordTimings[i].$1 <= position ? sungStyle : upcomingStyle,
            ),
        ]),
        textAlign: textAlign,
      );
    }
    return Text(
      line.text,
      textAlign: textAlign,
      style: active ? activeStyle : inactiveStyle,
    );
  }
}

/// Spotify-style scrolling view of every synced lyric line in [lines],
/// the line active at [position] highlighted via [activeStyle] and kept
/// vertically centered in the viewport as [position] advances — an
/// animated [ScrollController.animateTo] on every change, never a hard
/// jump. Shared by [PlayerLyricsPanel] (compact) and
/// `KaraokeGesturesLayout` (large, lyrics-as-primary-content) so the
/// scroll/highlight math lives in exactly one place.
class SyncedLyricsView extends StatefulWidget {
  final List<LyricLine> lines;
  final Duration position;
  final TextStyle? activeStyle;
  final TextStyle? inactiveStyle;
  final TextAlign textAlign;
  final EdgeInsetsGeometry padding;

  /// Fixed per-line height. A fixed `itemExtent` (rather than measuring
  /// each line's real, variable wrapped height) is what makes "the target
  /// scroll offset for a given active index" a direct, cheap computation
  /// instead of needing a layout pass's results — worth the trade of
  /// long lines not getting extra vertical room.
  final double lineExtent;

  const SyncedLyricsView({
    super.key,
    required this.lines,
    required this.position,
    this.activeStyle,
    this.inactiveStyle,
    this.textAlign = TextAlign.center,
    this.padding = EdgeInsets.zero,
    this.lineExtent = 44,
  });

  @override
  State<SyncedLyricsView> createState() => _SyncedLyricsViewState();
}

class _SyncedLyricsViewState extends State<SyncedLyricsView> {
  final _controller = ScrollController();
  int? _lastScrolledIndex;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeScrollToActive());
  }

  @override
  void didUpdateWidget(covariant SyncedLyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A genuinely different line list (new track, or lyrics that just
    // finished fetching) must re-scroll even if the newly computed active
    // index happens to numerically match the last one scrolled to for the
    // old list.
    if (!identical(oldWidget.lines, widget.lines)) _lastScrolledIndex = null;
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeScrollToActive());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _maybeScrollToActive() {
    if (!mounted || !_controller.hasClients) return;
    final active = activeLyricLineIndex(widget.lines, widget.position);
    if (active == null || active == _lastScrolledIndex) return;
    _lastScrolledIndex = active;

    final viewport = _controller.position.viewportDimension;
    final target = (active * widget.lineExtent) -
        (viewport / 2) +
        (widget.lineExtent / 2);
    final clamped =
        target.clamp(0.0, _controller.position.maxScrollExtent);
    _controller.animateTo(
      clamped,
      duration: OmnisMotion.durationFor(OmnisMotion.medium),
      curve: OmnisMotion.standardCurve,
    );
  }

  @override
  Widget build(BuildContext context) {
    final active = activeLyricLineIndex(widget.lines, widget.position);
    return ListView.builder(
      controller: _controller,
      padding: widget.padding,
      itemExtent: widget.lineExtent,
      itemCount: widget.lines.length,
      itemBuilder: (context, index) {
        final line = widget.lines[index];
        final isActive = index == active;
        return Center(
          child: LyricLineText(
            line: line,
            position: widget.position,
            active: isActive,
            activeStyle: widget.activeStyle,
            inactiveStyle: widget.inactiveStyle,
            textAlign: widget.textAlign,
          ),
        );
      },
    );
  }
}

class PlayerExtrasRow extends StatelessWidget {
  final PlayerLayoutData data;

  const PlayerExtrasRow({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final equalizer = data.equalizerPlugin;
    final visualizer = data.visualizerPlugin;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        PlayerAbRepeatButton(data: data),
        if (equalizer != null || visualizer != null) const SizedBox(width: 8),
        if (equalizer != null)
          FilledButton.tonal(
              onPressed: data.onOpenEqualizer, child: const Text('Equalizer')),
        if (equalizer != null && visualizer != null) const SizedBox(width: 8),
        if (visualizer != null)
          OutlinedButton(
              onPressed: data.onActivateVisualizer,
              child: const Text('Visualizer')),
      ],
    );
  }
}

/// A-B repeat toggle: a 3-state cycle (off -> A marked -> looping A-B -> off)
/// driven entirely by AudioEngine's own loop-point state -- this widget
/// just reflects it. A common practicing/DJ feature (Poweramp, Musicolet,
/// most desktop players) just_audio has no built-in concept of. Long-press
/// opens the saved/named loops sheet (`data.onLongPressAbRepeat`) --
/// MusicBee comparison §27 / spec §19's "saved loops" gap, since the
/// underlying `AbRepeatController` only ever holds one loop in memory.
class PlayerAbRepeatButton extends StatelessWidget {
  final PlayerLayoutData data;

  const PlayerAbRepeatButton({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final looping = data.abRepeatRange != null;
    final aMarked = data.loopAMarker != null;

    final (icon, label) = looping
        ? (Icons.loop, 'A-B looping')
        : aMarked
            ? (Icons.bookmark_added_outlined, 'Set point B')
            : (Icons.repeat, 'A-B repeat');

    return GestureDetector(
      onLongPress: data.onLongPressAbRepeat,
      child: OutlinedButton.icon(
        onPressed: data.onCycleAbRepeat,
        icon: Icon(icon,
            color: (looping || aMarked) ? theme.colorScheme.primary : null),
        label: Text(label,
            style: (looping || aMarked)
                ? TextStyle(color: theme.colorScheme.primary)
                : null),
        style: (looping || aMarked)
            ? OutlinedButton.styleFrom(
                side: BorderSide(color: theme.colorScheme.primary, width: 1.5))
            : null,
      ),
    );
  }
}

/// Compact sleep-timer control: a single icon (badged with the remaining
/// time when a timer is running) that opens a dropdown menu instead of the
/// old always-visible two-button row + status line, which took up a full
/// row of Now Playing even when no timer was active.
class PlayerSleepTimerRow extends StatelessWidget {
  final PlayerLayoutData data;

  const PlayerSleepTimerRow({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final timer = data.sleepTimerPlugin;
    if (timer == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final active = timer.isActive;
    final icon = Icon(
      active ? Icons.bedtime : Icons.bedtime_outlined,
      color: active ? theme.colorScheme.primary : null,
    );

    return PopupMenuButton<_SleepTimerAction>(
      tooltip: active
          ? 'Sleep timer — pausing in '
              '${data.formatDuration(timer.remaining ?? Duration.zero)}'
          : 'Sleep timer',
      icon: active
          ? Badge(
              label: Text(
                data.formatDuration(timer.remaining ?? Duration.zero),
              ),
              alignment: Alignment.bottomRight,
              offset: const Offset(4, 4),
              child: icon,
            )
          : icon,
      onSelected: (action) {
        switch (action) {
          case _SleepTimerAction.startOrChange:
            OmnisHaptics.mediumImpact();
            data.onStartSleepTimer();
          case _SleepTimerAction.cancel:
            data.onCancelSleepTimer?.call();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: _SleepTimerAction.startOrChange,
          child: Text(active ? 'Change duration' : 'Start sleep timer'),
        ),
        if (active)
          const PopupMenuItem(
            value: _SleepTimerAction.cancel,
            child: Text('Cancel timer'),
          ),
      ],
    );
  }
}

enum _SleepTimerAction { startOrChange, cancel }

class PlayerCrossfadeStatus extends StatelessWidget {
  final PlayerLayoutData data;

  const PlayerCrossfadeStatus({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final text = data.crossfadeStatusText;
    if (text == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(text, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}
