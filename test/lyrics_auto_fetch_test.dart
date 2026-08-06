import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/core/audio_engine.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/event_bus.dart';
import 'package:omnis/core/plugin_context.dart';
import 'package:omnis/core/service_registry.dart';
import 'package:omnis/plugin_api/service_interfaces.dart';
import 'package:omnis/plugins/lyrics_plugin.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeEngine implements AudioEngine {
  BaseTrack? current;

  @override
  BaseTrack? get currentTrack => current;

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName} not stubbed');
}

class _FakeTagWriter implements IFileTagWriter {
  final Map<String, String> written = {};

  @override
  Future<bool> writeLyrics(String filePath, String lyrics) async {
    written[filePath] = lyrics;
    return true;
  }
}

BaseTrack _track({String? localPath}) => BaseTrack(
      id: 't1',
      title: 'Threshold',
      artists: const ['Bad Omens'],
      album: 'THE DEATH OF PEACE OF MIND',
      duration: 197,
      type: TrackType.local,
      localPath: localPath,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.initialize();
  });

  group('parseLrc', () {
    test('parses standard [mm:ss.xx] timestamps in order', () {
      const lrc = '[00:12.50]First line\n[00:05.00]Second line (out of order)';
      final lines = parseLrc(lrc);

      expect(lines, hasLength(2));
      expect(lines[0].text, 'Second line (out of order)');
      expect(lines[0].timestamp, const Duration(seconds: 5));
      expect(lines[1].text, 'First line');
      expect(lines[1].timestamp,
          const Duration(seconds: 12, milliseconds: 500));
    });

    test('skips metadata lines like [ar:Artist]', () {
      const lrc = '[ar:Bad Omens]\n[ti:Threshold]\n[00:01.00]Real lyric line';
      final lines = parseLrc(lrc);

      expect(lines, hasLength(1));
      expect(lines.single.text, 'Real lyric line');
    });

    test('handles a timestamp with no fractional seconds', () {
      final lines = parseLrc('[01:30]No fraction here');
      expect(lines.single.timestamp, const Duration(minutes: 1, seconds: 30));
    });

    test('empty input produces no lines', () {
      expect(parseLrc(''), isEmpty);
    });
  });

  group('LyricsPlugin auto-fetch', () {
    test('fetchLyrics stores both plain and synced lyrics from an exact match',
        () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/get');
        return http.Response(
          jsonEncode({
            'plainLyrics': 'Plain lyric text',
            'syncedLyrics': '[00:01.00]Synced line one',
            'instrumental': false,
          }),
          200,
        );
      });
      final plugin = LyricsPlugin(client: client);
      final track = _track();

      final result = await plugin.fetchLyrics(track);

      expect(result.isEmpty, isFalse);
      expect(plugin.lyricFor(track), 'Plain lyric text');
      expect(plugin.timedLyricFor(track).single.text, 'Synced line one');
      expect(plugin.lastFetchStatus, contains('Fetched lyrics'));
    });

    test('falls back to /api/search when the exact match 404s', () async {
      var searchCalled = false;
      final client = MockClient((request) async {
        if (request.url.path == '/api/get') {
          return http.Response('not found', 404);
        }
        searchCalled = true;
        return http.Response(
          jsonEncode([
            {'plainLyrics': 'From search', 'instrumental': false},
          ]),
          200,
        );
      });
      final plugin = LyricsPlugin(client: client);

      final result = await plugin.fetchLyrics(_track());

      expect(searchCalled, isTrue);
      expect(result.plainLyrics, 'From search');
    });

    test('an instrumental track is not treated as a failure', () async {
      final client = MockClient((request) async => http.Response(
            jsonEncode({'instrumental': true}),
            200,
          ));
      final plugin = LyricsPlugin(client: client);

      final result = await plugin.fetchLyrics(_track());

      expect(result.instrumental, isTrue);
      expect(result.isEmpty, isFalse);
      expect(plugin.lastFetchStatus, contains('instrumental'));
    });

    test('a non-200/malformed response never throws, resolves to empty',
        () async {
      final client =
          MockClient((request) async => http.Response('server error', 500));
      final plugin = LyricsPlugin(client: client);

      final result = await plugin.fetchLyrics(_track());

      expect(result.isEmpty, isTrue);
    });

    test('onTrackStart auto-fetches only when enabled and nothing is stored '
        'yet', () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return http.Response(
          jsonEncode({'plainLyrics': 'Auto-fetched', 'instrumental': false}),
          200,
        );
      });
      final plugin = LyricsPlugin(client: client);
      final track = _track();

      // Auto-fetch off by default — no network call.
      await plugin.onTrackStart(track);
      expect(calls, 0);

      await plugin.setAutoFetchEnabled(true);
      await plugin.onTrackStart(track);
      expect(calls, 1);
      expect(plugin.lyricFor(track), 'Auto-fetched');

      // Already has lyrics now — a second track start must not re-fetch.
      await plugin.onTrackStart(track);
      expect(calls, 1);
    });

    test('writeToMetadataEnabled writes fetched lyrics through '
        'IFileTagWriter for a track with a local file', () async {
      final client = MockClient((request) async => http.Response(
            jsonEncode({'plainLyrics': 'Write me', 'instrumental': false}),
            200,
          ));
      final plugin = LyricsPlugin(client: client);
      final writer = _FakeTagWriter();
      final services = ServiceRegistry()..register(IFileTagWriter, writer);
      plugin.attach(PluginContext(
        audioEngine: _FakeEngine(),
        services: services,
        events: EventBus(),
      ));
      await plugin.setWriteToMetadataEnabled(true);

      await plugin.fetchLyrics(_track(localPath: '/music/threshold.mp3'));

      expect(writer.written['/music/threshold.mp3'], 'Write me');
    });

    test('writeToMetadataEnabled is a no-op for a track with no local file',
        () async {
      final client = MockClient((request) async => http.Response(
            jsonEncode({'plainLyrics': 'Write me', 'instrumental': false}),
            200,
          ));
      final plugin = LyricsPlugin(client: client);
      final writer = _FakeTagWriter();
      final services = ServiceRegistry()..register(IFileTagWriter, writer);
      plugin.attach(PluginContext(
        audioEngine: _FakeEngine(),
        services: services,
        events: EventBus(),
      ));
      await plugin.setWriteToMetadataEnabled(true);

      await plugin.fetchLyrics(_track()); // no localPath

      expect(writer.written, isEmpty);
    });
  });
}
