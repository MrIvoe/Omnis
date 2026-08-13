import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/app_settings.dart' show RepeatMode;
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/playback_state.dart';
import 'package:omnis/core/recovery_journal.dart';

/// Covers §42 of the Omnis 2.0 product spec ("crash recovery journal") —
/// the journal is the thing that survives a crash/power-loss/OS-kill, so
/// its failure modes (corrupt file, stale snapshot, interrupted write)
/// matter more than its happy path.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late File journalFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('omnis_journal_test');
    journalFile = File('${tempDir.path}/omnis_recovery_journal.json');
    RecoveryJournal.instance.fileOverride = journalFile;
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

  PlaybackState sampleState({DateTime? savedAt}) => PlaybackState(
        queue: [track('1'), track('2')],
        currentIndex: 1,
        position: const Duration(seconds: 42),
        wasPlaying: true,
        shuffleEnabled: true,
        repeatMode: RepeatMode.all,
        volume: 0.8,
        speed: 1.0,
        pitch: 1.0,
        skipSilenceEnabled: false,
        gaplessEnabled: true,
        crossfadeDuration: const Duration(seconds: 3),
        savedAt: savedAt,
      );

  test('load() returns null when no journal file exists', () async {
    expect(await RecoveryJournal.instance.load(), isNull);
  });

  test('save() then load() round-trips the snapshot, and the .tmp file is '
      'never left behind', () async {
    await RecoveryJournal.instance.save(sampleState());

    final tmp = File('${journalFile.path}.tmp');
    expect(await tmp.exists(), isFalse);
    expect(await journalFile.exists(), isTrue);

    final loaded = await RecoveryJournal.instance.load();
    expect(loaded, isNotNull);
    expect(loaded!.queue, hasLength(2));
    expect(loaded.currentIndex, 1);
    expect(loaded.position, const Duration(seconds: 42));
    expect(loaded.wasPlaying, isTrue);
    expect(loaded.shuffleEnabled, isTrue);
    expect(loaded.repeatMode, RepeatMode.all);
  });

  test('load() treats a corrupt/unparseable file as "nothing to resume", '
      'not a crash', () async {
    await journalFile.create(recursive: true);
    await journalFile.writeAsString('{not valid json');

    expect(await RecoveryJournal.instance.load(), isNull);
  });

  test('load() treats an empty file as "nothing to resume"', () async {
    await journalFile.create(recursive: true);
    await journalFile.writeAsString('');

    expect(await RecoveryJournal.instance.load(), isNull);
  });

  test('clear() removes the journal (and any stray .tmp file)', () async {
    await RecoveryJournal.instance.save(sampleState());
    expect(await journalFile.exists(), isTrue);

    await RecoveryJournal.instance.clear();

    expect(await journalFile.exists(), isFalse);
    expect(await RecoveryJournal.instance.load(), isNull);
  });

  test('isStale() is true once savedAt is older than maxAge', () {
    final old = sampleState(
        savedAt: DateTime.now().toUtc().subtract(const Duration(hours: 30)));
    final fresh = sampleState(savedAt: DateTime.now().toUtc());

    expect(RecoveryJournal.instance.isStale(old), isTrue);
    expect(RecoveryJournal.instance.isStale(fresh), isFalse);
  });

  test('removeIfStale() clears a stale journal and reports true; leaves a '
      'fresh one untouched and reports false', () async {
    await RecoveryJournal.instance.save(sampleState(
        savedAt: DateTime.now().toUtc().subtract(const Duration(hours: 48))));

    final removed = await RecoveryJournal.instance.removeIfStale();

    expect(removed, isTrue);
    expect(await journalFile.exists(), isFalse);

    await RecoveryJournal.instance.save(sampleState());
    final removedFresh = await RecoveryJournal.instance.removeIfStale();

    expect(removedFresh, isFalse);
    expect(await journalFile.exists(), isTrue);
  });

  test('save() overwrites a previous snapshot rather than merging with it',
      () async {
    await RecoveryJournal.instance.save(sampleState());
    await RecoveryJournal.instance.save(sampleState()
        .copyWith(currentIndex: 0, position: const Duration(seconds: 5)));

    final loaded = await RecoveryJournal.instance.load();
    expect(loaded!.currentIndex, 0);
    expect(loaded.position, const Duration(seconds: 5));
  });

  test('two concurrent save() calls (e.g. a pause and the periodic '
      'heartbeat landing together) are serialized — neither throws, no '
      '.tmp file is left behind, and the result is one complete '
      'snapshot, not a torn write', () async {
    // Deliberately not awaited individually — both start before either
    // finishes, which is exactly what happens when MainCore's pause
    // handler and its 20s Timer.periodic heartbeat both call save()
    // around the same moment.
    final first = RecoveryJournal.instance
        .save(sampleState().copyWith(currentIndex: 0));
    final second = RecoveryJournal.instance
        .save(sampleState().copyWith(currentIndex: 1));

    await Future.wait([first, second]);

    final tmp = File('${journalFile.path}.tmp');
    expect(await tmp.exists(), isFalse,
        reason: 'a lost race used to leave a stray .tmp behind');

    // Whichever write actually landed, it must be one complete,
    // internally-consistent snapshot (parseable, currentIndex either 0
    // or 1) — never a torn mix of both writes' bytes.
    final loaded = await RecoveryJournal.instance.load();
    expect(loaded, isNotNull);
    expect(loaded!.currentIndex, anyOf(0, 1));
  });

  test('save() and clear() racing (e.g. dismissing the resume prompt '
      'right as the heartbeat fires) never throws and leaves a '
      'consistent end state', () async {
    await RecoveryJournal.instance.save(sampleState());

    final saveCall = RecoveryJournal.instance.save(sampleState());
    final clearCall = RecoveryJournal.instance.clear();

    await Future.wait([saveCall, clearCall]);

    final tmp = File('${journalFile.path}.tmp');
    expect(await tmp.exists(), isFalse);
    // Whichever ran last (they're serialized, so deterministically
    // clear() — the second call in program order) decides the outcome;
    // either way this must not throw and must not leave a half-written
    // file.
    expect(await journalFile.exists(), isFalse);
  });
}
