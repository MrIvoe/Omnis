import 'package:flutter/material.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/ui/player_layouts/player_layout.dart';
import 'package:omnis/ui/theme/omnis_motion.dart';
import 'package:omnis/ui/widgets/track_artwork.dart';

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
        ? data.position.inMilliseconds
            .clamp(0, total.inMilliseconds)
            .toDouble()
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

    return Column(
      children: [
        Slider(
          value: value,
          max: max,
          onChanged: (v) => data.onSeek(Duration(milliseconds: v.round())),
          onChangeEnd: (_) => OmnisHaptics.selectionClick(),
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
    final inactiveColor = (color ?? theme.colorScheme.onSurface)
        .withValues(alpha: 0.6);

    Widget iconButton(IconData icon,
        {required VoidCallback onPressed,
        required double size,
        Color? iconColor}) {
      return IconButton(
        iconSize: size,
        icon: Icon(icon, color: iconColor ?? color),
        onPressed: onPressed,
      );
    }

    final shuffleRepeatSize = compact ? iconSize * 0.55 : iconSize * 0.65;
    final playSize = compact ? playIconSize * 0.8 : playIconSize;
    final seekIncrement = data.settings.seekIncrementSeconds;
    final seekIcons = switch (seekIncrement) {
      15 => (Icons.replay_10, Icons.forward_10), // no dedicated 15s glyph
      30 => (Icons.replay_30, Icons.forward_30),
      _ => (Icons.replay_10, Icons.forward_10),
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

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (layout == ButtonLayout.standard)
          iconButton(Icons.shuffle,
              onPressed: data.onToggleShuffle,
              size: shuffleRepeatSize,
              iconColor: data.shuffleEnabled ? activeColor : inactiveColor),
        if (layout != ButtonLayout.minimal)
          iconButton(Icons.skip_previous,
              onPressed: data.onPrevious,
              size: compact ? iconSize * 0.8 : iconSize),
        if (layout == ButtonLayout.standard) ...[
          iconButton(seekIcons.$1,
              onPressed: () => skip(-seekIncrement),
              size: shuffleRepeatSize),
          const SizedBox(width: 4),
        ],
        const SizedBox(width: 16),
        data.buffering
            ? SizedBox(
                width: playIconSize - 8,
                height: playIconSize - 8,
                child: CircularProgressIndicator(color: color),
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
                onPressed: data.onPlayPause,
              ),
        const SizedBox(width: 16),
        if (layout == ButtonLayout.standard) ...[
          const SizedBox(width: 4),
          iconButton(seekIcons.$2,
              onPressed: () => skip(seekIncrement),
              size: shuffleRepeatSize),
        ],
        if (layout != ButtonLayout.minimal)
          iconButton(Icons.skip_next,
              onPressed: data.onNext,
              size: compact ? iconSize * 0.8 : iconSize),
        if (layout == ButtonLayout.standard)
          iconButton(
              data.repeatMode == RepeatMode.one
                  ? Icons.repeat_one
                  : Icons.repeat,
              onPressed: data.onCycleRepeat,
              size: shuffleRepeatSize,
              iconColor:
                  data.repeatMode != RepeatMode.off ? activeColor : inactiveColor),
      ],
    );
  }
}

/// Shows the current track's lyrics. `LyricsPlugin.currentLyricFor` returns
/// the *whole* stored lyric block for a plain (untimed) lyric, not one
/// line at a time — a full song's lyrics can easily be taller than the
/// screen, so the text scrolls internally on its own rather than pushing
/// the rest of Now Playing off-screen or clipping silently. This is the
/// one part of Now Playing that's meant to scroll; everything around it
/// stays fixed (see [StandardLayout]).
class PlayerLyricsPanel extends StatelessWidget {
  final PlayerLayoutData data;
  final TextStyle? style;

  const PlayerLyricsPanel({super.key, required this.data, this.style});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plugin = data.lyricsPlugin;
    final text = plugin == null
        ? 'The Lyrics plugin is disabled — enable it in Settings.'
        : (data.lyricText ?? 'No lyrics added for this track yet.');
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
            child: SingleChildScrollView(
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: style ?? theme.textTheme.bodyMedium,
              ),
            ),
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
/// most desktop players) just_audio has no built-in concept of.
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

    return OutlinedButton.icon(
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
    );
  }
}

class PlayerSleepTimerRow extends StatelessWidget {
  final PlayerLayoutData data;

  const PlayerSleepTimerRow({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final timer = data.sleepTimerPlugin;
    if (timer == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FilledButton.tonal(
                onPressed: () {
                  OmnisHaptics.mediumImpact();
                  data.onStartSleepTimer();
                },
                child: const Text('Sleep timer')),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: timer.isActive ? data.onCancelSleepTimer : null,
              child: const Text('Cancel'),
            ),
          ],
        ),
        if (timer.isActive)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Pausing in ${data.formatDuration(timer.remaining ?? Duration.zero)}',
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

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
