import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/waveform_store.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Fake path_provider, same pattern as playlist_store_test.dart.
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String tempDir;
  _FakePathProvider(this.tempDir);

  @override
  Future<String?> getApplicationSupportPath() async => tempDir;
}

BaseTrack _track({
  String id = 't1',
  TrackType type = TrackType.local,
  String? localPath,
}) =>
    BaseTrack(
      id: id,
      title: 'Sunrise',
      artists: const ['Ava'],
      album: 'Album',
      duration: 180,
      type: type,
      localPath: localPath,
    );

/// `waveformFor` degrading to `null` on every failure mode (rather than
/// throwing) is the contract that lets `PlayerProgressBar` always have a
/// safe "fall back to the plain slider" path — see waveform_store.dart's
/// doc comment. `just_waveform`'s native extraction has no platform
/// channel registered in a plain `flutter test` environment, so these
/// exercise the real fallback path, not a simulated one — same approach
/// bootstrap_test.dart uses for `ensureCoreReady`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late String tempDir;

  setUp(() async {
    tempDir =
        (await Directory.systemTemp.createTemp('omnis_waveform_test')).path;
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
  });

  test('a streaming track (no localPath) never touches disk', () async {
    final track = _track(type: TrackType.spotify);
    final result = await WaveformStore().waveformFor(track);
    expect(result, isNull);
  });

  test('a local track with a null localPath returns null', () async {
    final track = _track(localPath: null);
    final result = await WaveformStore().waveformFor(track);
    expect(result, isNull);
  });

  test('a local track whose file does not exist returns null', () async {
    final track = _track(localPath: '$tempDir/does_not_exist.mp3');
    final result = await WaveformStore().waveformFor(track);
    expect(result, isNull);
  });

  test(
      'a local track with a real file but no waveform plugin registered '
      'degrades to null instead of throwing', () async {
    final audioFile = File('$tempDir/song.mp3');
    await audioFile.writeAsBytes([0, 1, 2, 3]);

    final track = _track(localPath: audioFile.path);
    await expectLater(WaveformStore().waveformFor(track), completes);
    expect(await WaveformStore().waveformFor(track), isNull);
  });
}
