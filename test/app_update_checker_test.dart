import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/core/app_update_checker.dart';
import 'package:omnis/core/omnis_version.dart';
import 'package:shared_preferences/shared_preferences.dart';

List<Map<String, dynamic>> _tags(List<String> names) =>
    [for (final name in names) {'name': name}];

void main() {
  final now = DateTime(2026, 8, 16);

  group('AppUpdateScheduler.isDue', () {
    test('null lastCheckAt is always due, regardless of interval', () {
      expect(
        AppUpdateScheduler.isDue(null, const Duration(days: 365), now),
        isTrue,
      );
    });

    test('a check older than the interval is due', () {
      final last = now.subtract(const Duration(days: 4));
      expect(
        AppUpdateScheduler.isDue(last, const Duration(days: 3), now),
        isTrue,
      );
    });

    test('a check within the interval is not due', () {
      final last = now.subtract(const Duration(days: 1));
      expect(
        AppUpdateScheduler.isDue(last, const Duration(days: 3), now),
        isFalse,
      );
    });

    test('exactly at the interval boundary is due — >=, not >', () {
      final last = now.subtract(const Duration(days: 3));
      expect(
        AppUpdateScheduler.isDue(last, const Duration(days: 3), now),
        isTrue,
      );
    });
  });

  group('latestAppVersionFromTags', () {
    test('a non-list response returns null', () {
      expect(latestAppVersionFromTags({'not': 'a list'}), isNull);
      expect(latestAppVersionFromTags(null), isNull);
    });

    test('an empty list returns null', () {
      expect(latestAppVersionFromTags(<dynamic>[]), isNull);
    });

    test('picks the highest of several vX.Y.Z tags, not the first or '
        'last in the list', () {
      final decoded = _tags(['v0.1.0', 'v0.3.0', 'v0.2.0']);
      expect(latestAppVersionFromTags(decoded), '0.3.0');
    });

    test('ignores non-app-release tags — plugin-api-vX.Y.Z and anything '
        'not shaped exactly vMAJOR.MINOR.PATCH', () {
      final decoded = _tags([
        'plugin-api-v0.19.0',
        'v0.5.0',
        'not-a-version',
        'v1.2', // missing patch segment
        'v1.2.3.4', // too many segments
      ]);
      expect(latestAppVersionFromTags(decoded), '0.5.0');
    });

    test('a list with nothing matching returns null', () {
      final decoded = _tags(['plugin-api-v0.19.0', 'random-tag']);
      expect(latestAppVersionFromTags(decoded), isNull);
    });

    test('a malformed individual entry is skipped, not fatal to the '
        'rest', () {
      final decoded = [
        <String, dynamic>{'name': 'v0.2.0'},
        <String, dynamic>{}, // no 'name' key
        'not even a map',
        <String, dynamic>{'name': 'v0.1.0'},
      ];
      expect(latestAppVersionFromTags(decoded), '0.2.0');
    });
  });

  group('AppUpdateService.checkForUpdate', () {
    test('returns the latest version when it is newer than the current '
        'one', () async {
      final client = MockClient((request) async => http.Response(
            jsonEncode(_tags(['v0.1.0', 'v9.9.9'])),
            200,
          ));
      final service = AppUpdateService(client: client);

      final result = await service.checkForUpdate();

      expect(result, '9.9.9');
    });

    test('returns null when already on the latest version', () async {
      final client = MockClient((request) async => http.Response(
            jsonEncode(_tags([omnisCoreVersion])),
            200,
          ));
      final service = AppUpdateService(client: client);

      expect(await service.checkForUpdate(), isNull);
    });

    test('a non-200 response returns null rather than throwing', () async {
      final client = MockClient((request) async => http.Response('', 500));
      final service = AppUpdateService(client: client);

      expect(await service.checkForUpdate(), isNull);
    });

    test('malformed JSON returns null rather than throwing', () async {
      final client =
          MockClient((request) async => http.Response('not json', 200));
      final service = AppUpdateService(client: client);

      expect(await service.checkForUpdate(), isNull);
    });
  });

  group('AppUpdateService.maybeCheckForUpdateAutomatically', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await AppSettings.instance.initialize();
    });

    test('does nothing when disabled', () async {
      final client = MockClient((request) async => http.Response(
            jsonEncode(_tags(['v9.9.9'])),
            200,
          ));
      final service = AppUpdateService(client: client);
      final settings = AppSettings.instance;
      settings.autoAppUpdateCheckEnabled = false;

      await service.maybeCheckForUpdateAutomatically(settings: settings);

      expect(settings.lastAppUpdateCheckAt, isNull);
      expect(service.lastKnownLatestVersion, isNull);
    });

    test('does nothing when enabled but not yet due', () async {
      final client = MockClient((request) async => http.Response(
            jsonEncode(_tags(['v9.9.9'])),
            200,
          ));
      final service = AppUpdateService(client: client);
      final settings = AppSettings.instance;
      settings.autoAppUpdateCheckEnabled = true;
      settings.lastAppUpdateCheckAt = now.subtract(const Duration(hours: 1));

      await service.maybeCheckForUpdateAutomatically(
          settings: settings, now: now);

      expect(service.lastKnownLatestVersion, isNull);
    });

    test('runs when enabled and due, caching the result and stamping '
        'the timestamp', () async {
      final client = MockClient((request) async => http.Response(
            jsonEncode(_tags(['v9.9.9'])),
            200,
          ));
      final service = AppUpdateService(client: client);
      final settings = AppSettings.instance;
      settings.autoAppUpdateCheckEnabled = true;

      await service.maybeCheckForUpdateAutomatically(
          settings: settings, now: now);

      expect(service.lastKnownLatestVersion, '9.9.9');
      expect(settings.lastKnownAppUpdateVersion, '9.9.9');
      expect(settings.lastAppUpdateCheckAt, now);
    });

    test('stamps the timestamp even when no update is found — "checked '
        'and found nothing" still counts as a completed check', () async {
      final client = MockClient((request) async => http.Response('', 500));
      final service = AppUpdateService(client: client);
      final settings = AppSettings.instance;
      settings.autoAppUpdateCheckEnabled = true;

      await service.maybeCheckForUpdateAutomatically(
          settings: settings, now: now);

      expect(service.lastKnownLatestVersion, isNull);
      expect(settings.lastAppUpdateCheckAt, now);
    });
  });
}
