import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/app_settings.dart' show RepeatMode;
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/main_core.dart';
import 'package:omnis/core/playback_state.dart';
import 'package:omnis/core/recovery_journal.dart';

/// MainCore's own class-level contract — construction, disposal
/// idempotency, isDisposed — as opposed to bootstrap_test.dart, which
/// covers the ensureCoreReady()/disposeCore() singleton-registration layer
/// built on top of it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a freshly constructed core is not disposed and exposes real '
      'sub-components before initialize() is even called', () {
    final core = MainCore();

    expect(core.isDisposed, isFalse);
    expect(core.audioEngine, isNotNull);
    expect(core.pluginManager, isNotNull);
    expect(core.sandbox, isNotNull);
    expect(core.diagnostics, isNotNull);
  });

  test('dispose() marks the core disposed', () async {
    final core = MainCore();

    await core.dispose();

    expect(core.isDisposed, isTrue);
  });

  test('dispose() is idempotent — a second call does not re-dispose',
      () async {
    final core = MainCore();

    await core.dispose();
    // If this re-ran the real dispose logic (AudioEngine.dispose(),
    // PluginManager.dispose()) a second time on already-torn-down
    // sub-components, it would be the kind of thing that throws on a
    // real platform even though it can't reproduce that specific failure
    // in this test environment — the guard itself is what's under test.
    await expectLater(core.dispose(), completes);
    expect(core.isDisposed, isTrue);
  });

  group('resumable state (§42 — journal-only, does not touch the engine)',
      () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('omnis_maincore_test');
      RecoveryJournal.instance.fileOverride =
          File('${tempDir.path}/omnis_recovery_journal.json');
    });

    tearDown(() async {
      RecoveryJournal.instance.clearFileOverride();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    BaseTrack track(String id) => BaseTrack(
          id: id,
          title: 'Track $id',
          artists: const ['Artist'],
          album: 'Album',
          duration: 180,
          type: TrackType.local,
        );

    test('loadResumableState() returns null when the journal is empty', () async {
      final core = MainCore();

      expect(await core.loadResumableState(), isNull);
    });

    test('loadResumableState() returns the snapshot when one is fresh and '
        'has content', () async {
      await RecoveryJournal.instance.save(PlaybackState(
        queue: [track('1')],
        currentIndex: 0,
        position: const Duration(seconds: 10),
        wasPlaying: true,
        shuffleEnabled: false,
        repeatMode: RepeatMode.off,
        volume: 1.0,
        speed: 1.0,
        pitch: 1.0,
        skipSilenceEnabled: false,
        gaplessEnabled: true,
        crossfadeDuration: Duration.zero,
      ));
      final core = MainCore();

      final state = await core.loadResumableState();

      expect(state, isNotNull);
      expect(state!.currentTrack?.id, '1');
    });

    test('loadResumableState() clears and returns null for a stale '
        'snapshot instead of offering to resume it', () async {
      await RecoveryJournal.instance.save(PlaybackState(
        queue: [track('1')],
        currentIndex: 0,
        position: Duration.zero,
        wasPlaying: false,
        shuffleEnabled: false,
        repeatMode: RepeatMode.off,
        volume: 1.0,
        speed: 1.0,
        pitch: 1.0,
        skipSilenceEnabled: false,
        gaplessEnabled: true,
        crossfadeDuration: Duration.zero,
        savedAt: DateTime.now().toUtc().subtract(const Duration(days: 3)),
      ));
      final core = MainCore();

      final state =
          await core.loadResumableState(maxAge: const Duration(hours: 24));

      expect(state, isNull);
      expect(await RecoveryJournal.instance.load(), isNull);
    });

    test('dismissResumableState() clears the journal', () async {
      await RecoveryJournal.instance.save(PlaybackState(
        queue: [track('1')],
        currentIndex: 0,
        position: Duration.zero,
        wasPlaying: false,
        shuffleEnabled: false,
        repeatMode: RepeatMode.off,
        volume: 1.0,
        speed: 1.0,
        pitch: 1.0,
        skipSilenceEnabled: false,
        gaplessEnabled: true,
        crossfadeDuration: Duration.zero,
      ));
      final core = MainCore();

      await core.dismissResumableState();

      expect(await core.loadResumableState(), isNull);
    });
  });
}
