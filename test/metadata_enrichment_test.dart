import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis_plugins/metadata_enrichment_plugin.dart';
import 'package:shared_preferences/shared_preferences.dart';

BaseTrack _track({String artist = 'Ava', String title = 'Sunrise'}) =>
    BaseTrack(
      id: 't1',
      title: title,
      artists: [artist],
      album: 'Unknown Album',
      duration: 180,
      type: TrackType.local,
    );

/// A response builder keyed by host, so one [MockClient] can stand in for
/// all three real APIs without a network call.
http.Client _mockFor(Map<String, http.Response Function(http.Request)> byHost) {
  return MockClient((request) async {
    final handler = byHost[request.url.host];
    if (handler == null) {
      return http.Response('not found', 404);
    }
    return handler(request);
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.initialize();
  });

  group('MetadataEnrichmentPlugin credential gating', () {
    test('MusicBrainz runs with no credentials at all', () async {
      final client = _mockFor({
        'musicbrainz.org': (req) => http.Response(
              jsonEncode({
                'recordings': [
                  {
                    'title': 'Sunrise',
                    'artist-credit': [
                      {'name': 'Ava'}
                    ],
                    'releases': [
                      {'title': 'Morning', 'date': '2011-05-01'}
                    ],
                  }
                ],
              }),
              200,
            ),
      });
      final plugin = MetadataEnrichmentPlugin(client: client);

      final result = await plugin.enrichTrack(_track());

      expect(result.canonicalAlbum, 'Morning');
      expect(result.canonicalArtist, 'Ava');
      expect(result.year, 2011);
      expect(result.sourcesUsed, contains('MusicBrainz'));
      // Neither key was configured, so neither source should have been hit.
      expect(result.sourcesUsed, isNot(contains('Last.fm')));
      expect(result.sourcesUsed, isNot(contains('Discogs')));
      expect(result.genres, isEmpty);
    });

    test('Last.fm is skipped entirely when no API key is configured', () async {
      var lastfmCalled = false;
      final client = _mockFor({
        'musicbrainz.org': (req) =>
            http.Response(jsonEncode({'recordings': []}), 200),
        'ws.audioscrobbler.com': (req) {
          lastfmCalled = true;
          return http.Response('{}', 200);
        },
      });
      final plugin = MetadataEnrichmentPlugin(client: client);

      await plugin.enrichTrack(_track());

      expect(lastfmCalled, isFalse);
      expect(plugin.hasLastfmKey, isFalse);
    });

    test('Last.fm tags become genres, and a mood word is picked out',
        () async {
      final client = _mockFor({
        'musicbrainz.org': (req) =>
            http.Response(jsonEncode({'recordings': []}), 200),
        'ws.audioscrobbler.com': (req) => http.Response(
              jsonEncode({
                'toptags': {
                  'tag': [
                    {'name': 'electronic', 'count': 100},
                    {'name': 'chill', 'count': 80},
                    {'name': '00s', 'count': 10},
                  ],
                },
              }),
              200,
            ),
      });
      final plugin = MetadataEnrichmentPlugin(client: client);
      await plugin.setLastfmApiKey('user-key');

      final result = await plugin.enrichTrack(_track());

      expect(result.genres, containsAll(['electronic', 'chill', '00s']));
      expect(result.mood, 'chill');
      expect(result.sourcesUsed, contains('Last.fm'));
    });

    test('Discogs genres/styles merge in only when a token is configured',
        () async {
      final client = _mockFor({
        'musicbrainz.org': (req) =>
            http.Response(jsonEncode({'recordings': []}), 200),
        'api.discogs.com': (req) => http.Response(
              jsonEncode({
                'results': [
                  {
                    'genre': ['Electronic'],
                    'style': ['Ambient', 'Downtempo'],
                  }
                ],
              }),
              200,
            ),
      });
      final plugin = MetadataEnrichmentPlugin(client: client);
      await plugin.setDiscogsToken('user-token');

      final result = await plugin.enrichTrack(_track());

      expect(result.genres,
          containsAll(['Electronic', 'Ambient', 'Downtempo']));
      expect(result.sourcesUsed, contains('Discogs'));
    });
  });

  group('MetadataEnrichmentPlugin failure handling', () {
    test('a non-200 response is treated as no match, not an error', () async {
      final client = _mockFor({
        'musicbrainz.org': (req) => http.Response('server error', 500),
      });
      final plugin = MetadataEnrichmentPlugin(client: client);

      final result = await plugin.enrichTrack(_track());

      expect(result.isEmpty, isTrue);
    });

    test('malformed JSON never throws out of enrichTrack', () async {
      final client = _mockFor({
        'musicbrainz.org': (req) => http.Response('not json at all {{{', 200),
      });
      final plugin = MetadataEnrichmentPlugin(client: client);

      final result = await plugin.enrichTrack(_track());

      expect(result.isEmpty, isTrue);
    });

    test('a track with no artist is never looked up', () async {
      var called = false;
      final client = _mockFor({
        'musicbrainz.org': (req) {
          called = true;
          return http.Response(jsonEncode({'recordings': []}), 200);
        },
      });
      final plugin = MetadataEnrichmentPlugin(client: client);

      final result = await plugin.enrichTrack(BaseTrack(
        id: 'x',
        title: 'No Artist',
        artists: const [],
        album: 'Album',
        duration: 1,
        type: TrackType.local,
      ));

      expect(called, isFalse);
      expect(result.isEmpty, isTrue);
    });
  });
}
