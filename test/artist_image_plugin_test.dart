import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omnis_plugins/artist_image_plugin.dart';

void main() {
  group('ArtistImagePlugin', () {
    test('returns picture_medium from a successful Deezer search match',
        () async {
      final client = MockClient((request) async {
        expect(request.url.host, 'api.deezer.com');
        expect(request.url.path, '/search/artist');
        expect(request.url.queryParameters['q'], 'Ava');
        return http.Response(
          jsonEncode({
            'data': [
              {'id': 1, 'name': 'Ava', 'picture_medium': 'https://example.com/ava.jpg'},
            ],
          }),
          200,
        );
      });
      final plugin = ArtistImagePlugin(client: client);

      final url = await plugin.imageUrlFor('Ava');

      expect(url, 'https://example.com/ava.jpg');
    });

    test('returns null when the search has no results', () async {
      final client = MockClient((request) async {
        return http.Response(jsonEncode({'data': []}), 200);
      });
      final plugin = ArtistImagePlugin(client: client);

      expect(await plugin.imageUrlFor('Nobody'), isNull);
    });

    test('returns null on a non-200 response', () async {
      final client = MockClient((request) async {
        return http.Response('rate limited', 429);
      });
      final plugin = ArtistImagePlugin(client: client);

      expect(await plugin.imageUrlFor('Ava'), isNull);
    });

    test('returns null on malformed JSON rather than throwing', () async {
      final client = MockClient((request) async {
        return http.Response('not json', 200);
      });
      final plugin = ArtistImagePlugin(client: client);

      expect(await plugin.imageUrlFor('Ava'), isNull);
    });

    test('degrades to null on a network failure rather than throwing',
        () async {
      final client = MockClient((request) async {
        throw Exception('no network');
      });
      final plugin = ArtistImagePlugin(client: client);

      expect(await plugin.imageUrlFor('Ava'), isNull);
    });

    test('skips the network entirely for an empty or "Unknown Artist" name',
        () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return http.Response(jsonEncode({'data': []}), 200);
      });
      final plugin = ArtistImagePlugin(client: client);

      expect(await plugin.imageUrlFor(''), isNull);
      expect(await plugin.imageUrlFor('Unknown Artist'), isNull);
      expect(calls, 0);
    });

    test('caches a lookup so a second call for the same artist does not '
        'hit the network again', () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return http.Response(
          jsonEncode({
            'data': [
              {'picture_medium': 'https://example.com/ava.jpg'},
            ],
          }),
          200,
        );
      });
      final plugin = ArtistImagePlugin(client: client);

      await plugin.imageUrlFor('Ava');
      await plugin.imageUrlFor('Ava');

      expect(calls, 1);
    });

    test('invalidate() clears the cache so the next lookup re-queries',
        () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return http.Response(
          jsonEncode({
            'data': [
              {'picture_medium': 'https://example.com/ava.jpg'},
            ],
          }),
          200,
        );
      });
      final plugin = ArtistImagePlugin(client: client);

      await plugin.imageUrlFor('Ava');
      plugin.invalidate('Ava');
      await plugin.imageUrlFor('Ava');

      expect(calls, 2);
    });

    test('isAvailable is always true — no credential required', () {
      final plugin = ArtistImagePlugin(client: MockClient((_) async => http.Response('', 200)));
      expect(plugin.isAvailable, isTrue);
    });
  });
}
