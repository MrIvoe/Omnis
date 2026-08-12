import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:omnis/core/audio_engine.dart';
import 'package:omnis/ui/now_playing_page.dart';
import 'package:omnis/ui/theme/omnis_motion.dart';
import 'package:omnis/ui/widgets/track_artwork.dart';

/// Persistent bar shown above the bottom nav whenever a track is loaded.
/// Tapping it pushes the full [NowPlayingPage] with a real `Hero`
/// transition on the album art (tag `'now_playing_art'`, matching
/// `PlayerAlbumArt`'s own — see that widget's doc comment).
///
/// Replaces "Now Playing" as a bottom-nav tab: a `Hero` needs two routes
/// to animate between, which the old same-route `IndexedStack` tab swap
/// never had — see `home_page.dart`'s doc comment for the full reasoning.
class MiniPlayerBar extends StatefulWidget {
  final AudioEngine engine;

  const MiniPlayerBar({super.key, required this.engine});

  @override
  State<MiniPlayerBar> createState() => _MiniPlayerBarState();
}

class _MiniPlayerBarState extends State<MiniPlayerBar> {
  StreamSubscription<dynamic>? _trackSub;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;

  bool _playing = false;
  Duration _position = Duration.zero;
  Duration? _duration;

  @override
  void initState() {
    super.initState();
    _trackSub = widget.engine.trackStream.listen((_) {
      if (mounted) setState(() {});
    });
    _stateSub = widget.engine.playerStateStream.listen((state) {
      if (mounted) setState(() => _playing = state.playing);
    });
    _positionSub = widget.engine.positionStream.listen((pos) {
      if (mounted) setState(() => _position = pos);
    });
    _durationSub = widget.engine.durationStream.listen((dur) {
      if (mounted) setState(() => _duration = dur);
    });
  }

  @override
  void dispose() {
    _trackSub?.cancel();
    _stateSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    super.dispose();
  }

  /// A plain `MaterialPageRoute` normally — its default transition (and
  /// the `now_playing_art` Hero flight riding along with it, since a
  /// Hero's flight duration is driven by the enclosing route's own
  /// transition) is left untouched. Only when reduce motion is on does
  /// this swap to a zero-duration route instead: [OmnisMotion.durationFor]
  /// returning [Duration.zero] is this app's established "jump straight
  /// to the end state" signal for every other animation, and a Hero
  /// flight follows the same rule — a zero-duration transition makes the
  /// shared-element animation resolve instantly rather than at 1/10th
  /// speed the way just shortening it would.
  Route<void> _nowPlayingRoute() {
    final duration = OmnisMotion.durationFor(OmnisMotion.medium);
    if (duration == Duration.zero) {
      return PageRouteBuilder<void>(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (context, animation, secondaryAnimation) =>
            const NowPlayingPage(),
      );
    }
    return MaterialPageRoute<void>(builder: (_) => const NowPlayingPage());
  }

  @override
  Widget build(BuildContext context) {
    final track = widget.engine.currentTrack;
    // Nothing loaded yet (fresh install, or nothing has ever played this
    // session) — no bar, rather than an empty player shell.
    if (track == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final duration = _duration;
    final progress = (duration != null && duration > Duration.zero)
        ? (_position.inMilliseconds / duration.inMilliseconds)
            .clamp(0.0, 1.0)
        : 0.0;

    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      child: InkWell(
        onTap: () => Navigator.of(context).push(_nowPlayingRoute()),
        child: Semantics(
          hint: 'Double tap to open Now Playing.',
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 56,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    ExcludeSemantics(
                      child: Hero(
                        tag: 'now_playing_art',
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: TrackArtwork(
                            track: track,
                            width: 40,
                            height: 40,
                            iconSize: 18,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            track.artists.join(', '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                      tooltip: _playing ? 'Pause' : 'Play',
                      onPressed: () =>
                          _playing ? widget.engine.pause() : widget.engine.play(),
                    ),
                  ],
                ),
              ),
            ),
            LinearProgressIndicator(
              value: progress,
              minHeight: 2,
              backgroundColor: Colors.transparent,
            ),
          ],
          ),
        ),
      ),
    );
  }
}
