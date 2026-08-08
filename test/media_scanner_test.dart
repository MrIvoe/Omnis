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
}
