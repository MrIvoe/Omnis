import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/plugin_api/audio_analysis_result.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/plugins/audio_analysis_plugin.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late File audioFile;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.initialize();
    tempDir = await Directory.systemTemp.createTemp('omnis_audio_analysis');
    audioFile = File('${tempDir.path}/track.mp3');
    await audioFile.writeAsBytes([0, 1, 2, 3]);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  BaseTrack trackFor(String path) => BaseTrack(
        id: 't1',
        title: 'Test Track',
        artists: const ['Artist'],
        album: 'Album',
        duration: 180,
        type: TrackType.local,
        localPath: path,
      );

  group('AudioAnalysisPlugin', () {
    test('does nothing when no service URL is configured', () async {
      var called = false;
      final client = MockClient((request) async {
        called = true;
        return http.Response('{}', 200);
      });
      final plugin = AudioAnalysisPlugin(client: client);

      final result = await plugin.analyzeTrack(trackFor(audioFile.path));

      expect(called, isFalse);
      expect(result.isEmpty, isTrue);
      expect(plugin.isConfigured, isFalse);
    });

    test('parses a full analysis response', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/analyze');
        return http.Response(
          jsonEncode({
            'bpm': 128.4,
            'key': 'C',
            'scale': 'minor',
            'mood': 'energetic',
            'genres': ['electronic', 'techno'],
          }),
          200,
        );
      });
      final plugin = AudioAnalysisPlugin(client: client);
      await plugin.setServiceUrl('http://localhost:8686');

      final result = await plugin.analyzeTrack(trackFor(audioFile.path));

      expect(result.bpm, 128.4);
      expect(result.key, 'C');
      expect(result.scale, 'minor');
      expect(result.formattedKey, 'C Minor');
      expect(result.mood, 'energetic');
      expect(result.genres, containsAll(['electronic', 'techno']));
    });

    test('trims a trailing slash on the configured URL', () async {
      Uri? seenUri;
      final client = MockClient((request) async {
        seenUri = request.url;
        return http.Response(jsonEncode({'bpm': 100}), 200);
      });
      final plugin = AudioAnalysisPlugin(client: client);
      await plugin.setServiceUrl('http://localhost:8686/');

      await plugin.analyzeTrack(trackFor(audioFile.path));

      expect(seenUri?.toString(), 'http://localhost:8686/analyze');
    });

    test('a non-200 response is treated as no result, not an error',
        () async {
      final client = MockClient((request) async => http.Response('err', 500));
      final plugin = AudioAnalysisPlugin(client: client);
      await plugin.setServiceUrl('http://localhost:8686');

      final result = await plugin.analyzeTrack(trackFor(audioFile.path));
      expect(result.isEmpty, isTrue);
    });

    test('malformed JSON never throws out of analyzeTrack', () async {
      final client =
          MockClient((request) async => http.Response('not json {{{', 200));
      final plugin = AudioAnalysisPlugin(client: client);
      await plugin.setServiceUrl('http://localhost:8686');

      final result = await plugin.analyzeTrack(trackFor(audioFile.path));
      expect(result.isEmpty, isTrue);
    });

    test('a track with no local file is never sent to the service',
        () async {
      var called = false;
      final client = MockClient((request) async {
        called = true;
        return http.Response('{}', 200);
      });
      final plugin = AudioAnalysisPlugin(client: client);
      await plugin.setServiceUrl('http://localhost:8686');

      final streamTrack = BaseTrack(
        id: 's1',
        title: 'Stream',
        artists: const ['Artist'],
        album: 'Album',
        duration: 180,
        type: TrackType.youtube,
        streamUrl: 'https://example.com/a.mp3',
      );
      final result = await plugin.analyzeTrack(streamTrack);

      expect(called, isFalse);
      expect(result.isEmpty, isTrue);
    });

    test('a local file that does not exist on disk is skipped', () async {
      var called = false;
      final client = MockClient((request) async {
        called = true;
        return http.Response('{}', 200);
      });
      final plugin = AudioAnalysisPlugin(client: client);
      await plugin.setServiceUrl('http://localhost:8686');

      final result =
          await plugin.analyzeTrack(trackFor('${tempDir.path}/missing.mp3'));

      expect(called, isFalse);
      expect(result.isEmpty, isTrue);
    });
  });

  group('AudioAnalysisResult', () {
    test('formattedKey combines key and scale with title case', () {
      const major = AudioAnalysisResult(key: 'F#', scale: 'major');
      expect(major.formattedKey, 'F# Major');
      const missingScale = AudioAnalysisResult(key: 'C');
      expect(missingScale.formattedKey, isNull);
    });

    test('isEmpty is true only when nothing was found', () {
      expect(const AudioAnalysisResult().isEmpty, isTrue);
      expect(const AudioAnalysisResult(bpm: 120).isEmpty, isFalse);
      expect(const AudioAnalysisResult(genres: ['rock']).isEmpty, isFalse);
    });
  });
}
