import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/core/plugin_storage.dart';
import 'package:omnis_plugins/youtube_auth.dart';
import 'package:omnis_plugins/youtube_music_import_plugin.dart';
import 'package:omnis_plugins/youtube_playback_plugin.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Seeds [storage] with a valid (non-expired) access token — see the
/// identical helper/rationale in `test/spotify_plugins_test.dart`.
Future<void> _seedValidToken(PluginStorage storage) async {
  await storage.setString('youtube_access_token', 'valid-token');
  await storage.setInt(
    'youtube_expires_at_ms',
    DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.initialize();
  });

  group('YoutubeAuth token lifecycle', () {
    test('validAccessToken returns null when never connected', () async {
      final auth = YoutubeAuth(storage: PluginStorage('yt_test'));
      expect(await auth.validAccessToken(), isNull);
    });

    test('validAccessToken returns the stored token while unexpired',
        () async {
      final storage = PluginStorage('yt_test');
      await _seedValidToken(storage);
      final auth = YoutubeAuth(storage: storage);
      expect(await auth.validAccessToken(), 'valid-token');
    });

    test('validAccessToken refreshes an expired token, including the '
        'client secret when one is set', () async {
      final storage = PluginStorage('yt_refresh_test');
      await storage.setString('youtube_access_token', 'expired-token');
      await storage.setString('youtube_refresh_token', 'a-refresh-token');
      await storage.setString('youtube_client_secret', 'shh');
      await storage.setInt(
        'youtube_expires_at_ms',
        DateTime.now().subtract(const Duration(minutes: 5)).millisecondsSinceEpoch,
      );

      final client = MockClient((request) async {
        expect(request.url.host, 'oauth2.googleapis.com');
        expect(request.body, contains('client_secret=shh'));
        return http.Response(
          jsonEncode({'access_token': 'refreshed-token', 'expires_in': 3600}),
          200,
        );
      });
      final auth = YoutubeAuth(storage: storage, client: client);

      expect(await auth.validAccessToken(), 'refreshed-token');
    });

    test('disconnect clears every stored token', () async {
      final storage = PluginStorage('yt_disconnect_test');
      await _seedValidToken(storage);
      final auth = YoutubeAuth(storage: storage);
      expect(auth.isConnected, isTrue);

      await auth.disconnect();

      expect(auth.isConnected, isFalse);
    });
  });

  group('YoutubeMusicImportPlugin.searchPublic', () {
    test('requires an API key', () async {
      final plugin = YoutubeMusicImportPlugin(
          client: MockClient((r) async => http.Response('', 200)));

      final results = await plugin.searchPublic('some song');

      expect(results, isEmpty);
      expect(plugin.lastError, contains('API key'));
    });

    test('parses search results into BaseTrack', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/youtube/v3/search');
        expect(request.url.queryParameters['key'], 'my-api-key');
        return http.Response(
          jsonEncode({
            'items': [
              {
                'id': {'videoId': 'abc123XYZ90'},
                'snippet': {
                  'title': 'Some Song',
                  'channelTitle': 'Some Artist',
                  'thumbnails': {
                    'high': {'url': 'https://example.com/thumb.jpg'}
                  },
                },
              },
            ],
          }),
          200,
        );
      });
      final plugin = YoutubeMusicImportPlugin(client: client);
      await plugin.setApiKey('my-api-key');

      final results = await plugin.searchPublic('some song');

      expect(results, hasLength(1));
      expect(results.single.title, 'Some Song');
      expect(results.single.artists, ['Some Artist']);
      expect(results.single.youtubeId, 'abc123XYZ90');
      expect(results.single.coverArt, 'https://example.com/thumb.jpg');
    });

    test('a non-200 response never throws, sets lastError', () async {
      final client = MockClient((request) async => http.Response('err', 500));
      final plugin = YoutubeMusicImportPlugin(client: client);
      await plugin.setApiKey('my-api-key');

      final results = await plugin.searchPublic('query');

      expect(results, isEmpty);
      expect(plugin.lastError, contains('500'));
    });
  });

  group('YoutubeMusicImportPlugin private playlists', () {
    test('fetchMyPlaylists requires a connection', () async {
      final plugin = YoutubeMusicImportPlugin(
          client: MockClient((r) async => http.Response('', 200)));

      final playlists = await plugin.fetchMyPlaylists();

      expect(playlists, isEmpty);
      expect(plugin.lastError, contains('Not connected'));
    });

    test('fetchMyPlaylists parses real-shaped API responses', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/youtube/v3/playlists');
        expect(request.headers['Authorization'], 'Bearer valid-token');
        return http.Response(
          jsonEncode({
            'items': [
              {
                'id': 'PL1',
                'snippet': {'title': 'Favorites'},
                'contentDetails': {'itemCount': 12},
              },
            ],
          }),
          200,
        );
      });
      final plugin = YoutubeMusicImportPlugin(client: client);
      await _seedValidToken(plugin.storage);

      final playlists = await plugin.fetchMyPlaylists();

      expect(playlists, hasLength(1));
      expect(playlists.single.title, 'Favorites');
      expect(playlists.single.itemCount, 12);
    });

    test('fetchPlaylistItems maps playlist items into BaseTrack', () async {
      final client = MockClient((request) async => http.Response(
            jsonEncode({
              'items': [
                {
                  'snippet': {
                    'title': 'A Video',
                    'videoOwnerChannelTitle': 'A Channel',
                    'resourceId': {'videoId': 'zzz999XYZ90'},
                    'thumbnails': {
                      'high': {'url': 'https://example.com/a.jpg'}
                    },
                  },
                },
              ],
            }),
            200,
          ));
      final plugin = YoutubeMusicImportPlugin(client: client);
      await _seedValidToken(plugin.storage);

      final tracks = await plugin.fetchPlaylistItems('PL1');

      expect(tracks, hasLength(1));
      expect(tracks.single.title, 'A Video');
      expect(tracks.single.artists, ['A Channel']);
      expect(tracks.single.youtubeId, 'zzz999XYZ90');
    });
  });

  group('YoutubePlaybackPlugin.videoIdFromInput', () {
    test('extracts the video id from a standard watch URL', () {
      expect(
        YoutubePlaybackPlugin.videoIdFromInput(
            'https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
        'dQw4w9WgXcQ',
      );
    });

    test('extracts the video id from a youtu.be short URL', () {
      expect(
        YoutubePlaybackPlugin.videoIdFromInput('https://youtu.be/dQw4w9WgXcQ'),
        'dQw4w9WgXcQ',
      );
    });

    test('accepts a bare 11-character video id', () {
      expect(YoutubePlaybackPlugin.videoIdFromInput('dQw4w9WgXcQ'), 'dQw4w9WgXcQ');
    });

    test('returns null for garbage input', () {
      expect(YoutubePlaybackPlugin.videoIdFromInput('not a video'), isNull);
      expect(YoutubePlaybackPlugin.videoIdFromInput(''), isNull);
    });

    test('returns null for a URL with no video id', () {
      expect(YoutubePlaybackPlugin.videoIdFromInput('https://youtube.com/'),
          isNull);
    });
  });
}
