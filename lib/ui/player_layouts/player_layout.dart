import 'package:flutter/material.dart';
import 'package:just_waveform/just_waveform.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/plugin_manager.dart';
import 'package:omnis/plugin_api/service_interfaces.dart';
import 'package:omnis_plugins/equalizer_plugin.dart';
import 'package:omnis_plugins/sleep_timer_plugin.dart';

/// Which way a horizontal swipe should skip.
enum SwipeSkipAction { previous, next }

/// Decides which way a swipe gesture should skip based on its primary
/// velocity, shared by every layout/gesture mode that offers swipe-to-skip
/// so the threshold lives in exactly one place. A pure function (not a
/// method on a State) so it's directly testable.
SwipeSkipAction? swipeSkipActionFor(
  double? velocity, {
  double threshold = 200,
}) {
  if (velocity == null) return null;
  if (velocity < -threshold) return SwipeSkipAction.next;
  if (velocity > threshold) return SwipeSkipAction.previous;
  return null;
}

/// Everything a [PlayerLayout] needs to render Now Playing, gathered by
/// the page's State so each layout stays a pure function of data plus a
/// handful of callbacks — a layout never touches streams, the service
/// locator, or plugin lookups itself.
class PlayerLayoutData {
  final BaseTrack track;
  final Duration position;
  final Duration? duration;
  final bool playing;
  final bool buffering;

  /// Live settings — layouts read display prefs (album art, lyrics,
  /// karaoke, button density, car-mode side) straight from here rather
  /// than through a duplicated set of fields.
  final AppSettings settings;

  final PluginManager pluginManager;

  /// Looked up by interface, not concrete plugin type — see
  /// `NowPlayingPage._lyricsProvider`. `null` means no lyrics source is
  /// registered (the Lyrics plugin is disabled), the same meaning the old
  /// concrete-typed field had.
  final ILyricsProvider? lyricsPlugin;
  final EqualizerPlugin? equalizerPlugin;

  /// Looked up by interface, not concrete plugin type — see
  /// `NowPlayingPage._visualizerProvider`.
  final IVisualizerProvider? visualizerPlugin;
  final SleepTimerPlugin? sleepTimerPlugin;

  /// The current lyric line, already resolved for [position]. `null` only
  /// when lyrics are switched off in Settings; when the plugin is enabled
  /// but has nothing stored, this is the plugin's own "nothing yet"
  /// message, never null.
  final String? lyricText;

  /// Human-readable crossfade status, or `null` when crossfade is off.
  final String? crossfadeStatusText;

  /// Live shuffle/repeat state, read straight from `AudioEngine` (not
  /// `AppSettings`) since the engine is the source of truth for what's
  /// actually mirrored onto the player right now.
  final bool shuffleEnabled;
  final RepeatMode repeatMode;

  /// A-B repeat state, read straight from `AudioEngine`: `null`/`null`
  /// means off, [loopAMarker] set alone means "A marked, waiting for B",
  /// and both set means it is actively looping.
  final Duration? loopAMarker;
  final (Duration a, Duration b)? abRepeatRange;

  /// Cached peak data for [track], when available — see
  /// `lib/core/waveform_store.dart`. `null` covers every case a layout
  /// must treat the same way (still computing, streaming track, no
  /// native support on this platform): fall back to the plain
  /// [PlayerProgressBar] slider rather than distinguishing why.
  final Waveform? waveform;

  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onOpenEqualizer;
  final VoidCallback onEditLyrics;
  final VoidCallback onActivateVisualizer;

  /// Opens the §40/§41 Queue panel (`lib/ui/widgets/queue_panel.dart`) —
  /// same "callback lives on `PlayerLayoutData`, `NowPlayingPage` owns
  /// the actual wiring" split every other player-adjacent panel here
  /// already uses.
  final VoidCallback onOpenQueue;
  final VoidCallback onStartSleepTimer;
  final VoidCallback? onCancelSleepTimer;

  /// Advances the combined shuffle/repeat play-mode cycle: off -> repeat
  /// all -> repeat one -> shuffle -> off. Replaces separate shuffle and
  /// repeat toggles with a single control (see
  /// `ShuffleRepeatPlugin.cyclePlayMode`).
  final VoidCallback onCyclePlayMode;
  final VoidCallback onCycleAbRepeat;

  /// Long-press on the A-B repeat button — opens the saved/named loops
  /// sheet (save the currently-active loop, apply/delete a previously
  /// saved one for this track). MusicBee comparison §27 / spec §19.
  final VoidCallback onLongPressAbRepeat;

  const PlayerLayoutData({
    required this.track,
    required this.position,
    required this.duration,
    required this.playing,
    required this.buffering,
    required this.settings,
    required this.pluginManager,
    required this.lyricsPlugin,
    required this.equalizerPlugin,
    required this.visualizerPlugin,
    required this.sleepTimerPlugin,
    required this.lyricText,
    required this.crossfadeStatusText,
    required this.shuffleEnabled,
    required this.repeatMode,
    required this.loopAMarker,
    required this.abRepeatRange,
    this.waveform,
    required this.onPlayPause,
    required this.onNext,
    required this.onPrevious,
    required this.onSeek,
    required this.onOpenEqualizer,
    required this.onEditLyrics,
    required this.onActivateVisualizer,
    required this.onOpenQueue,
    required this.onStartSleepTimer,
    this.onCancelSleepTimer,
    required this.onCyclePlayMode,
    required this.onCycleAbRepeat,
    required this.onLongPressAbRepeat,
  });

  /// `h:mm:ss` once past an hour, `m:ss` otherwise.
  String formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '${d.inMinutes}:$s';
  }
}

/// A selectable arrangement of the Now Playing screen.
///
/// Layouts are bundled Dart/Flutter code registered in
/// `lib/ui/player_layouts/registry.dart` — **not** downloadable at runtime
/// the way the Plugins tab's `dart_eval` plugins are. A downloaded plugin
/// is deliberately barred from touching `dart:ui` (that is the sandbox
/// boundary that keeps it safe), so it cannot construct a real widget
/// tree — and a layout is nothing *but* a widget tree. The two
/// extensibility mechanisms can't share a runtime. Anyone editing the
/// app's source can add a layout in two steps (a class in this directory,
/// one line in the registry); this is an extension point for
/// contributors, not an end-user plugin system.
abstract class PlayerLayout {
  /// Stable id persisted in [AppSettings.playerLayoutId]. Never rename an
  /// existing id — a user's saved preference would silently fall back to
  /// Standard (see `resolvePlayerLayout`).
  String get id;

  String get name;

  /// One line shown under the layout's name in the picker.
  String get description;

  IconData get icon;

  /// Whether this layout manages its own gestures (tap to play/pause,
  /// swipe to skip). When true, `NowPlayingPage` does not additionally
  /// wrap it with the Settings → Gesture mode handler, since the layout's
  /// gestures *are* its whole interaction model, not an addition on top
  /// of visible buttons the other layouts have.
  bool get definesOwnGestures => false;

  Widget build(BuildContext context, PlayerLayoutData data);
}
