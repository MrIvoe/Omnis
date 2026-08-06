import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/core/plugin_storage.dart';
import 'package:omnis/plugins/spotify_auth.dart';
import 'package:omnis/plugins/spotify_import_plugin.dart';
import 'package:omnis/plugins/spotify_playback_plugin.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Seeds [storage] with a valid (non-expired) access token, the way a
/// successful `connect()` would have — used to test the HTTP/JSON logic
/// downstream of auth without driving the interactive OAuth browser
/// flow, which needs a real platform channel this test environment
/// doesn't have.
///
/// Must be called with the *exact* [PluginStorage] instance the code
/// under test will later read from (a plugin's own `storage` getter, or
/// the same instance handed to `SpotifyAuth`) — [PluginStorage] caches
/// its backing store on first use, so writing through a different
/// instance would leave this one's cache still pointing at nothing, and
/// its synchronous getters would keep returning `null` regardless of
/// what's actually persisted underneath.
Future<void> _seedValidToken(PluginStorage storage) async {
  await storage.setString('spotify_access_token', 'valid-token');
  await storage.setInt(
    'spotify_expires_at_ms',
    DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.initialize();
  });

  group('SpotifyAuth token lifecycle', () {
    test('validAccessToken returns null when never connected', () async {
      final auth = SpotifyAuth(storage: PluginStorage('spotify_test'));
      expect(await auth.validAccessToken(), isNull);
    });

    test('validAccessToken returns the stored token while unexpired',
        () async {
      final storage = PluginStorage('spotify_test');
      await _seedValidToken(storage);
      final auth = SpotifyAuth(storage: storage);
      expect(await auth.validAccessToken(), 'valid-token');
    });

    test('validAccessToken refreshes an expired token using the refresh '
        'token', () async {
      final storage = PluginStorage('spotify_refresh_test');
      await storage.setString('spotify_access_token', 'expired-token');
      await storage.setString('spotify_refresh_token', 'a-refresh-token');
      await storage.setInt(
        'spotify_expires_at_ms',
        DateTime.now().subtract(const Duration(minutes: 5)).millisecondsSinceEpoch,
      );
      await storage.setString('spotify_client_id', 'client123');

      var refreshCalled = false;
      final client = MockClient((request) async {
        refreshCalled = true;
        expect(request.url.path, '/api/token');
        expect(request.body, contains('grant_type=refresh_token'));
        return http.Response(
          jsonEncode({'access_token': 'refreshed-token', 'expires_in': 3600}),
          200,
        );
      });
      final auth = SpotifyAuth(storage: storage, client: client);

      final token = await auth.validAccessToken();

      expect(refreshCalled, isTrue);
      expect(token, 'refreshed-token');
    });

    test('validAccessToken returns null when refresh fails', () async {
      final storage = PluginStorage('spotify_refresh_fail_test');
      await storage.setString('spotify_access_token', 'expired-token');
      await storage.setString('spotify_refresh_token', 'a-refresh-token');
      await storage.setInt(
        'spotify_expires_at_ms',
        DateTime.now().subtract(const Duration(minutes: 5)).millisecondsSinceEpoch,
      );

      final client =
          MockClient((request) async => http.Response('bad request', 400));
      final auth = SpotifyAuth(storage: storage, client: client);

      expect(await auth.validAccessToken(), isNull);
    });

    test('disconnect clears every stored token', () async {
      final storage = PluginStorage('spotify_disconnect_test');
      await _seedValidToken(storage);
      final auth = SpotifyAuth(storage: storage);
      expect(auth.isConnected, isTrue);

      await auth.disconnect();

      expect(auth.isConnected, isFalse);
      expect(await auth.validAccessToken(), isNull);
    });
  });

  group('SpotifyImportPlugin', () {
    test('fetchPlaylists parses real-shaped API responses', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/v1/me/playlists');
        expect(request.headers['Authorization'], 'Bearer valid-token');
        return http.Response(
          jsonEncode({
            'items': [
              {
                'id': 'pl1',
                'name': 'Road Trip',
                'tracks': {'total': 42},
              },
            ],
          }),
          200,
        );
      });
      final plugin = SpotifyImportPlugin(client: client);
      await _seedValidToken(plugin.storage);

      final playlists = await plugin.fetchPlaylists();

      expect(playlists, hasLength(1));
      expect(playlists.single.name, 'Road Trip');
      expect(playlists.single.trackCount, 42);
    });

    test('fetchPlaylistTracks maps Spotify track JSON into BaseTrack',
        () async {
      final client = MockClient((request) async => http.Response(
            jsonEncode({
              'items': [
                {
                  'track': {
                    'id': 'trk1',
                    'name': 'Threshold',
                    'duration_ms': 197000,
                    'artists': [
                      {'name': 'Bad Omens'}
                    ],
                    'album': {
                      'name': 'THE DEATH OF PEACE OF MIND',
                      'images': [
                        {'url': 'https://example.com/art.jpg'}
                      ],
                    },
                  },
                },
              ],
            }),
            200,
          ));
      final plugin = SpotifyImportPlugin(client: client);
      await _seedValidToken(plugin.storage);

      final tracks = await plugin.fetchPlaylistTracks('pl1');

      expect(tracks, hasLength(1));
      final track = tracks.single;
      expect(track.title, 'Threshold');
      expect(track.artists, ['Bad Omens']);
      expect(track.duration, 197);
      expect(track.spotifyId, 'trk1');
      expect(track.coverArt, 'https://example.com/art.jpg');
    });

    test('fetchPlaylists returns empty with lastError when not connected',
        () async {
      final plugin = SpotifyImportPlugin(client: MockClient((r) async => http.Response('', 200)));

      final playlists = await plugin.fetchPlaylists();

      expect(playlists, isEmpty);
      expect(plugin.lastError, contains('Not connected'));
    });

    test('a non-200 response never throws, sets lastError', () async {
      final client = MockClient((request) async => http.Response('err', 500));
      final plugin = SpotifyImportPlugin(client: client);
      await _seedValidToken(plugin.storage);

      final playlists = await plugin.fetchPlaylists();

      expect(playlists, isEmpty);
      expect(plugin.lastError, contains('500'));
    });
  });

  group('SpotifyPlaybackPlugin', () {
    test('fetchDevices parses the device list', () async {
      final client = MockClient((request) async => http.Response(
            jsonEncode({
              'devices': [
                {'id': 'd1', 'name': 'Living Room Speaker', 'is_active': true},
                {'id': 'd2', 'name': 'Phone', 'is_active': false},
              ],
            }),
            200,
          ));
      final plugin = SpotifyPlaybackPlugin(client: client);
      await _seedValidToken(plugin.storage);

      final devices = await plugin.fetchDevices();

      expect(devices, hasLength(2));
      expect(devices[0].name, 'Living Room Speaker');
      expect(devices[0].isActive, isTrue);
      expect(devices[1].isActive, isFalse);
    });

    test('fetchState returns null when nothing is playing (204)', () async {
      final client = MockClient((request) async => http.Response('', 204));
      final plugin = SpotifyPlaybackPlugin(client: client);
      await _seedValidToken(plugin.storage);

      expect(await plugin.fetchState(), isNull);
    });

    test('fetchState parses currently playing track', () async {
      final client = MockClient((request) async => http.Response(
            jsonEncode({
              'is_playing': true,
              'progress_ms': 5000,
              'device': {'name': 'Living Room Speaker'},
              'item': {
                'name': 'Threshold',
                'duration_ms': 197000,
                'artists': [
                  {'name': 'Bad Omens'}
                ],
              },
            }),
            200,
          ));
      final plugin = SpotifyPlaybackPlugin(client: client);
      await _seedValidToken(plugin.storage);

      final state = await plugin.fetchState();

      expect(state, isNotNull);
      expect(state!.trackName, 'Threshold');
      expect(state.artistName, 'Bad Omens');
      expect(state.isPlaying, isTrue);
      expect(state.progress, const Duration(seconds: 5));
      expect(state.deviceName, 'Living Room Speaker');
    });

    test('play/pause/next/previous hit the right endpoints', () async {
      final calls = <String>[];
      final client = MockClient((request) async {
        calls.add('${request.method} ${request.url.path}');
        return http.Response('', 204);
      });
      final plugin = SpotifyPlaybackPlugin(client: client);
      await _seedValidToken(plugin.storage);

      await plugin.play();
      await plugin.pause();
      await plugin.next();
      await plugin.previous();

      expect(calls, [
        'PUT /v1/me/player/play',
        'PUT /v1/me/player/pause',
        'POST /v1/me/player/next',
        'POST /v1/me/player/previous',
      ]);
    });
  });
}
