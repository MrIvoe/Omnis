import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/core/plugin_installer.dart';
import 'package:omnis/core/plugin_manager.dart';
import 'package:omnis/core/sandbox.dart';
import 'package:omnis/ui/plugins_page.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// Same host-routing fake client plugin_updates_test.dart uses: zip
/// downloads (`codeload.github.com`) vs. manifest-only fetches
/// (`raw.githubusercontent.com`), independently versioned.
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

/// A bare pump() doesn't give a real (MockClient-backed, dart:io-driven)
/// network Future — even inside tester.runAsync() — a chance to actually
/// resolve before the next frame is checked. A real delay interleaved
/// with pumps does; same pattern home_dashboard_page_test.dart's own
/// `_settle` uses for the same underlying reason.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await Future<void>.delayed(const Duration(milliseconds: 300));
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late String tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.initialize();
    tempDir =
        (await Directory.systemTemp.createTemp('omnis_plugins_page_test'))
            .path;
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
  });

  tearDown(() async {
    final dir = Directory(tempDir);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  });

  testWidgets('"Check for updates" is absent with no external plugins '
      'installed', (tester) async {
    final manager = PluginManager();

    await tester.pumpWidget(MaterialApp(
      home: PluginsPage(pluginManager: manager, sandbox: PluginSandbox()),
    ));
    await tester.pump();

    expect(find.text('Check for updates'), findsNothing);
  });

  // The remaining tests all drive PluginManager.checkForUpdates()/
  // updatePlugin() from a button tap — real dart:io http calls (via
  // MockClient) whose Futures never resolve through testWidgets()'s
  // default fake-async zone, only a plain pump()/pumpAndSettle(). Wrapped
  // in tester.runAsync(), same fix home_dashboard_page_test.dart already
  // documents for the same underlying cause (real async I/O, fake clock).

  testWidgets('checking for updates shows an "Update available" banner '
      'with an Update button', (tester) async {
    await tester.runAsync(() async {
      final client =
          _RoutingClient(manifestVersion: '1.0.0', zipVersion: '1.0.0');
      final manager =
          PluginManager(installer: PluginInstaller(client: client));
      await manager.installFromUrl('https://github.com/user/repo');
      client.manifestVersion = '2.0.0';

      await tester.pumpWidget(MaterialApp(
        home: PluginsPage(pluginManager: manager, sandbox: PluginSandbox()),
      ));
      await tester.pump();

      expect(find.text('Check for updates'), findsOneWidget);
      await tester.tap(find.text('Check for updates'));
      await _settle(tester);

      expect(find.text('Update available: v2.0.0'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Update'), findsOneWidget);
    });
  });

  testWidgets('checking for updates with nothing newer shows "Everything '
      'is up to date."', (tester) async {
    await tester.runAsync(() async {
      final client =
          _RoutingClient(manifestVersion: '1.0.0', zipVersion: '1.0.0');
      final manager =
          PluginManager(installer: PluginInstaller(client: client));
      await manager.installFromUrl('https://github.com/user/repo');

      await tester.pumpWidget(MaterialApp(
        home: PluginsPage(pluginManager: manager, sandbox: PluginSandbox()),
      ));
      await tester.pump();
      await tester.tap(find.text('Check for updates'));
      await _settle(tester);

      expect(find.text('Everything is up to date.'), findsOneWidget);
      expect(find.textContaining('Update available'), findsNothing);
    });
  });

  testWidgets('tapping Update installs the newer version and the banner '
      'disappears', (tester) async {
    await tester.runAsync(() async {
      final client =
          _RoutingClient(manifestVersion: '1.0.0', zipVersion: '1.0.0');
      final manager =
          PluginManager(installer: PluginInstaller(client: client));
      await manager.installFromUrl('https://github.com/user/repo');
      client.manifestVersion = '2.0.0';

      await tester.pumpWidget(MaterialApp(
        home: PluginsPage(pluginManager: manager, sandbox: PluginSandbox()),
      ));
      await tester.pump();
      await tester.tap(find.text('Check for updates'));
      await _settle(tester);
      expect(find.text('Update available: v2.0.0'), findsOneWidget);

      // The manifest check said v2.0.0 is available; the actual zip
      // download that Update triggers must independently reflect that
      // same version for the install to land on v2.0.0, not silently
      // stay at v1.0.0.
      client.zipVersion = '2.0.0';
      // Below the fold: the "Installed plugins" section (with its update
      // banner) sits under the catalog/installer cards above it.
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Update'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Update'));
      await _settle(tester);

      expect(find.textContaining('Updated Sample Plugin to v2.0.0'),
          findsOneWidget);
      expect(find.textContaining('Update available'), findsNothing);
      expect(manager.byId('sample_plugin')!.version, '2.0.0');
    });
  });
}
