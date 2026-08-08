import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_waveform/just_waveform.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/core/audio_engine.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/bootstrap.dart';
import 'package:omnis/core/main_core.dart';
import 'package:omnis/core/plugin_manager.dart';
import 'package:omnis/core/waveform_store.dart';
import 'package:omnis/plugin_api/service_interfaces.dart';
import 'package:omnis_plugins/equalizer_plugin.dart';
import 'package:omnis_plugins/lyrics_plugin.dart';
import 'package:omnis_plugins/shuffle_repeat_plugin.dart';
import 'package:omnis_plugins/sleep_timer_plugin.dart';
import 'package:omnis_plugins/visualizer_plugin.dart';
import 'package:omnis/ui/player_layouts/layout_manager.dart';
import 'package:omnis/ui/player_layouts/player_layout.dart';
import 'package:omnis/ui/theme/omnis_colors.dart';
import 'package:omnis/ui/widgets/now_playing_background.dart';
import 'package:omnis/ui/widgets/track_artwork.dart' show ArtworkProvider;

/// Which way a "Taps" gesture-mode tap should skip.
enum TapZoneAction { previous, next }

/// Decides which way a tap-zone gesture should skip: right half → next,
/// left half → previous, `null` when the content hasn't been laid out yet
/// (width <= 0). A top-level function (not a method on the page's private
/// State class) so it's directly testable from `test/` without pumping the
/// whole page — previously "Taps" was declared as a gesture mode in
/// Settings but had no implementation at all; only swipe ever worked.
TapZoneAction? tapZoneAction(double dx, double width) {
  if (width <= 0) return null;
  return dx > width / 2 ? TapZoneAction.next : TapZoneAction.previous;
}

/// Now Playing screen.
///
/// This page is deliberately thin: it owns the audio-engine subscriptions
/// and plugin lookups, packages the result into a [PlayerLayoutData], and
/// hands rendering off entirely to whichever [PlayerLayout] is selected
/// (`AppSettings.playerLayoutId`, see `lib/ui/player_layouts/`). Adding a
/// new arrangement of the screen — moving buttons, going gesture-only,
/// whatever — means adding a layout, never touching this file.
class NowPlayingPage extends StatefulWidget {
  const NowPlayingPage({super.key});

  @override
  State<NowPlayingPage> createState() => _NowPlayingPageState();
}

class _NowPlayingPageState extends State<NowPlayingPage> {
  AudioEngine get engine => locator<AudioEngine>();
  PluginManager get _plugins => locator<MainCore>().pluginManager;
  LayoutManager get _layouts => locator<LayoutManager>();

  // Every plugin below resolves to the *registered* shared instance so a
  // disabled plugin (`onlyEnabled: true`) genuinely disappears from every
  // layout at once, rather than each layout needing its own lookup logic.
  //
  // Lyrics is looked up two ways: [_lyricsProvider] by interface, for the
  // display path (what a layout shows) — [_lyricsEditor] stays a concrete
  // lookup because editing is specific to this plugin's own storage
  // format, not part of the generic "read the current lyric" contract.
  ILyricsProvider? get _lyricsProvider =>
      _plugins.services.get<ILyricsProvider>();
  LyricsPlugin? get _lyricsEditor =>
      _plugins.bundled<LyricsPlugin>(onlyEnabled: true);
  EqualizerPlugin? get _equalizer =>
      _plugins.bundled<EqualizerPlugin>(onlyEnabled: true);
  // Same split as lyrics: [_visualizerProvider] by interface for the
  // display path — [_visualizerEmitter] stays a concrete lookup because
  // `emitLevels` (how *this* provider produces levels) isn't part of the
  // generic read-only interface.
  IVisualizerProvider? get _visualizerProvider =>
      _plugins.services.get<IVisualizerProvider>();
  VisualizerPlugin? get _visualizerEmitter =>
      _plugins.bundled<VisualizerPlugin>(onlyEnabled: true);
  SleepTimerPlugin? get _sleepTimer =>
      _plugins.bundled<SleepTimerPlugin>(onlyEnabled: true);
  ShuffleRepeatPlugin? get _shuffleRepeat =>
      _plugins.bundled<ShuffleRepeatPlugin>(onlyEnabled: true);

  StreamSubscription<dynamic>? _trackSub;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<List<ManagedPlugin>>? _pluginsSub;
  StreamSubscription<List<PlayerLayout>>? _layoutsSub;

  bool _playing = false;
  bool _buffering = false;
  Duration _position = Duration.zero;
  Duration? _duration;
  late AppSettings _settings;

  final WaveformStore _waveformStore = WaveformStore();
  Waveform? _waveform;
  String? _waveformTrackId;

  @override
  void initState() {
    super.initState();
    _settings = AppSettings.instance;
    _settings.addListener(_refresh);
    final initialTrack = engine.currentTrack;
    if (initialTrack != null) _loadWaveform(initialTrack);
    _trackSub = engine.trackStream.listen((track) {
      // Runs synchronously up to its first `await`, so `_waveform` is
      // already cleared for the new track by the time this setState
      // rebuilds — otherwise the old track's shape would flash briefly
      // before the fetch for the new one completes.
      if (track != null) _loadWaveform(track);
      if (mounted) setState(() {});
    });
    _stateSub = engine.playerStateStream.listen((state) {
      if (!mounted) return;
      setState(() {
        _playing = state.playing;
        _buffering = state.processingState == ProcessingState.loading ||
            state.processingState == ProcessingState.buffering;
      });
    });
    _positionSub = engine.positionStream.listen((pos) {
      if (mounted) setState(() => _position = pos);
    });
    _durationSub = engine.durationStream.listen((dur) {
      if (mounted) setState(() => _duration = dur);
    });
    // Enabling/disabling a plugin changes which controls a layout shows.
    _pluginsSub = _plugins.changes.listen((_) {
      if (mounted) setState(() {});
    });
    // Installing/uninstalling an imported layout should be reflected
    // immediately if it happens to be the one currently selected.
    _layoutsSub = _layouts.changes.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _settings.removeListener(_refresh);
    _trackSub?.cancel();
    _stateSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _pluginsSub?.cancel();
    _layoutsSub?.cancel();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  /// Fetches/computes peak data for [track] (see `WaveformStore`'s doc
  /// comment for every way this can legitimately resolve to `null` —
  /// streaming track, unsupported platform, still computing). Guards
  /// against a track change racing an in-flight fetch: if [track] is no
  /// longer the current one by the time this resolves, its result is
  /// discarded rather than clobbering whatever the newer track already
  /// loaded.
  Future<void> _loadWaveform(BaseTrack track) async {
    if (_waveformTrackId == track.id) return;
    _waveformTrackId = track.id;
    _waveform = null;
    final waveform = await _waveformStore.waveformFor(track);
    if (!mounted || _waveformTrackId != track.id) return;
    setState(() => _waveform = waveform);
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  /// Duration picker for the sleep timer. Previously this was hardcoded
  /// to a single fixed 15-minute button with no way to change it — the
  /// plugin itself (`SleepTimerPlugin.startTimer`) already accepts any
  /// `Duration`, only the UI never offered one.
  Future<void> _pickSleepTimerDuration(SleepTimerPlugin sleepTimer) async {
    const presets = [5, 10, 15, 30, 45, 60, 90];
    final chosen = await showDialog<int>(
      context: context,
      builder: (context) {
        // Pre-filled from this plugin's own settings (default duration),
        // so "the timer I always use" is one Enter away instead of
        // needing to find the matching chip every time.
        final controller =
            TextEditingController(text: '${sleepTimer.defaultMinutes}');
        return AlertDialog(
          title: const Text('Sleep timer'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final minutes in presets)
                    ActionChip(
                      label: Text('${minutes}m'),
                      onPressed: () => Navigator.pop(context, minutes),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Custom (minutes)',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (value) =>
                    Navigator.pop(context, int.tryParse(value)),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(context, int.tryParse(controller.text)),
              child: const Text('Start'),
            ),
          ],
        );
      },
    );
    if (chosen == null || chosen <= 0 || !mounted) return;
    sleepTimer.startTimer(Duration(minutes: chosen));
    setState(() {});
    _toast('Sleep timer started for $chosen minute${chosen == 1 ? '' : 's'}.');
  }

  /// Wraps [child] with the Settings → Gesture mode handler (swipe / taps /
  /// none). Layouts that define their own gestures
  /// ([PlayerLayout.definesOwnGestures]) skip this entirely — their
  /// gestures *are* the interaction model, not an addition on top of
  /// visible buttons the way this wrapper is for the other layouts.
  Widget _wrapWithGestureMode(Widget child, AppSettings settings) {
    if (!settings.allowSwipeGestures) return child;
    switch (settings.gestureMode) {
      case GestureMode.swipe:
        return GestureDetector(
          onHorizontalDragEnd: (details) {
            switch (swipeSkipActionFor(details.primaryVelocity)) {
              case SwipeSkipAction.next:
                engine.next();
              case SwipeSkipAction.previous:
                engine.previous();
              case null:
                break;
            }
          },
          child: child,
        );
      case GestureMode.taps:
        return GestureDetector(
          onTapUp: (details) {
            final width = context.size?.width ?? 0;
            switch (tapZoneAction(details.localPosition.dx, width)) {
              case TapZoneAction.next:
                engine.next();
              case TapZoneAction.previous:
                engine.previous();
              case null:
                break;
            }
          },
          child: child,
        );
      case GestureMode.none:
        return child;
    }
  }

  /// The active layout, honouring the auto-landscape override: while the
  /// device is rotated and `autoLandscapeLayout` is on, a "portrait"
  /// layout (Standard, Top Controls) renders as Landscape instead —
  /// without touching the persisted `playerLayoutId` the user actually
  /// picked. Gesture-first layouts and Car Mode already suit a wide
  /// viewport on their own, so they're left alone.
  PlayerLayout _resolveActiveLayout(BuildContext context, AppSettings settings) {
    final selected = _layouts.resolve(settings.playerLayoutId);
    const portraitOriented = {'standard', 'top_controls'};
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    if (settings.autoLandscapeLayout &&
        isLandscape &&
        portraitOriented.contains(selected.id)) {
      return _layouts.resolve('landscape');
    }
    return selected;
  }

  @override
  Widget build(BuildContext context) {
    final track = engine.currentTrack;
    final settings = _settings;

    if (track == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Now Playing')),
        body: const Center(
          child: Text('Nothing playing — pick a track from the Library.'),
        ),
      );
    }

    final lyricsProvider = _lyricsProvider;
    final lyricsEditor = _lyricsEditor;
    final lyricText = settings.showLyrics && lyricsProvider != null
        ? lyricsProvider.currentLyricFor(track, _position)
        : null;
    final sleepTimer = _sleepTimer;
    final equalizer = _equalizer;
    final visualizerProvider = _visualizerProvider;
    final visualizerEmitter = _visualizerEmitter;
    final crossfadeStatus = engine.crossfadeDuration > Duration.zero
        ? (engine.isCrossfading
            ? 'Crossfading into the next track…'
            : 'Crossfade armed for the last '
                '${engine.crossfadeDuration.inSeconds}s.')
        : null;

    final data = PlayerLayoutData(
      track: track,
      position: _position,
      duration: _duration,
      playing: _playing,
      buffering: _buffering,
      settings: settings,
      pluginManager: _plugins,
      lyricsPlugin: lyricsProvider,
      equalizerPlugin: equalizer,
      visualizerPlugin: visualizerProvider,
      sleepTimerPlugin: sleepTimer,
      lyricText: lyricText,
      crossfadeStatusText: crossfadeStatus,
      // ShuffleRepeatPlugin re-orders the queue itself rather than
      // setting the engine's own shuffle flag (see its class doc), so
      // its state — not the engine's — is the source of truth whenever
      // it's the one handling the toggle below.
      shuffleEnabled: _shuffleRepeat?.shuffleEnabled ?? engine.shuffleEnabled,
      repeatMode: engine.repeatMode,
      loopAMarker: engine.loopAMarker,
      abRepeatRange: engine.abRepeatRange,
      waveform: _waveformTrackId == track.id ? _waveform : null,
      onToggleShuffle: () async {
        final plugin = _shuffleRepeat;
        if (plugin != null) {
          await plugin.toggleShuffle();
        } else {
          await engine.setShuffleEnabled(!engine.shuffleEnabled);
        }
        if (mounted) setState(() {});
      },
      onCycleRepeat: () async {
        final plugin = _shuffleRepeat;
        if (plugin != null) {
          await plugin.cycleRepeat();
        } else {
          final next = switch (engine.repeatMode) {
            RepeatMode.off => RepeatMode.all,
            RepeatMode.all => RepeatMode.one,
            RepeatMode.one => RepeatMode.off,
          };
          await engine.setRepeatMode(next);
        }
        if (mounted) setState(() {});
      },
      onCycleAbRepeat: () {
        // Cycle: off -> A marked -> looping A-B -> off.
        if (engine.abRepeatRange != null) {
          engine.clearLoop();
        } else if (engine.loopAMarker != null) {
          engine.markLoopB();
        } else {
          engine.markLoopA();
        }
        setState(() {});
      },
      onPlayPause: () => _playing ? engine.pause() : engine.play(),
      onNext: () => engine.next(),
      onPrevious: () => engine.previous(),
      onSeek: (position) => engine.seek(position),
      onOpenEqualizer: equalizer == null
          ? () {}
          : () async {
              await EqualizerSheet.show(context, equalizer);
              if (mounted) setState(() {});
            },
      onEditLyrics: lyricsEditor == null
          ? () {}
          : () async {
              final changed = await LyricEditDialog.show(
                context,
                plugin: lyricsEditor,
                track: track,
              );
              if (changed && mounted) setState(() {});
            },
      onActivateVisualizer: visualizerEmitter == null
          ? () {}
          : () {
              visualizerEmitter
                  .emitLevels([0.2, 0.5, 0.7, 0.3, 0.8, 0.4, 0.6, 0.3]);
              _toast('Visualizer activated.');
            },
      onStartSleepTimer: sleepTimer == null
          ? () {}
          : () => _pickSleepTimerDuration(sleepTimer),
      onCancelSleepTimer: sleepTimer == null
          ? null
          : () {
              sleepTimer.stopTimer();
              setState(() {});
              _toast('Sleep timer cancelled.');
            },
    );

    final layout = _resolveActiveLayout(context, settings);
    final body = layout.build(context, data);

    return _DynamicColorScope(
      track: track,
      enabled: settings.dynamicColorFromArtEnabled,
      child: Scaffold(
        appBar: AppBar(title: const Text('Now Playing')),
        body: Stack(
          children: [
            Positioned.fill(child: NowPlayingBackground(track: track)),
            layout.definesOwnGestures
                ? body
                : _wrapWithGestureMode(body, settings),
          ],
        ),
      ),
    );
  }
}

/// Tints the ambient [ThemeData] from the current track's artwork
/// (`DynamicColorExtractor`) when [enabled] — Android 12-style dynamic
/// color, seeded from art instead of wallpaper. Renders [child] unchanged
/// while disabled, while extraction is still in flight for a new track,
/// or when extraction fails (no artwork, corrupt image) — a cosmetic
/// feature must never block or alter Now Playing beyond its own color
/// scheme.
class _DynamicColorScope extends StatefulWidget {
  final BaseTrack track;
  final bool enabled;
  final Widget child;

  const _DynamicColorScope({
    required this.track,
    required this.enabled,
    required this.child,
  });

  @override
  State<_DynamicColorScope> createState() => _DynamicColorScopeState();
}

class _DynamicColorScopeState extends State<_DynamicColorScope> {
  ColorScheme? _scheme;
  String? _resolvedForKey;

  @override
  void initState() {
    super.initState();
    _maybeResolve();
  }

  @override
  void didUpdateWidget(_DynamicColorScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybeResolve();
  }

  void _maybeResolve() {
    if (!widget.enabled) {
      if (_scheme != null) setState(() => _scheme = null);
      return;
    }
    final brightness = Theme.of(context).brightness;
    final key = '${widget.track.id}-${brightness.name}';
    if (_resolvedForKey == key) return;
    _resolvedForKey = key;
    _resolve(brightness, key);
  }

  Future<void> _resolve(Brightness brightness, String key) async {
    final bytes = await ArtworkProvider.forTrack(widget.track);
    final scheme = await DynamicColorExtractor.forTrack(
      trackId: widget.track.id,
      artBytes: bytes,
      brightness: brightness,
    );
    // The user may have switched tracks (or disabled the setting) again
    // before this resolved — only apply it if it's still the most recent
    // request in flight.
    if (mounted && _resolvedForKey == key) {
      setState(() => _scheme = scheme);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = _scheme;
    if (scheme == null) return widget.child;
    return Theme(
      data: Theme.of(context).copyWith(colorScheme: scheme),
      child: widget.child,
    );
  }
}
