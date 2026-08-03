import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:just_audio/just_audio.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/core/audio_engine.dart';
import 'package:omnis/core/equalizer_plugin.dart';
import 'package:omnis/core/lyrics_plugin.dart';
import 'package:omnis/core/main_core.dart';
import 'package:omnis/core/sleep_timer_plugin.dart';
import 'package:omnis/core/visualizer_plugin.dart';

/// Global GetIt instance (same singleton used in main.dart).
GetIt get locator => GetIt.instance;

/// Now Playing screen — bound directly to [AudioEngine] streams.
class NowPlayingPage extends StatefulWidget {
  const NowPlayingPage({super.key});

  @override
  State<NowPlayingPage> createState() => _NowPlayingPageState();
}

class _NowPlayingPageState extends State<NowPlayingPage> {
  AudioEngine get engine => locator<AudioEngine>();

  StreamSubscription? _trackSub;
  StreamSubscription? _stateSub;
  bool _playing = false;
  bool _buffering = false;
  Duration _position = Duration.zero;
  Duration? _duration;
  late AppSettings _settings;
  final LyricsPlugin _lyricsPlugin = LyricsPlugin();
  final EqualizerPlugin _equalizerPlugin = EqualizerPlugin();
  final VisualizerPlugin _visualizerPlugin = VisualizerPlugin();
  final SleepTimerPlugin _sleepTimer = SleepTimerPlugin(onPause: () async {
    final core = locator<MainCore>();
    await core.audioEngine.pause();
  });

  @override
  void initState() {
    super.initState();
    _settings = AppSettings.instance;
    _settings.addListener(_refresh);
    _trackSub = engine.trackStream.listen((_) {
      if (mounted) setState(() {});
    });
    _stateSub = engine.playerStateStream.listen((state) {
      if (!mounted) return;
      setState(() {
        _playing = state.playing;
        _buffering = state.processingState == ProcessingState.loading;
      });
    });
    engine.positionStream.listen((pos) {
      if (mounted) setState(() => _position = pos);
    });
    engine.durationStream.listen((dur) {
      if (mounted) setState(() => _duration = dur);
    });
  }

  @override
  void dispose() {
    _settings.removeListener(_refresh);
    _trackSub?.cancel();
    _stateSub?.cancel();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${d.inMinutes}:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final track = engine.currentTrack;
    final theme = Theme.of(context);
    final settings = _settings;
    final buttonLayout = settings.buttonLayout;
    final showLyrics = settings.showLyrics;
    final karaokeMode = settings.karaokeMode;
    final showAlbumArt = settings.showAlbumArt;
    final scale = settings.albumArtScale;
    final lyricText = showLyrics && track != null
        ? _lyricsPlugin.currentLyricFor(track, _position)
        : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Now Playing')),
      body: Center(
        child: track == null
            ? const Text('Nothing playing — pick a track from the Library.')
            : GestureDetector(
                onHorizontalDragEnd: settings.allowSwipeGestures &&
                        settings.gestureMode == GestureMode.swipe
                    ? (details) {
                        if (details.primaryVelocity == null) return;
                        if (details.primaryVelocity! < -200) {
                          engine.next();
                        } else if (details.primaryVelocity! > 200) {
                          engine.previous();
                        }
                      }
                    : null,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (showAlbumArt)
                        Transform.scale(
                          scale: scale,
                          child: Container(
                            width: 220,
                            height: 220,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color: theme.colorScheme.shadow
                                      .withOpacity(0.15),
                                  blurRadius: 16,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Center(
                              child: Icon(Icons.album,
                                  size: 96,
                                  color: theme.colorScheme.onPrimaryContainer),
                            ),
                          ),
                        )
                      else
                        Icon(Icons.music_note,
                            size: 72, color: theme.colorScheme.primary),
                      const SizedBox(height: 24),
                      Text(track.title,
                          style: theme.textTheme.headlineSmall,
                          textAlign: TextAlign.center),
                      const SizedBox(height: 8),
                      Text(track.artists.join(', '),
                          style: theme.textTheme.bodyLarge),
                      const SizedBox(height: 16),
                      if (showLyrics)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest
                                .withOpacity(0.35),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            karaokeMode
                                ? '♪ ${track.title} ♪'
                                : (lyricText ??
                                    'Lyrics mode is on — karaoke visuals will appear here.'),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      const SizedBox(height: 24),
                      if (showLyrics)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: VisualizerBars(plugin: _visualizerPlugin),
                        ),
                      Slider(
                        value: (_duration ?? Duration.zero).inMilliseconds > 0
                            ? _position.inMilliseconds
                                .clamp(0, _duration!.inMilliseconds)
                                .toDouble()
                            : 0,
                        max: (_duration ?? Duration.zero).inMilliseconds > 0
                            ? _duration!.inMilliseconds.toDouble()
                            : 1,
                        onChanged: (v) =>
                            engine.seek(Duration(milliseconds: v.round())),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(_fmt(_position)),
                          Text(_fmt(_duration ?? Duration.zero)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          FilledButton.tonal(
                            onPressed: () {
                              _equalizerPlugin.setBand('bass', 6.0);
                              _equalizerPlugin.setBand('mid', 2.0);
                              _equalizerPlugin.setBand('treble', -2.0);
                              _visualizerPlugin.emitLevels(
                                  [0.2, 0.5, 0.8, 0.3, 0.7, 0.4, 0.6, 0.2]);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Equalizer preset applied.')),
                              );
                            },
                            child: const Text('EQ preset'),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: () {
                              _visualizerPlugin.emitLevels(
                                  [0.2, 0.5, 0.7, 0.3, 0.8, 0.4, 0.6, 0.3]);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Visualizer activated.')),
                              );
                            },
                            child: const Text('Visualizer'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildControlRow(buttonLayout),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          FilledButton.tonal(
                            onPressed: () {
                              _sleepTimer
                                  .startTimer(const Duration(minutes: 15));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        'Sleep timer started for 15 minutes.')),
                              );
                            },
                            child: const Text('Sleep in 15m'),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: () {
                              _sleepTimer.stopTimer();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Sleep timer cancelled.')),
                              );
                            },
                            child: const Text('Cancel'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildControlRow(ButtonLayout layout) {
    final compact = layout != ButtonLayout.standard;
    final showLarge = layout == ButtonLayout.standard;

    Widget buildButton(IconData icon,
        {required VoidCallback onPressed, double size = 40}) {
      return IconButton(
        iconSize: size,
        icon: Icon(icon),
        onPressed: onPressed,
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (layout != ButtonLayout.minimal)
          buildButton(Icons.skip_previous,
              onPressed: () => engine.previous(), size: compact ? 32 : 40),
        const SizedBox(width: 16),
        _buffering
            ? const SizedBox(
                width: 48, height: 48, child: CircularProgressIndicator())
            : buildButton(
                _playing ? Icons.pause_circle_filled : Icons.play_circle_fill,
                onPressed: () => _playing ? engine.pause() : engine.play(),
                size: showLarge ? 56 : 44,
              ),
        const SizedBox(width: 16),
        if (layout != ButtonLayout.minimal)
          buildButton(Icons.skip_next,
              onPressed: () => engine.next(), size: compact ? 32 : 40),
      ],
    );
  }
}
