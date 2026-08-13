import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/core/media_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.initialize();
    tempDir =
        await Directory.systemTemp.createTemp('omnis_media_scanner_test');
    AppSettings.instance.librarySource = LibrarySource.dedicatedFolder;
    AppSettings.instance.selectedFolderPath = tempDir.path;
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  File audioFile(String name) {
    // Untagged bytes — no leading 'ID3' header. MediaScanner should still
    // pick the file up and fall back to the filename as the title, the
    // same untagged-file case tag_editor_plugin_test.dart's own fixture
    // covers.
    final file = File('${tempDir.path}/$name');
    file.writeAsBytesSync(List.filled(200, 0xFF));
    return file;
  }

  test('scanLibrary finds real audio files under the configured folder',
      () async {
    audioFile('song_one.mp3');
    audioFile('song_two.mp3');
    File('${tempDir.path}/not_audio.txt').writeAsStringSync('ignore me');

    final tracks = await MediaScanner.instance.scanLibrary();

    expect(tracks.map((t) => t.title).toSet(), {'song_one', 'song_two'});
  });

  test('librarySource none returns no tracks without touching the disk',
      () async {
    AppSettings.instance.librarySource = LibrarySource.none;

    final tracks = await MediaScanner.instance.scanLibrary();

    expect(tracks, isEmpty);
  });

  group('directory-walk error handling', () {
    // Regression coverage for a real bug: a blanket try/catch used to
    // wrap the *entire* recursive directory walk, so a single stream
    // error (permission denied, a broken symlink, removable storage
    // unmounting mid-scan) threw out of the `await for` and silently
    // discarded everything the walk hadn't reached yet — no crash, no
    // signal, just a truncated library. Real directory permission
    // semantics differ too much across platforms/CI to fake reliably, so
    // these inject the same shape of failure directly against
    // MediaScanner's own lister seam (see MediaScanner.forTesting)
    // instead of trying to create a genuinely unreadable directory.

    test(
        'a stream error partway through the walk skips only that entry, '
        'not the files after it', () async {
      final fileA = audioFile('song_a.mp3');
      final fileB = audioFile('song_b.mp3');

      final scanner = MediaScanner.forTesting(
        lister: (dir) => Stream<FileSystemEntity>.fromFutures([
          Future.value(fileA),
          Future<FileSystemEntity>.error(
              const FileSystemException('permission denied', '/some/dir')),
          Future.value(fileB),
        ]),
      );

      final tracks = await scanner.scanLibrary();

      expect(tracks.map((t) => t.title).toSet(), {'song_a', 'song_b'},
          reason:
              'both files on either side of the stream error must still be '
              'found — the old blanket try/catch would have dropped '
              'song_b entirely');
    });

    test('an entirely unreadable root returns no tracks without throwing',
        () async {
      final scanner = MediaScanner.forTesting(
        lister: (dir) => Stream<FileSystemEntity>.fromFutures([
          Future<FileSystemEntity>.error(
              const FileSystemException('permission denied', '/root')),
        ]),
      );

      final tracks = await scanner.scanLibrary();

      expect(tracks, isEmpty);
    });

    test('multiple errors interspersed with valid files all get skipped',
        () async {
      final fileA = audioFile('song_a.mp3');
      final fileB = audioFile('song_b.mp3');
      final fileC = audioFile('song_c.mp3');

      final scanner = MediaScanner.forTesting(
        lister: (dir) => Stream<FileSystemEntity>.fromFutures([
          Future<FileSystemEntity>.error(
              const FileSystemException('permission denied', '/a')),
          Future.value(fileA),
          Future<FileSystemEntity>.error(
              const FileSystemException('permission denied', '/b')),
          Future.value(fileB),
          Future<FileSystemEntity>.error(
              const FileSystemException('permission denied', '/c')),
          Future.value(fileC),
        ]),
      );

      final tracks = await scanner.scanLibrary();

      expect(
          tracks.map((t) => t.title).toSet(), {'song_a', 'song_b', 'song_c'});
    });
  });

  group('per-file error handling', () {
    // Regression coverage for a real bug adjacent to the directory-walk
    // one above: a file that vanishes *after* being listed but *before*
    // it's stat'd/read (deleted mid-scan, removable storage unmounting)
    // used to throw out of `file.lastModified()`, which propagated out
    // of the `Future.wait` batch in `_scanFilesystem` and aborted the
    // entire scan — discarding every track already found, not just the
    // one vanished file.

    test('a file that no longer exists when read is skipped, not fatal '
        'to the whole scan', () async {
      final fileA = audioFile('song_a.mp3');
      final vanished = File('${tempDir.path}/vanished.mp3');
      // Never actually created on disk — lastModified() on it throws a
      // real FileSystemException, the same shape a deleted/unmounted
      // file produces, no platform-specific fakery required.
      final fileB = audioFile('song_b.mp3');

      final scanner = MediaScanner.forTesting(
        lister: (dir) => Stream<FileSystemEntity>.fromIterable(
            [fileA, vanished, fileB]),
      );

      final tracks = await scanner.scanLibrary();

      expect(tracks.map((t) => t.title).toSet(), {'song_a', 'song_b'},
          reason: 'both real files must still be found — only the '
              'vanished one should be skipped');
    });
  });

  group('incremental scanning (knownTracks)', () {
    // Regression coverage for a real, user-reported problem: every scan
    // re-read and re-decoded ID3 tags for every file, even ones already
    // known from the previous scan — slow for a large desktop library.
    // A file whose mtime still matches its cached BaseTrack should be
    // reused outright, not re-parsed.

    test('an unchanged known file is reused, not re-parsed', () async {
      audioFile('song_a.mp3');
      final firstScan = await MediaScanner.instance.scanLibrary();
      expect(firstScan, hasLength(1));
      expect(firstScan.single.fileModifiedAt, isNotNull);

      final secondScan = await MediaScanner.instance
          .scanLibrary(knownTracks: firstScan);

      expect(secondScan, hasLength(1));
      // Reference-identical to the object passed in via knownTracks — the
      // only way that happens is the scanner short-circuited before
      // calling _trackFromFile at all, rather than constructing a new
      // (if field-equal) BaseTrack from a fresh tag read.
      expect(identical(secondScan.single, firstScan.single), isTrue);
    });

    test('a modified known file is re-parsed, not reused', () async {
      final file = audioFile('song_a.mp3');
      final firstScan = await MediaScanner.instance.scanLibrary();
      final originalMtime = firstScan.single.fileModifiedAt;

      // Rewriting the file's bytes advances its real mtime — some
      // filesystems only report mtime at one-second granularity, so the
      // gap has to be comfortably past that, not just past scheduler
      // jitter.
      await Future.delayed(const Duration(seconds: 1, milliseconds: 100));
      file.writeAsBytesSync(List.filled(300, 0xFF));

      final secondScan = await MediaScanner.instance
          .scanLibrary(knownTracks: firstScan);

      expect(secondScan, hasLength(1));
      expect(identical(secondScan.single, firstScan.single), isFalse);
      expect(secondScan.single.fileModifiedAt, isNot(originalMtime));
    });

    test('a genuinely new file is parsed and gets no dateAdded stamped by '
        'the scanner itself', () async {
      audioFile('song_new.mp3');

      final tracks =
          await MediaScanner.instance.scanLibrary(knownTracks: const []);

      expect(tracks, hasLength(1));
      expect(tracks.single.fileModifiedAt, isNotNull);
      // The scanner has no reliable "first added" signal on the
      // filesystem-walk path — backfilling dateAdded is the caller's job
      // (library_page.dart), not the scanner's.
      expect(tracks.single.dateAdded, isNull);
    });
  });
}
