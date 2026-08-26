import 'dart:async';
import 'dart:io' show File, Platform;

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:just_audio/just_audio.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/core/app_update_checker.dart';
import 'package:omnis/core/audio_engine.dart';
import 'package:omnis/core/backup_service.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/home_widget_service.dart';
import 'package:omnis/core/library_repository.dart';
import 'package:omnis/core/library_scan_scheduler.dart';
import 'package:omnis/core/library_watcher.dart';
import 'package:omnis/core/media_scanner.dart';
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
import 'package:omnis/core/queue_continuation.dart';
import 'package:omnis/core/queue_history_store.dart';
import 'package:omnis/core/queue_rules.dart';
import 'package:omnis/core/recovery_journal.dart';
import 'package:omnis/core/rename_reconciliation.dart';
import 'package:omnis/core/sandbox.dart';
import 'package:omnis/core/track_fingerprint.dart';
import 'package:omnis/core/track_fingerprint_store.dart';
import 'package:omnis_plugins/bundled_plugins.dart';
import 'package:omnis_plugins/custom_radio_station_store.dart';

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
  StreamSubscription<PlayerState>? _continuationSub;
  String? _lastContinuationSeedId;
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

  /// Item 5/spec §8's "filesystem watchers" gap — auto-rescans the
  /// user's dedicated library folder shortly after it changes on disk,
  /// instead of requiring a manual rescan. `null` when
  /// [AppSettings.libraryWatcherEnabled] is off, the platform is
  /// Android (which already gets live results from `on_audio_query`'s
  /// own MediaStore index — see `MediaScanner._scanAndroid`), or
  /// [AppSettings.librarySource] isn't a dedicated folder. Started once
  /// from current settings at [initialize] time, the same "read once at
  /// startup" shape every other restored player preference in this
  /// method already has — changing the watched folder or toggling the
  /// setting takes effect on the next app restart, not live.
  LibraryWatcher? _libraryWatcher;

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
        // Item 16/MusicBee comparison §37's "skip tracking" — the
        // moment playback moves off a track is exactly what "the
        // listen ended" means, distinct from a pause (recordPosition
        // above), which isn't itself a skip.
        // ignore: unawaited_futures
        PlayHistoryStore.instance
            .recordTrackEnd(previous.id, _lastPosition, _lastDuration);
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

    // Item 2 (Queue)'s "smart/rule-based continuation" gap. A separate
    // subscription from [_playerStateSub] above — that one early-returns
    // whenever `state.playing` is true, but on natural queue completion
    // `playing` isn't guaranteed false, so folding this in would risk
    // missing the event. `_lastContinuationSeedId` guards against firing
    // twice for the same completed track if the stream emits `completed`
    // more than once before a new track becomes current; it self-clears
    // the moment `currentTrack` changes (from this continuation or a
    // manual skip), so a later genuine queue-end fires again.
    _continuationSub = _audioEngine.playerStateStream.listen((state) {
      if (state.processingState != ProcessingState.completed) return;
      final mode = AppSettings.instance.queueContinuationMode;
      if (mode == QueueContinuationMode.off) return;
      final seed = _audioEngine.currentTrack;
      if (seed == null || _lastContinuationSeedId == seed.id) return;
      _lastContinuationSeedId = seed.id;
      // ignore: unawaited_futures
      _continueQueue(seed, mode);
    });

    // Belt-and-suspenders periodic snapshot — see [_journalTimer]'s doc.
    _journalTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (_audioEngine.currentTrack == null) return;
      // ignore: unawaited_futures
      RecoveryJournal.instance.save(_audioEngine.captureState());
    });

    // MusicBee comparison §43's scheduling gap. A no-op tick whenever
    // there are no saved schedules — see [_checkPlaybackSchedules].
    // Reuses the same once-a-minute tick for item 5's scheduled-scan
    // check (see [_maybeRunScheduledScan]) rather than adding a second
    // Timer — [LibraryScanScheduler.isDue] itself gates how often that
    // one actually does anything, so a per-minute check costs nothing
    // between due scans.
    _scheduleTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      // ignore: unawaited_futures
      _checkPlaybackSchedules();
      // ignore: unawaited_futures
      _maybeRunScheduledScan();
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
    //
    // Skippable via `--dart-define=OMNIS_NO_BUNDLED_PLUGINS=true` — a
    // dev/QA-only build flag for exercising the marketplace/catalog
    // install flow and every page's "no plugins registered" behavior
    // against a genuinely empty ServiceRegistry, the same state a brand
    // new install would have before anything gets installed. Defaults to
    // false, so every normal build is completely unaffected.
    if (!const bool.fromEnvironment('OMNIS_NO_BUNDLED_PLUGINS')) {
      _pluginManager.registerAll(createBundledPlugins);
    }

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

    // Item 29's "no automatic/background checking" — a no-op unless the
    // user has opted in (AppSettings.autoUpdateCheckEnabled defaults
    // false) and one is actually due. Fire-and-forget, same "never
    // block boot" contract as the backup call above.
    // ignore: unawaited_futures
    _pluginManager.maybeCheckForUpdatesAutomatically();

    // Item 28's "no heartbeat for a silently-hung plugin" gap — a no-op
    // unless the user has opted in (AppSettings.pluginHeartbeatEnabled
    // defaults false) and one is actually due. Fire-and-forget, same
    // "never block boot" contract as the calls above.
    // ignore: unawaited_futures
    _pluginManager.maybeRunHeartbeatsAutomatically();

    // Item 5/spec §8's "filesystem watchers" gap — see [_libraryWatcher]'s
    // own doc for the full gating logic (opt-in, desktop-only, dedicated
    // folder required).
    _maybeStartLibraryWatcher();

    // Item 5's "no scheduled scans" gap — a no-op unless the user has
    // opted in (AppSettings.autoScanEnabled defaults false) and one is
    // actually due. Fire-and-forget, same "never block boot" contract
    // as the backup/update-check calls above; also reached every
    // minute thereafter via [_scheduleTimer].
    // ignore: unawaited_futures
    _maybeRunScheduledScan();

    // The About page's "auto updater" toggle — a no-op unless the user
    // has opted in (AppSettings.autoAppUpdateCheckEnabled defaults
    // false) and one is actually due. Fire-and-forget, same "never
    // block boot" contract as the backup/plugin-update-check calls
    // above.
    // ignore: unawaited_futures
    AppUpdateService().maybeCheckForUpdateAutomatically();

    debugPrint('Omnis Core initialized successfully');
  }

  /// Checks whether any saved [PlaybackSchedule] is due right now — the
  /// [_scheduleTimer]'s once-a-minute callback. A due
  /// [PlaybackScheduleAction.stop] schedule just pauses playback,
  /// ignoring [PlaybackSchedule.playlistId]/[PlaybackSchedule.
  /// radioStationId] entirely (meaningless for a stop). A due
  /// [PlaybackScheduleAction.play] schedule resolves, in order: a
  /// [PlaybackSchedule.playlistId] against the current library and
  /// replaces the queue with it; otherwise a [PlaybackSchedule.
  /// radioStationId] against `CustomRadioStationStore` (item 50's
  /// "scheduled radio" gap) and replaces the queue with that station's
  /// track; one with neither just resumes whatever's already queued. A
  /// referenced playlist/station that's since been deleted degrades the
  /// same way — the queue is simply left untouched before playing.
  /// Never throws — a scheduling failure must never crash the app, the
  /// same "denial degrades" contract every other best-effort background
  /// task in this file already follows.
  Future<void> _checkPlaybackSchedules() async {
    try {
      final schedules = await PlaybackScheduleStore.instance.load();
      if (schedules.isEmpty) return;
      final now = DateTime.now();
      final due = PlaybackScheduler.dueSchedules(
          schedules, now, _scheduleLastFiredAt);
      for (final schedule in due) {
        _scheduleLastFiredAt[schedule.id] = now;

        if (schedule.action == PlaybackScheduleAction.stop) {
          await _audioEngine.pause();
          continue;
        }

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
        } else {
          // Item 50's "scheduled radio" gap — deliberately scoped to a
          // saved *custom* station only (see PlaybackSchedule.
          // radioStationId's own doc): CustomRadioStation.toTrack()
          // resolves to a playable BaseTrack with no network call,
          // unlike a Radio-Browser-searched station.
          final radioStationId = schedule.radioStationId;
          if (radioStationId != null) {
            final stations = await CustomRadioStationStore.instance.load();
            CustomRadioStation? station;
            for (final s in stations) {
              if (s.id == radioStationId) {
                station = s;
                break;
              }
            }
            if (station != null) {
              await _audioEngine.setQueue([station.toTrack()]);
            }
          }
        }
        await _audioEngine.play();
      }
    } catch (e) {
      // Best-effort; a scheduling failure must never crash the app.
    }
  }

  /// Item 2 (Queue)'s "smart/rule-based continuation" gap — extends the
  /// queue with [continuationTracks] chosen by [mode] once it naturally
  /// finishes playing [seed], instead of just stopping. Appends rather
  /// than replaces, so the growing queue itself doubles as the
  /// `excludeIds` anti-repeat set across a whole auto-continued session
  /// with no extra state to track. A no-op (queue just ends, same as
  /// today) whenever the library is empty or [continuationTracks] has
  /// nothing real to base a pick on.
  Future<void> _continueQueue(BaseTrack seed, QueueContinuationMode mode) async {
    try {
      final library = LibraryRepository.instance.tracks;
      if (library.isEmpty) return;
      final existingQueue = _audioEngine.queue;
      final settings = AppSettings.instance;
      final picked = continuationTracks(
        seed: seed,
        library: library,
        mode: mode,
        excludeIds: existingQueue.map((t) => t.id).toSet(),
        groupByAlbumArtist: settings.groupArtistsByAlbumArtist,
        constraints: QueueRuleConstraints(
          minArtistGap: settings.queueRuleAvoidRepeatArtist ? 1 : 0,
          minAlbumGap: settings.queueRuleAvoidRepeatAlbum ? 1 : 0,
        ),
        queueTail: existingQueue,
      );
      if (picked.isEmpty) return;
      await _audioEngine.setQueue(
        [...existingQueue, ...picked],
        startIndex: existingQueue.length,
      );
      await _audioEngine.play();
    } catch (e) {
      // Best-effort; a continuation failure must never crash the app —
      // the queue simply ends, same as if this feature didn't exist.
    }
  }

  /// Starts [_libraryWatcher] when every condition [_libraryWatcher]'s
  /// own doc names is met: [AppSettings.libraryWatcherEnabled], not
  /// Android/web, a dedicated folder actually selected. Any other
  /// combination is a silent no-op, not an error — this is a pure
  /// convenience feature, never something that should be able to block
  /// or complicate startup.
  void _maybeStartLibraryWatcher() {
    final settings = AppSettings.instance;
    if (!settings.libraryWatcherEnabled) return;
    if (!kIsWeb && Platform.isAndroid) return;
    if (settings.librarySource != LibrarySource.dedicatedFolder) return;
    final folder = settings.selectedFolderPath;
    if (folder == null || folder.isEmpty) return;

    _libraryWatcher = LibraryWatcher(
      onSettled: () async {
        final current = LibraryRepository.instance.tracks;
        final scanned =
            await MediaScanner.instance.scanLibrary(knownTracks: current);
        if (scanned.isEmpty) return;
        await _mergeScanIntoLibrary(current, scanned);
      },
    );
    _libraryWatcher!.start(folder);
  }

  /// Mirrors `library_page.dart`'s own "_pickAndAdd" merge exactly
  /// (minus its UI-specific bits — no `setState`, no in-progress
  /// spinner): a fresh scan only ever reports *local* files, so
  /// naively replacing the whole library with its result would
  /// silently drop every non-local track (Spotify/YouTube/radio/...).
  /// Keep every still-valid existing track, add only what's genuinely
  /// new ([newTracksFromScan], pure/tested), and prune a local track
  /// whose file is now gone (needs real file-existence I/O, so it stays
  /// here rather than in that pure function) — unless it's recognized as
  /// a rename via [reconcileRenamedTracks] (item 5's fix, the same one
  /// `library_page.dart._pickAndAdd` applies), in which case its old id
  /// is kept instead of being dropped and re-added under a new one.
  /// Shared by both [_maybeStartLibraryWatcher]'s onSettled callback and
  /// [_maybeRunScheduledScan]/[rescanNow] — every real trigger for a
  /// rescan being applied to the persisted library other than
  /// `library_page.dart`'s own explicit "Add audio files" button.
  Future<void> _mergeScanIntoLibrary(
    List<BaseTrack> current,
    List<BaseTrack> scanned,
  ) async {
    final newTracks = newTracksFromScan(current, scanned);
    final missingTracks = current.where((t) {
      return t.type == TrackType.local &&
          t.localPath != null &&
          !File(t.localPath!).existsSync();
    }).toList();
    // Only a genuine addition or removal is worth a write — a rescan
    // that finds nothing new and nothing gone (e.g. a file merely
    // touched/re-saved with the same path) shouldn't churn the library
    // store for no reason.
    if (newTracks.isEmpty && missingTracks.isEmpty) {
      return;
    }
    final stillPresent =
        current.where((t) => !missingTracks.contains(t)).toList();
    final fingerprintStore = TrackFingerprintStore.instance;
    final fingerprints = await fingerprintStore.load();
    final reconciled = await reconcileRenamedTracks(
      missingTracks: missingTracks,
      candidateNewTracks: newTracks,
      fingerprints: fingerprints,
      computeFingerprint: computeFileFingerprint,
    );
    await fingerprintStore.save(reconciled.updatedFingerprints);
    await LibraryRepository.instance
        .save([...stillPresent, ...reconciled.renamed, ...reconciled.trulyNew]);
  }

  /// An explicit, user-triggered rescan — item 48's command palette's
  /// "Scan library" action. Unlike [_maybeRunScheduledScan], never gated
  /// by [LibraryScanScheduler.isDue] (an explicit tap should always run,
  /// not silently no-op because a background scan happened to fire
  /// recently) and, unlike that method, lets a real failure propagate to
  /// the caller instead of swallowing it — the palette action is
  /// expected to catch it and tell the user, the same way a scheduled
  /// scan's own silent "try again next tick" isn't appropriate for an
  /// action the user is actively watching for a result from.
  Future<void> rescanNow() async {
    final current = LibraryRepository.instance.tracks;
    final scanned =
        await MediaScanner.instance.scanLibrary(knownTracks: current);
    if (scanned.isEmpty) return;
    await _mergeScanIntoLibrary(current, scanned);
  }

  /// Item 5's "no scheduled scans" gap — a no-op unless the user has
  /// opted in ([AppSettings.autoScanEnabled] defaults false) and one is
  /// actually due. Unlike [_maybeStartLibraryWatcher] (desktop-only,
  /// needs a real `Directory.watch`), this works on every platform:
  /// `MediaScanner.scanLibrary` already branches to the right source
  /// (MediaStore on Android, filesystem walk elsewhere) and already
  /// no-ops when [LibrarySource.none] is selected, so there's no extra
  /// platform/source gating to duplicate here. Never throws — a
  /// scheduling failure must never crash the app, the same "denial
  /// degrades" contract every other best-effort background task in
  /// this file already follows.
  Future<void> _maybeRunScheduledScan() async {
    final settings = AppSettings.instance;
    if (!settings.autoScanEnabled) return;
    if (!LibraryScanScheduler.isDue(
      settings.lastAutoScanAt,
      Duration(hours: settings.autoScanIntervalHours),
      DateTime.now(),
    )) {
      return;
    }
    try {
      final current = LibraryRepository.instance.tracks;
      final scanned =
          await MediaScanner.instance.scanLibrary(knownTracks: current);
      settings.lastAutoScanAt = DateTime.now();
      if (scanned.isEmpty) return;
      await _mergeScanIntoLibrary(current, scanned);
    } catch (_) {
      // Swallow — the next scheduled tick (or manual rescan) tries again.
    }
  }

  /// Dispose the core engine.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    debugPrint('Disposing Omnis Core...');
    _journalTimer?.cancel();
    _scheduleTimer?.cancel();
    _libraryWatcher?.stop();
    await _positionSub?.cancel();
    await _durationSub?.cancel();
    await _playerStateSub?.cancel();
    await _trackForHistorySub?.cancel();
    await _queueHistorySub?.cancel();
    await _continuationSub?.cancel();
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
