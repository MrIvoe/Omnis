import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/track_fingerprint.dart';
import 'package:omnis/core/track_fingerprint_store.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String tempDir;

  _FakePathProvider(this.tempDir);

  @override
  Future<String?> getApplicationDocumentsPath() async => tempDir;

  @override
  Future<String?> getApplicationSupportPath() async => tempDir;

  @override
  Future<String?> getTemporaryPath() async => tempDir;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('computeFileFingerprint', () {
    late String tempDir;

    setUp(() async {
      tempDir =
          (await Directory.systemTemp.createTemp('omnis_fingerprint_test'))
              .path;
    });

    test('the same content produces the same fingerprint regardless of '
        'file path/name', () async {
      final fileA = File('$tempDir/original_name.mp3');
      await fileA.writeAsBytes(List<int>.generate(1000, (i) => i % 256));
      final fileB = File('$tempDir/renamed.mp3');
      await fileB.writeAsBytes(List<int>.generate(1000, (i) => i % 256));

      final fpA = await computeFileFingerprint(fileA.path);
      final fpB = await computeFileFingerprint(fileB.path);
      expect(fpA, isNotNull);
      expect(fpA, fpB);
    });

    test('different content produces a different fingerprint', () async {
      final fileA = File('$tempDir/a.mp3');
      await fileA.writeAsBytes(List<int>.generate(1000, (i) => i % 256));
      final fileB = File('$tempDir/b.mp3');
      await fileB.writeAsBytes(List<int>.generate(1000, (i) => (i + 1) % 256));

      final fpA = await computeFileFingerprint(fileA.path);
      final fpB = await computeFileFingerprint(fileB.path);
      expect(fpA, isNot(fpB));
    });

    test('works for a file larger than the 64KB sample window (exercises '
        'both the head and tail read)', () async {
      final file = File('$tempDir/large.flac');
      await file.writeAsBytes(List<int>.generate(200000, (i) => i % 256));
      final fp = await computeFileFingerprint(file.path);
      expect(fp, isNotNull);

      // Changing only the tail (well past the head sample) must still
      // change the fingerprint — proves the tail bytes are actually read,
      // not just the head.
      final bytes = List<int>.generate(200000, (i) => i % 256);
      bytes[199999] = (bytes[199999] + 1) % 256;
      final fileB = File('$tempDir/large_tail_changed.flac');
      await fileB.writeAsBytes(bytes);
      final fpTailChanged = await computeFileFingerprint(fileB.path);
      expect(fpTailChanged, isNot(fp));
    });

    test('a nonexistent file returns null rather than throwing', () async {
      final fp = await computeFileFingerprint('$tempDir/does_not_exist.mp3');
      expect(fp, isNull);
    });

    test('an empty file returns null', () async {
      final file = File('$tempDir/empty.mp3');
      await file.writeAsBytes(const []);
      final fp = await computeFileFingerprint(file.path);
      expect(fp, isNull);
    });
  });

  group('TrackFingerprintStore', () {
    late String tempDir;

    setUp(() async {
      tempDir = (await Directory.systemTemp.createTemp('omnis_fp_store_test'))
          .path;
      PathProviderPlatform.instance = _FakePathProvider(tempDir);
      TrackFingerprintStore.instance.resetForTesting();
    });

    test('loading with no saved file returns an empty map', () async {
      expect(await TrackFingerprintStore.instance.load(), isEmpty);
    });

    test('a real save/load round-trip', () async {
      await TrackFingerprintStore.instance
          .save({'id1': 'fp1', 'id2': 'fp2'});
      final reloaded = await TrackFingerprintStore.instance.load();
      expect(reloaded, {'id1': 'fp1', 'id2': 'fp2'});
    });

    test('a corrupt file is treated as empty, never throws', () async {
      final file = File('$tempDir/omnis_track_fingerprints.json');
      await file.writeAsString('{not valid json');
      expect(await TrackFingerprintStore.instance.load(), isEmpty);
    });
  });
}
