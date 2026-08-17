import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/core/plugin_installer.dart';
import 'package:omnis/core/plugin_manager.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Same fake path_provider plugin_installer_test.dart uses.
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String tempDir;
  _FakePathProvider(this.tempDir);

  @override
  Future<String?> getApplicationSupportPath() async => tempDir;
}

List<int> _buildZip(Map<String, String> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    final bytes = utf8.encode(entry.value);
    archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
  }
  return ZipEncoder().encode(archive)!;
}

String _manifest({String version = '1.0.0'}) => '''
id: sample_plugin
name: Sample Plugin
description: A test plugin
version: $version
author: Tester
entrypoint: plugin.dart
''';

// ManagedPlugin.version comes from the runtime's own createPlugin()
// result, not the omnis_plugin.yaml manifest's version: field — so a
// test simulating a version bump must vary both in lockstep, the same
// as a real plugin author bumping their own plugin.dart.
String _entrypoint({String version = '1.0.0'}) => '''
dynamic createPlugin(dynamic api) {
  return {
    'id': 'sample_plugin',
    'name': 'Sample Plugin',
    'version': '$version',
    'author': 'Tester',
    'hooks': [],
  };
}
''';

/// Routes by host: `codeload.github.com` (the zip download `installFromUrl`
/// itself uses) gets [zipBytes] at whatever [zipVersion] is current;
/// `raw.githubusercontent.com` (the manifest-only fetch
/// `checkForUpdates`/`fetchRemoteManifest` uses) gets a manifest text at
/// [manifestVersion] — independently settable so a test can simulate "the
/// published manifest says a newer version exists" before actually
/// downloading it.
class _RoutingClient extends http.BaseClient {
  String manifestVersion;
  String zipVersion;

  _RoutingClient({required this.manifestVersion, required this.zipVersion});

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.host == 'raw.githubusercontent.com') {
      final body = utf8.encode(_manifest(version: manifestVersion));
      return http.StreamedResponse(Stream.value(body), 200);
    }
    final zip = _buildZip({
      'repo-main/omnis_plugin.yaml': _manifest(version: zipVersion),
      'repo-main/plugin.dart': _entrypoint(version: zipVersion),
    });
    return http.StreamedResponse(Stream.value(zip), 200);
  }
}

/// Same routing as [_RoutingClient], but can be told to fail the zip
/// download specifically — used to simulate an update whose download
/// breaks partway (a network error, a server outage) after a real,
/// working version is already installed, the scenario item 29's
/// backup-before-update/rollback gap is about.
class _FailOnUpdateClient extends http.BaseClient {
  String manifestVersion;
  String zipVersion;
  bool failZipDownload = false;

  _FailOnUpdateClient({required this.manifestVersion, required this.zipVersion});

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.host == 'raw.githubusercontent.com') {
      final body = utf8.encode(_manifest(version: manifestVersion));
      return http.StreamedResponse(Stream.value(body), 200);
    }
    if (failZipDownload) {
      return http.StreamedResponse(
          Stream.value(utf8.encode('server error')), 500);
    }
    final zip = _buildZip({
      'repo-main/omnis_plugin.yaml': _manifest(version: zipVersion),
      'repo-main/plugin.dart': _entrypoint(version: zipVersion),
    });
    return http.StreamedResponse(Stream.value(zip), 200);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late String tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.initialize();
    tempDir =
        (await Directory.systemTemp.createTemp('omnis_plugin_updates_test'))
            .path;
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
  });

  tearDown(() async {
    final dir = Directory(tempDir);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  });

  group('checkForUpdates', () {
    test('reports an available update when the published manifest has a '
        'newer version than what is installed', () async {
      final client =
          _RoutingClient(manifestVersion: '1.0.0', zipVersion: '1.0.0');
      final manager = PluginManager(installer: PluginInstaller(client: client));
      await manager.installFromUrl('https://github.com/user/repo');

      client.manifestVersion = '2.0.0';
      final updates = await manager.checkForUpdates();

      expect(updates, hasLength(1));
      expect(updates.single.pluginId, 'sample_plugin');
      expect(updates.single.currentVersion, '1.0.0');
      expect(updates.single.latestVersion, '2.0.0');
    });

    test('reports nothing when the installed version is already current',
        () async {
      final client =
          _RoutingClient(manifestVersion: '1.0.0', zipVersion: '1.0.0');
      final manager = PluginManager(installer: PluginInstaller(client: client));
      await manager.installFromUrl('https://github.com/user/repo');

      final updates = await manager.checkForUpdates();

      expect(updates, isEmpty);
    });

    test('never flags an update for a bundled (in-process) plugin',
        () async {
      final client =
          _RoutingClient(manifestVersion: '9.9.9', zipVersion: '1.0.0');
      final manager = PluginManager(installer: PluginInstaller(client: client));
      // No external plugin installed at all — checkForUpdates must not
      // try to network-check anything, since only external plugins have
      // a real, checkable sourceUrl.
      final updates = await manager.checkForUpdates();

      expect(updates, isEmpty);
    });
  });

  group('maybeCheckForUpdatesAutomatically (item 29, "no automatic/'
      'background checking")', () {
    test('is a no-op when disabled, even if due', () async {
      AppSettings.instance.autoUpdateCheckEnabled = false;
      final client =
          _RoutingClient(manifestVersion: '1.0.0', zipVersion: '1.0.0');
      final manager = PluginManager(installer: PluginInstaller(client: client));
      await manager.installFromUrl('https://github.com/user/repo');
      client.manifestVersion = '2.0.0';

      await manager.maybeCheckForUpdatesAutomatically(
          settings: AppSettings.instance);

      expect(manager.lastKnownUpdates, isEmpty);
      expect(AppSettings.instance.lastPluginUpdateCheckAt, isNull);
    });

    test('runs and caches results when enabled and never checked before '
        '(first run is always due)', () async {
      AppSettings.instance.autoUpdateCheckEnabled = true;
      final client =
          _RoutingClient(manifestVersion: '1.0.0', zipVersion: '1.0.0');
      final manager = PluginManager(installer: PluginInstaller(client: client));
      await manager.installFromUrl('https://github.com/user/repo');
      client.manifestVersion = '2.0.0';
      final now = DateTime(2026, 8, 16);

      await manager.maybeCheckForUpdatesAutomatically(
          settings: AppSettings.instance, now: now);

      expect(manager.lastKnownUpdates, hasLength(1));
      expect(manager.lastKnownUpdates.single.pluginId, 'sample_plugin');
      expect(AppSettings.instance.lastPluginUpdateCheckAt, now);
    });

    test('is a no-op when enabled but not yet due', () async {
      AppSettings.instance.autoUpdateCheckEnabled = true;
      AppSettings.instance.autoUpdateCheckIntervalDays = 3;
      final now = DateTime(2026, 8, 16);
      AppSettings.instance.lastPluginUpdateCheckAt =
          now.subtract(const Duration(days: 1));
      final client =
          _RoutingClient(manifestVersion: '1.0.0', zipVersion: '1.0.0');
      final manager = PluginManager(installer: PluginInstaller(client: client));
      await manager.installFromUrl('https://github.com/user/repo');
      client.manifestVersion = '2.0.0';

      await manager.maybeCheckForUpdatesAutomatically(
          settings: AppSettings.instance, now: now);

      expect(manager.lastKnownUpdates, isEmpty,
          reason: 'not due yet, so no real check should have run');
    });

    test('runs again once the interval has actually elapsed', () async {
      AppSettings.instance.autoUpdateCheckEnabled = true;
      AppSettings.instance.autoUpdateCheckIntervalDays = 3;
      final now = DateTime(2026, 8, 16);
      AppSettings.instance.lastPluginUpdateCheckAt =
          now.subtract(const Duration(days: 4));
      final client =
          _RoutingClient(manifestVersion: '1.0.0', zipVersion: '1.0.0');
      final manager = PluginManager(installer: PluginInstaller(client: client));
      await manager.installFromUrl('https://github.com/user/repo');
      client.manifestVersion = '2.0.0';

      await manager.maybeCheckForUpdatesAutomatically(
          settings: AppSettings.instance, now: now);

      expect(manager.lastKnownUpdates, hasLength(1));
      expect(AppSettings.instance.lastPluginUpdateCheckAt, now);
    });

    test('stamps lastPluginUpdateCheckAt even when the check finds '
        'nothing — "checked, found nothing" is still a completed check',
        () async {
      AppSettings.instance.autoUpdateCheckEnabled = true;
      final client =
          _RoutingClient(manifestVersion: '1.0.0', zipVersion: '1.0.0');
      final manager = PluginManager(installer: PluginInstaller(client: client));
      await manager.installFromUrl('https://github.com/user/repo');
      final now = DateTime(2026, 8, 16);

      await manager.maybeCheckForUpdatesAutomatically(
          settings: AppSettings.instance, now: now);

      expect(manager.lastKnownUpdates, isEmpty);
      expect(AppSettings.instance.lastPluginUpdateCheckAt, now);
    });
  });

  group('maybeRunHeartbeatsAutomatically (item 28, "no heartbeat for a '
      'silently-hung plugin")', () {
    // No external plugin needs to be installed for these — they cover the
    // due/enabled gating and timestamp-stamping logic (identical shape to
    // maybeCheckForUpdatesAutomatically's own group above), not what
    // happens to an individual plugin's heartbeat call, which
    // test/plugin_system_test.dart's dedicated "runHeartbeats" group
    // already covers with real dart_eval plugin fixtures. With zero
    // installed plugins, runHeartbeats() itself is a guaranteed no-op
    // (nothing for _enabled() to loop over), so any records or timestamp
    // changes observed here come purely from the gating logic.
    test('is a no-op when disabled, even if due', () async {
      AppSettings.instance.pluginHeartbeatEnabled = false;
      final manager = PluginManager();

      await manager.maybeRunHeartbeatsAutomatically(
          settings: AppSettings.instance);

      expect(AppSettings.instance.lastPluginHeartbeatAt, isNull);
    });

    test('runs and stamps the timestamp when enabled and never checked '
        'before (first run is always due)', () async {
      AppSettings.instance.pluginHeartbeatEnabled = true;
      final manager = PluginManager();
      final now = DateTime(2026, 8, 16);

      await manager.maybeRunHeartbeatsAutomatically(
          settings: AppSettings.instance, now: now);

      expect(AppSettings.instance.lastPluginHeartbeatAt, now);
    });

    test('is a no-op when enabled but not yet due', () async {
      AppSettings.instance.pluginHeartbeatEnabled = true;
      AppSettings.instance.pluginHeartbeatIntervalMinutes = 15;
      final now = DateTime(2026, 8, 16);
      final lastCheck = now.subtract(const Duration(minutes: 5));
      AppSettings.instance.lastPluginHeartbeatAt = lastCheck;
      final manager = PluginManager();

      await manager.maybeRunHeartbeatsAutomatically(
          settings: AppSettings.instance, now: now);

      expect(AppSettings.instance.lastPluginHeartbeatAt, lastCheck,
          reason: 'not due yet, so the timestamp should be untouched');
    });

    test('runs again once the interval has actually elapsed', () async {
      AppSettings.instance.pluginHeartbeatEnabled = true;
      AppSettings.instance.pluginHeartbeatIntervalMinutes = 15;
      final now = DateTime(2026, 8, 16);
      AppSettings.instance.lastPluginHeartbeatAt =
          now.subtract(const Duration(minutes: 20));
      final manager = PluginManager();

      await manager.maybeRunHeartbeatsAutomatically(
          settings: AppSettings.instance, now: now);

      expect(AppSettings.instance.lastPluginHeartbeatAt, now);
    });

    test('stamps lastPluginHeartbeatAt even when there is nothing to check '
        '— "checked, found nothing" is still a completed check', () async {
      AppSettings.instance.pluginHeartbeatEnabled = true;
      final manager = PluginManager();
      final now = DateTime(2026, 8, 16);

      await manager.maybeRunHeartbeatsAutomatically(
          settings: AppSettings.instance, now: now);

      expect(manager.sandbox.healthRecords, isEmpty);
      expect(AppSettings.instance.lastPluginHeartbeatAt, now);
    });
  });

  group('updatePlugin', () {
    test('throws for a plugin id that is not installed', () async {
      final manager = PluginManager(
        installer: PluginInstaller(
          client: _RoutingClient(manifestVersion: '1.0.0', zipVersion: '1.0.0'),
        ),
      );

      await expectLater(
        manager.updatePlugin('does_not_exist'),
        throwsA(isA<PluginInstallException>()),
      );
    });

    test('re-downloads and replaces the plugin with the newly published '
        'version', () async {
      final client =
          _RoutingClient(manifestVersion: '1.0.0', zipVersion: '1.0.0');
      final manager = PluginManager(installer: PluginInstaller(client: client));
      await manager.installFromUrl('https://github.com/user/repo');
      expect(manager.byId('sample_plugin')!.version, '1.0.0');

      client.zipVersion = '2.0.0';
      final updated = await manager.updatePlugin('sample_plugin');

      expect(updated.version, '2.0.0');
      expect(manager.byId('sample_plugin')!.version, '2.0.0');
      // Still exactly one entry for this id — updating must replace, not
      // duplicate, the managed plugin.
      expect(manager.plugins.where((p) => p.id == 'sample_plugin'), hasLength(1));
    });

    test('a previously-disabled plugin stays disabled after updating — '
        'update must not silently re-enable it', () async {
      final client =
          _RoutingClient(manifestVersion: '1.0.0', zipVersion: '1.0.0');
      final manager = PluginManager(installer: PluginInstaller(client: client));
      await manager.installFromUrl('https://github.com/user/repo');
      await manager.disablePlugin(manager.byId('sample_plugin')!);
      expect(manager.byId('sample_plugin')!.enabled, isFalse);

      client.zipVersion = '2.0.0';
      final updated = await manager.updatePlugin('sample_plugin');

      expect(updated.version, '2.0.0');
      expect(updated.enabled, isFalse);
    });

    test('a previously-enabled plugin stays enabled after updating',
        () async {
      final client =
          _RoutingClient(manifestVersion: '1.0.0', zipVersion: '1.0.0');
      final manager = PluginManager(installer: PluginInstaller(client: client));
      await manager.installFromUrl('https://github.com/user/repo');
      expect(manager.byId('sample_plugin')!.enabled, isTrue);

      client.zipVersion = '2.0.0';
      final updated = await manager.updatePlugin('sample_plugin');

      expect(updated.enabled, isTrue);
      expect(updated.initialized, isTrue);
    });

    group('backup-before-update / rollback (item 29)', () {
      test('a failed update download rolls back to the previous working '
          'version, leaving the plugin fully functional rather than a '
          'broken record with unregistered services', () async {
        final client =
            _FailOnUpdateClient(manifestVersion: '1.0.0', zipVersion: '1.0.0');
        final manager =
            PluginManager(installer: PluginInstaller(client: client));
        await manager.installFromUrl('https://github.com/user/repo');
        expect(manager.byId('sample_plugin')!.version, '1.0.0');

        client.failZipDownload = true;

        await expectLater(
          manager.updatePlugin('sample_plugin'),
          throwsA(isA<PluginInstallException>()),
        );

        final rolledBack = manager.byId('sample_plugin');
        expect(rolledBack, isNotNull);
        expect(rolledBack!.version, '1.0.0');
        expect(rolledBack.initialized, isTrue);
        // Exactly one entry — a failed-then-rolled-back update must not
        // leave a stale broken record alongside a restored one.
        expect(manager.plugins.where((p) => p.id == 'sample_plugin'),
            hasLength(1));
      });

      test('the rollback error message names the original failure', () async {
        final client =
            _FailOnUpdateClient(manifestVersion: '1.0.0', zipVersion: '1.0.0');
        final manager =
            PluginManager(installer: PluginInstaller(client: client));
        await manager.installFromUrl('https://github.com/user/repo');
        client.failZipDownload = true;

        await expectLater(
          manager.updatePlugin('sample_plugin'),
          throwsA(isA<PluginInstallException>().having(
            (e) => e.toString(),
            'message',
            allOf(contains('rolled back'), contains('500')),
          )),
        );
      });

      test('after a rolled-back update, a subsequent successful update '
          'still works normally — the plugin is not left in some '
          'half-updated limbo', () async {
        final client =
            _FailOnUpdateClient(manifestVersion: '1.0.0', zipVersion: '1.0.0');
        final manager =
            PluginManager(installer: PluginInstaller(client: client));
        await manager.installFromUrl('https://github.com/user/repo');

        client.failZipDownload = true;
        await expectLater(
          manager.updatePlugin('sample_plugin'),
          throwsA(isA<PluginInstallException>()),
        );

        client.failZipDownload = false;
        client.zipVersion = '2.0.0';
        final updated = await manager.updatePlugin('sample_plugin');

        expect(updated.version, '2.0.0');
        expect(manager.byId('sample_plugin')!.version, '2.0.0');
      });
    });
  });
}
