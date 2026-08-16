import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/core/audio_engine.dart';
import 'package:omnis/core/backup_service.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/home_widget_service.dart';
import 'package:omnis/core/library_repository.dart';
import 'package:omnis/core/permissions.dart';
import 'package:omnis/core/play_history_store.dart';
import 'package:omnis/core/playback_diagnostics.dart';
import 'package:omnis/core/playback_schedule.dart';
import 'package:omnis/core/playback_scheduler.dart';
import 'package:omnis/core/playback_state.dart';
import 'package:omnis/core/playback_watchdog.dart';
import 'package:omnis/core/playlist_store.dart';
import 'package:omnis/core/plugin_context.dart';
import 'package:omnis/core/plugin_manager.dart';
import 'package:omnis/core/queue_history_store.dart';
import 'package:omnis/core/recovery_journal.dart';
import 'package:omnis/core/sandbox.dart';
import 'package:omnis_plugins/bundled_plugins.dart';

/// MainCore is the entry point for the Omnis micro-kernel music engine.
///
/// It owns the two "indestructible" layers:
///  - the [AudioEngine] (playback never stops)
///  - the [PluginManager] (plugin crashes are sandboxed + health-logged)
///
/// It deliberately knows **no concrete plugin**. The only plugin-side
/// import is `createBundledPlugins()`, the registry in the separate
/// `omnis_plugins` package (github.com/MrIvoe/Omnis-Plugins), so adding
/// or removing a feature never touches this file — or this repo at all.
/// Plugins reach playback through the [PluginContext] built here, and the
/// UI binds to shared instances via `PluginManager.bundled<T>()`.
class MainCore {
  /// Audio engine instance.
  final AudioEngine _audioEngine;

  /// Plugin manager instance.
  final PluginManager _pluginManager;

  /// Playback watchdog — the permanent internal failure detector from §2
  /// of the Omnis 2.0 product spec. `late` because it must be wired to the
  /// real [_audioEngine], which is itself initialized in the constructor's
  /// initializer list — a field can't reference a sibling being initialized
  /// in the same list, so the watchdog is built in the constructor body.
  late final PlaybackWatchdog _watchdog;

  /// The recovery policy (watchdog-produced failures → reload/advance/stop).
  late final PlaybackRecovery _recovery;

  /// Rolling playback diagnostics (surfaced to the UI / support reports).
  final PlaybackDiagnosticsStore _diagnostics;

  bool _disposed = false;

  // Play-history position tracking (Continue Listening) — the engine only
  // exposes position/duration as streams, not a synchronous getter, so
  // the latest values are cached here and read back when a pause or
  // track-change moment actually calls for a position write. Cheap,
  // low-frequency writes only (pause, track change) — never per tick.
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<BaseTrack?>? _trackForHistorySub;
  StreamSubscription<List<BaseTrack>>? _queueHistorySub;
  Duration _lastPosition = Duration.zero;
  Duration _lastDuration = Duration.zero;
  BaseTrack? _trackBeingTracked;

  /// Periodic crash-recovery snapshot (§42 of the Omnis 2.0 product spec:
  /// "persist frequently enough to recover from crash, power loss, OS
  /// kill..."). Pause/track-change already save on their own — see below
  /// — but neither fires while a track just plays on uninterrupted for a
  /// long time, which is exactly the case a power-loss/OS-kill needs
  /// covered too.
  Timer? _journalTimer;

  /// Ticks once a minute to check for a due [PlaybackSchedule] —
  /// MusicBee comparison §43's scheduling gap. Runs at the same
  /// granularity a schedule's own [PlaybackSchedule.minuteOfDay]
  /// resolution supports; the actual due/dedup decision is pure logic
  /// in [PlaybackScheduler.dueSchedules], this timer is just the clock.
  Timer? _scheduleTimer;

  /// In-memory only, deliberately not persisted — an app restart simply
  /// re-allows every schedule to fire again today, which is harmless
  /// (worst case: one schedule replays once more the same day after a
  /// restart) and far simpler than a store field that would need its
  /// own migration/reset story.
  final Map<String, DateTime> _scheduleLastFiredAt = {};

  /// Constructor.
  MainCore()
      : _audioEngine = AudioEngine(),
        _pluginManager = PluginManager(),
        _diagnostics = PlaybackDiagnosticsStore() {
    // Wire the watchdog and recovery to the *real* engine. The watchdog
    // observes the engine's streams; the recovery acts on the same engine.
    // The recovery callback is what the watchdog invokes on a failure.
    _watchdog = PlaybackWatchdog(
      engine: _audioEngine,
      diagnostics: _diagnostics,
      recover: (failure, consecutive) => _recovery.recover(failure),
    );
    _recovery = PlaybackRecovery(
      engine: _audioEngine,
      diagnostics: _diagnostics,
      watchdog: _watchdog,
    );
  }

  /// Initialize the core engine: audio engine, plugin manager, bundled
  /// plugins, and any plugins installed on disk from previous sessions.
  Future<void> initialize() async {
    debugPrint('Initializing Omnis Core...');

    // Best-effort; a denial degrades to "no notification controls," never
    // blocks boot. Requested before the audio engine initializes
    // audio_service below, so the notification permission is already
    // resolved by the time there's a notification to post.
    await OmnisPermissions.ensureCorePermissions();

    // Audio engine first — the player must be ready before any plugin hook.
    await _audioEngine.initialize();

    // Start the playback watchdog as soon as there's an engine to observe.
    // It must be running before the queue is ever restored/populated below
    // (or by a caller right after initialize() returns) so a bad first
    // track is caught exactly the same as any later one.
    _watchdog.start();

    // Restore persisted playback preferences. These previously lived only
    // as ephemeral State fields in settings_page.dart, so every app
    // restart silently reset volume/speed/crossfade/gapless to hardcoded
    // defaults regardless of what the user last set.
    final settings = AppSettings.instance;
    await _audioEngine.setVolume(settings.volume);
    await _audioEngine.setSpeed(settings.playbackSpeed);
    _audioEngine.setGaplessEnabled(settings.gaplessEnabled);
    _audioEngine.setCrossfadeDuration(
        Duration(seconds: settings.crossfadeSeconds.round()));
    await _audioEngine.setPitch(settings.pitch);
    await _audioEngine.setSkipSilenceEnabled(settings.skipSilenceEnabled);

    // Wire the engine's track-started callback to the plugin hooks and to
    // play-history tracking (Home dashboard's Recently/Most Played) — the
    // latter is core, not plugin-dependent, so it's recorded directly
    // here rather than through the plugin manager.
    _audioEngine.onTrackStarted = (track) {
      // A track actually starting means the queue is healthy again — reset
      // the watchdog/recovery failure counters so one earlier transient
      // failure can't cascade into "everything is broken" the next time
      // something goes wrong.
      _watchdog.onTrackStarted();
      _recovery.reset();
      // Ignore failures: the plugin manager sandboxes every call.
      // ignore: unawaited_futures
      _pluginManager.onTrackStart(track);
      // ignore: unawaited_futures
      PlayHistoryStore.instance.recordPlay(track);
    };

    // Continue Listening position tracking. Cheap, low-frequency writes
    // only: on pause, and when the track changes (recording the position
    // of whichever track playback is moving away from) — never per
    // position tick.
    _positionSub = _audioEngine.positionStream.listen((pos) {
      _lastPosition = pos;
    });
    _durationSub = _audioEngine.durationStream.listen((dur) {
      _lastDuration = dur ?? Duration.zero;
    });
    _trackBeingTracked = _audioEngine.currentTrack;
    _playerStateSub = _audioEngine.playerStateStream.listen((state) {
      if (state.playing) return;
      final track = _audioEngine.currentTrack;
      if (track == null) return;
      // ignore: unawaited_futures
      PlayHistoryStore.instance
          .recordPosition(track.id, _lastPosition, _lastDuration);
      // A pause is exactly the moment §42 of the product spec cares about
      // most — the user stepped away, so the journal should reflect
      // *this* position, not whatever the last periodic tick captured.
      // ignore: unawaited_futures
      RecoveryJournal.instance.save(_audioEngine.captureState());
    });
    _trackForHistorySub = _audioEngine.trackStream.listen((track) {
      final previous = _trackBeingTracked;
      if (previous != null) {
        // ignore: unawaited_futures
        PlayHistoryStore.instance
            .recordPosition(previous.id, _lastPosition, _lastDuration);
      }
      _trackBeingTracked = track;
      if (track != null) {
        // ignore: unawaited_futures
        RecoveryJournal.instance.save(_audioEngine.captureState());
      }
    });
    // Queue history (§7 of the product spec) — an automatic, capped
    // rolling log of past queues. Observes queueStream from outside the
    // engine entirely, the same "external listener, no engine-side
    // dependency" shape PlaylistPage's own queueStream subscription
    // already uses, rather than teaching AudioEngine.setQueue itself
    // about persistence.
    _queueHistorySub = _audioEngine.queueStream.listen((queue) {
      // ignore: unawaited_futures
      QueueHistoryStore.instance.recordAutoHistory(queue);
    });

    // Belt-and-suspenders periodic snapshot — see [_journalTimer]'s doc.
    _journalTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (_audioEngine.currentTrack == null) return;
      // ignore: unawaited_futures
      RecoveryJournal.instance.save(_audioEngine.captureState());
    });

    // MusicBee comparison §43's scheduling gap. A no-op tick whenever
    // there are no saved schedules — see [_checkPlaybackSchedules].
    _scheduleTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      // ignore: unawaited_futures
      _checkPlaybackSchedules();
    });

    // Mirror track/play-state into the Android home-screen widget. Core,
    // not plugin-dependent — same reasoning as PlayHistoryStore/
    // RecoveryJournal above.
    HomeWidgetService.instance.initialize(_audioEngine);

    // Hand plugins their capability surface, then register the registry.
    _pluginManager.attachContext(OmnisPluginContext(
      audioEngine: _audioEngine,
      services: _pluginManager.services,
      events: _pluginManager.events,
    ));
    // registerAll (not a plain loop over createBundledPlugins()) so a
    // throwing bundled-plugins registry — a bad release of omnis_plugins,
    // or a single plugin constructor that throws — can't crash app boot.
    _pluginManager.registerAll(createBundledPlugins);

    // Initialize bundled plugins registered so far, then load any plugins
    // installed on disk from previous sessions.
    await _pluginManager.initializeAll();
    await _pluginManager.loadInstalled();

    // Item 4/50's "automatic scheduled backups" — a no-op unless the
    // user has opted in (AppSettings.autoBackupEnabled defaults false)
    // and one is actually due. Fire-and-forget, not awaited: writing a
    // zip must never delay app startup, the same "denial degrades,
    // never blocks boot" contract OmnisPermissions above already
    // follows.
    // ignore: unawaited_futures
    BackupService().maybeRunAutomaticBackup();

    debugPrint('Omnis Core initialized successfully');
  }

  /// Checks whether any saved [PlaybackSchedule] is due right now — the
  /// [_scheduleTimer]'s once-a-minute callback. A due schedule with a
  /// [PlaybackSchedule.playlistId] resolves that playlist against the
  /// current library and replaces the queue with it; one with no
  /// playlist just resumes whatever's already queued. Never throws — a
  /// scheduling failure must never crash the app, the same "denial
  /// degrades" contract every other best-effort background task in this
  /// file already follows.
  Future<void> _checkPlaybackSchedules() async {
    try {
      final schedules = await PlaybackScheduleStore.instance.load();
      if (schedules.isEmpty) return;
      final now = DateTime.now();
      final due = PlaybackScheduler.dueSchedules(
          schedules, now, _scheduleLastFiredAt);
      for (final schedule in due) {
        _scheduleLastFiredAt[schedule.id] = now;
        final playlistId = schedule.playlistId;
        if (playlistId != null) {
          final playlists = await PlaylistStore.instance.load();
          Playlist? playlist;
          for (final p in playlists) {
            if (p.id == playlistId) {
              playlist = p;
              break;
            }
          }
          if (playlist != null) {
            final library = await LibraryRepository.instance.load();
            final byId = {for (final t in library) t.id: t};
            final tracks = [
              for (final id in playlist.trackIds)
                if (byId[id] != null) byId[id]!
            ];
            if (tracks.isNotEmpty) {
              await _audioEngine.setQueue(tracks);
            }
          }
        }
        await _audioEngine.play();
      }
    } catch (e) {
      // Best-effort; a scheduling failure must never crash the app.
    }
  }

  /// Dispose the core engine.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    debugPrint('Disposing Omnis Core...');
    _journalTimer?.cancel();
    _scheduleTimer?.cancel();
    await _positionSub?.cancel();
    await _durationSub?.cancel();
    await _playerStateSub?.cancel();
    await _trackForHistorySub?.cancel();
    await _queueHistorySub?.cancel();
    await HomeWidgetService.instance.dispose();
    await _watchdog.dispose();
    await _pluginManager.dispose();
    await _audioEngine.dispose();
    debugPrint('Omnis Core disposed successfully');
  }

  /// Whether [dispose] has already run.
  bool get isDisposed => _disposed;

  /// The audio engine.
  AudioEngine get audioEngine => _audioEngine;

  /// The plugin manager.
  PluginManager get pluginManager => _pluginManager;

  /// The shared plugin sandbox (exposes health records for dashboards).
  PluginSandbox get sandbox => _pluginManager.sandbox;

  /// Rolling playback failure/recovery history (§2 of the product spec) —
  /// read-only, for a future plugin-health-style diagnostics view.
  PlaybackDiagnosticsStore get diagnostics => _diagnostics;

  /// Checks the recovery journal for a snapshot worth offering to resume
  /// (§42 of the product spec: **"Resume where you left off?"**).
  ///
  /// Returns `null` when there is nothing to resume: no journal, a
  /// corrupt/unparseable one, an empty queue, or a snapshot older than
  /// [maxAge] (a stale snapshot is actively cleared rather than silently
  /// ignored, so it doesn't linger forever). Deliberately read-only — it
  /// never touches the live engine, so it's safe to call before the user
  /// has decided whether to resume.
  Future<PlaybackState?> loadResumableState(
      {Duration maxAge = const Duration(hours: 24)}) async {
    final state = await RecoveryJournal.instance.load();
    if (state == null || !state.hasResumableContent) return null;
    if (RecoveryJournal.instance.isStale(state, maxAge: maxAge)) {
      await RecoveryJournal.instance.clear();
      return null;
    }
    return state;
  }

  /// Restores [state] into the live engine and starts playback — the
  /// action behind the user tapping "Resume" on the prompt.
  Future<void> resumePlayback(PlaybackState state) async {
    await _audioEngine.setQueue(state.queue, startIndex: state.currentIndex);
    await _audioEngine.setShuffleEnabled(state.shuffleEnabled);
    await _audioEngine.setRepeatMode(state.repeatMode);
    await _audioEngine.seek(state.position);
    if (state.wasPlaying) {
      await _audioEngine.play();
    }
  }

  /// Discards the recovery journal — the user declined the resume prompt,
  /// or a resume already happened and the stale snapshot shouldn't be
  /// offered again on the next launch.
  Future<void> dismissResumableState() => RecoveryJournal.instance.clear();
}
