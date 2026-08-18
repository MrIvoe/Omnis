import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omnis/core/plugin_installer.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Fake path_provider that returns a temp directory, same pattern as
/// playlist_store_test.dart/library_store_test.dart.
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String tempDir;
  _FakePathProvider(this.tempDir);

  @override
  Future<String?> getApplicationSupportPath() async => tempDir;
}

/// Builds real zip bytes from a name -> content map — every value ends up
/// as UTF-8 text content, which is all these tests need (manifests, a
/// stub entrypoint, an artifact from a path-traversal attempt).
List<int> _buildZip(Map<String, String> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    final bytes = utf8.encode(entry.value);
    archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
  }
  return ZipEncoder().encode(archive)!;
}

/// A streaming fake client that (unlike `MockClient`/`http.Response.bytes`,
/// which always forces `contentLength` to the actual body length) can
/// report a `contentLength` independent of the real byte count — needed to
/// simulate a server that lies about (or omits) Content-Length, which the
/// size-limit tests below need to exercise both the upfront header check
/// and the mid-stream actual-bytes check separately.
class _FakeStreamingClient extends http.BaseClient {
  final List<int> bytes;
  final int? declaredContentLength;

  _FakeStreamingClient(this.bytes, {this.declaredContentLength});

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      Stream.value(bytes),
      200,
      contentLength: declaredContentLength,
    );
  }
}

const _validManifest = '''
id: sample_plugin
name: Sample Plugin
description: A test plugin
version: 1.0.0
author: Tester
entrypoint: plugin.dart
hooks:
  - onTrackStart
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late String tempDir;

  setUp(() async {
    tempDir =
        (await Directory.systemTemp.createTemp('omnis_plugin_installer_test'))
            .path;
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
  });

  tearDown(() async {
    final dir = Directory(tempDir);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  });

  http.Client clientReturning(List<int> zipBytes, {int statusCode = 200}) =>
      MockClient((request) async => http.Response.bytes(zipBytes, statusCode));

  group('zip-slip guard', () {
    test(
        'a "../" path-traversal entry is rejected and nothing is written '
        'outside the plugin directory', () async {
      final zip = _buildZip({
        'repo-main/omnis_plugin.yaml': _validManifest,
        'repo-main/plugin.dart': '// entrypoint',
        // The attack: this entry's stored path climbs out of the
        // extraction directory once the "repo-main/" wrapper is
        // stripped off.
        'repo-main/../../../evil.txt': 'pwned',
      });
      final installer = PluginInstaller(client: clientReturning(zip));

      await expectLater(
        installer.installFromUrl('https://github.com/user/repo'),
        throwsA(isA<PluginInstallException>().having(
          (e) => e.message,
          'message',
          contains('path traversal'),
        )),
      );

      // The attack's payload must not exist anywhere under tempDir.
      final escaped = await Directory(tempDir)
          .list(recursive: true)
          .any((e) => p.basename(e.path) == 'evil.txt');
      expect(escaped, isFalse);
    });

    test('an absolute-path entry is rejected', () async {
      final absolute = Platform.isWindows ? 'C:/evil.txt' : '/etc/evil.txt';
      final zip = _buildZip({
        'repo-main/omnis_plugin.yaml': _validManifest,
        'repo-main/plugin.dart': '// entrypoint',
        'repo-main/$absolute': 'pwned',
      });
      final installer = PluginInstaller(client: clientReturning(zip));

      await expectLater(
        installer.installFromUrl('https://github.com/user/repo'),
        throwsA(isA<PluginInstallException>()),
      );
    });

    test(
        'a manifest entrypoint referencing "../" is rejected even though '
        'the zip entries themselves are safe', () async {
      final zip = _buildZip({
        'repo-main/omnis_plugin.yaml': '''
id: sample_plugin
name: Sample Plugin
description: A test plugin
version: 1.0.0
author: Tester
entrypoint: ../../../etc/passwd
hooks:
  - onTrackStart
''',
        'repo-main/plugin.dart': '// entrypoint',
      });
      final installer = PluginInstaller(client: clientReturning(zip));

      await expectLater(
        installer.installFromUrl('https://github.com/user/repo'),
        throwsA(isA<PluginInstallException>().having(
          (e) => e.message,
          'message',
          contains('not allowed to reference paths'),
        )),
      );
    });
  });

  group('happy path', () {
    test(
        'installs a repo-wrapped zip, extracts it, and parses the manifest',
        () async {
      final zip = _buildZip({
        'my-plugin-main/omnis_plugin.yaml': _validManifest,
        'my-plugin-main/plugin.dart': '// entrypoint',
      });
      final installer = PluginInstaller(client: clientReturning(zip));

      final result =
          await installer.installFromUrl('https://github.com/user/my-plugin');

      expect(result.manifest.id, 'sample_plugin');
      expect(result.manifest.entrypoint, 'plugin.dart');
      expect(await File(result.entrypointPath).exists(), isTrue);
      expect(await File(result.entrypointPath).readAsString(),
          '// entrypoint');
    });

    test('a zip with no wrapper directory (files at the root) also installs',
        () async {
      final zip = _buildZip({
        'omnis_plugin.yaml': _validManifest,
        'plugin.dart': '// entrypoint',
      });
      final installer = PluginInstaller(client: clientReturning(zip));

      final result =
          await installer.installFromUrl('https://github.com/user/repo');

      expect(result.manifest.id, 'sample_plugin');
    });

    test(
        'a catalog install (.../tree/branch/subfolder) only extracts that '
        "subfolder's files", () async {
      final zip = _buildZip({
        'Omnis-Plugins-main/sample_logger/omnis_plugin.yaml': _validManifest,
        'Omnis-Plugins-main/sample_logger/plugin.dart': '// sample_logger',
        // A sibling plugin in the same catalog repo — must not be
        // extracted or considered part of this install.
        'Omnis-Plugins-main/other_plugin/omnis_plugin.yaml': _validManifest,
        'Omnis-Plugins-main/other_plugin/plugin.dart': '// other_plugin',
      });
      final installer = PluginInstaller(client: clientReturning(zip));

      final result = await installer.installFromUrl(
          'https://github.com/MrIvoe/Omnis-Plugins/tree/main/sample_logger');

      expect(await File(result.entrypointPath).readAsString(),
          '// sample_logger');
      final installedFiles =
          await Directory(result.directory).list(recursive: true).toList();
      expect(installedFiles.any((e) => e.path.contains('other_plugin')),
          isFalse);
    });

    test('reinstalling the same plugin replaces its old files', () async {
      final firstZip = _buildZip({
        'my-plugin-main/omnis_plugin.yaml': _validManifest,
        'my-plugin-main/plugin.dart': '// version 1',
        'my-plugin-main/stale_file.txt': 'should be gone after reinstall',
      });
      final installer1 = PluginInstaller(client: clientReturning(firstZip));
      final first =
          await installer1.installFromUrl('https://github.com/user/my-plugin');
      expect(await File(p.join(first.directory, 'stale_file.txt')).exists(),
          isTrue);

      final secondZip = _buildZip({
        'my-plugin-main/omnis_plugin.yaml': _validManifest,
        'my-plugin-main/plugin.dart': '// version 2',
      });
      final installer2 = PluginInstaller(client: clientReturning(secondZip));
      final second =
          await installer2.installFromUrl('https://github.com/user/my-plugin');

      expect(second.directory, first.directory);
      expect(await File(p.join(second.directory, 'stale_file.txt')).exists(),
          isFalse);
      expect(await File(second.entrypointPath).readAsString(), '// version 2');
    });
  });

  group('bare-repo default-branch fallback (main -> master)', () {
    test('a bare repo URL tries the codeload main zip first, and only '
        'falls back to master on a 404 for that specific ref', () async {
      final zip = _buildZip({
        'repo-master/omnis_plugin.yaml': _validManifest,
        'repo-master/plugin.dart': '// entrypoint',
      });
      final requestedUrls = <Uri>[];
      final installer = PluginInstaller(
        client: MockClient((request) async {
          requestedUrls.add(request.url);
          if (request.url.toString().contains('/main')) {
            return http.Response('Not Found', 404);
          }
          return http.Response.bytes(zip, 200);
        }),
      );

      final result =
          await installer.installFromUrl('https://github.com/user/repo');

      expect(result.manifest.id, 'sample_plugin');
      expect(requestedUrls, [
        Uri.parse('https://codeload.github.com/user/repo/zip/refs/heads/main'),
        Uri.parse(
            'https://codeload.github.com/user/repo/zip/refs/heads/master'),
      ]);
    });

    test('a bare repo URL never tries master when main already succeeds',
        () async {
      final zip = _buildZip({
        'repo-main/omnis_plugin.yaml': _validManifest,
        'repo-main/plugin.dart': '// entrypoint',
      });
      final requestedUrls = <Uri>[];
      final installer = PluginInstaller(
        client: MockClient((request) async {
          requestedUrls.add(request.url);
          return http.Response.bytes(zip, 200);
        }),
      );

      await installer.installFromUrl('https://github.com/user/repo');

      expect(requestedUrls, hasLength(1));
      expect(requestedUrls.single.toString(), contains('/main'));
    });

    test('a 404 on both main and master surfaces as a real download '
        'failure, not silently as "missing manifest"', () async {
      final installer = PluginInstaller(
        client: MockClient((request) async => http.Response('Not Found', 404)),
      );

      await expectLater(
        installer.installFromUrl('https://github.com/user/repo'),
        throwsA(isA<PluginInstallException>().having(
            (e) => e.message, 'message', contains('404'))),
      );
    });

    test('an explicit .../tree/branch URL never tries a second branch — '
        'the caller already said exactly which one it means', () async {
      final requestedUrls = <Uri>[];
      final installer = PluginInstaller(
        client: MockClient((request) async {
          requestedUrls.add(request.url);
          return http.Response('Not Found', 404);
        }),
      );

      await expectLater(
        installer.installFromUrl('https://github.com/user/repo/tree/develop'),
        throwsA(isA<PluginInstallException>()),
      );
      expect(requestedUrls, hasLength(1));
    });
  });

  group('validation failures', () {
    test('an empty zip is rejected', () async {
      final zip = _buildZip({});
      final installer = PluginInstaller(client: clientReturning(zip));

      await expectLater(
        installer.installFromUrl('https://github.com/user/repo'),
        throwsA(isA<PluginInstallException>().having(
            (e) => e.message, 'message', contains('empty'))),
      );
    });

    test('a zip with no omnis_plugin.yaml is rejected', () async {
      final zip = _buildZip({'repo-main/plugin.dart': '// entrypoint'});
      final installer = PluginInstaller(client: clientReturning(zip));

      await expectLater(
        installer.installFromUrl('https://github.com/user/repo'),
        throwsA(isA<PluginInstallException>().having(
            (e) => e.message, 'message', contains('manifest'))),
      );
    });

    test('a manifest pointing at a missing entrypoint file is rejected',
        () async {
      final zip = _buildZip({'repo-main/omnis_plugin.yaml': _validManifest});
      final installer = PluginInstaller(client: clientReturning(zip));

      await expectLater(
        installer.installFromUrl('https://github.com/user/repo'),
        throwsA(isA<PluginInstallException>().having(
            (e) => e.message, 'message', contains('does not exist'))),
      );
    });

    test('a non-200 download response is reported, not silently ignored',
        () async {
      final installer =
          PluginInstaller(client: clientReturning(const [], statusCode: 404));

      await expectLater(
        installer.installFromUrl('https://github.com/user/repo'),
        throwsA(isA<PluginInstallException>().having(
            (e) => e.message, 'message', contains('404'))),
      );
    });

    test('an unsupported URL is rejected before any network call', () async {
      var called = false;
      final installer = PluginInstaller(
        client: MockClient((request) async {
          called = true;
          return http.Response('', 200);
        }),
      );

      await expectLater(
        installer.installFromUrl('not a url at all'),
        throwsA(isA<PluginInstallException>()),
      );
      expect(called, isFalse);
    });
  });

  group('size limits', () {
    test(
        'a download whose declared Content-Length exceeds the cap is '
        'rejected without streaming the body', () async {
      final installer = PluginInstaller(
        maxDownloadBytes: 1024,
        client: _FakeStreamingClient(List<int>.filled(10, 0),
            declaredContentLength: 2048),
      );

      await expectLater(
        installer.installFromUrl('https://github.com/user/repo'),
        throwsA(isA<PluginInstallException>().having(
            (e) => e.message, 'message', contains('too large'))),
      );
    });

    test(
        'a download whose actual bytes exceed the cap (no honest '
        'Content-Length) is aborted mid-stream', () async {
      final installer = PluginInstaller(
        maxDownloadBytes: 1024,
        // No declaredContentLength — simulates a server that omits the
        // header entirely (e.g. chunked transfer encoding), so the
        // upfront check can't catch it and the mid-stream running-total
        // check has to.
        client: _FakeStreamingClient(List<int>.filled(4096, 0)),
      );

      await expectLater(
        installer.installFromUrl('https://github.com/user/repo'),
        throwsA(isA<PluginInstallException>().having(
            (e) => e.message, 'message', contains('size limit'))),
      );
    });

    test(
        'a zip whose declared (uncompressed) entry sizes exceed the '
        'extraction cap is rejected before decompressing anything',
        () async {
      final archive = Archive()
        ..addFile(ArchiveFile('repo-main/omnis_plugin.yaml',
            _validManifest.length, utf8.encode(_validManifest)))
        // The declared `size` (second constructor arg) is independent of
        // the actual content bytes supplied — this simulates zip metadata
        // claiming a huge uncompressed size without needing to really
        // produce that much data.
        ..addFile(ArchiveFile('repo-main/bomb.bin', 10 * 1024 * 1024,
            utf8.encode('tiny actual content')));
      final zip = ZipEncoder().encode(archive)!;
      final installer =
          PluginInstaller(maxExtractedBytes: 1024, client: clientReturning(zip));

      await expectLater(
        installer.installFromUrl('https://github.com/user/repo'),
        throwsA(isA<PluginInstallException>().having(
            (e) => e.message, 'message', contains('extract to more than'))),
      );
    });

    test(
        'a zip that lies about a small declared size but actually '
        'decompresses to more is still caught during extraction',
        () async {
      final bigContent = utf8.encode('x' * 5000);
      final archive = Archive()
        ..addFile(ArchiveFile('repo-main/omnis_plugin.yaml',
            _validManifest.length, utf8.encode(_validManifest)))
        // Declared size (10 bytes) undersells the real content (5000
        // bytes) — the pass-one declared-size check alone would let this
        // through; the pass-two actual-bytes check during extraction must
        // still catch it.
        ..addFile(ArchiveFile('repo-main/bomb.bin', 10, bigContent));
      final zip = ZipEncoder().encode(archive)!;
      final installer =
          PluginInstaller(maxExtractedBytes: 1000, client: clientReturning(zip));

      await expectLater(
        installer.installFromUrl('https://github.com/user/repo'),
        throwsA(isA<PluginInstallException>().having(
            (e) => e.message, 'message', contains('extracted more than'))),
      );
    });

    test('a normal small install still succeeds under the real default caps',
        () async {
      final zip = _buildZip({
        'my-plugin-main/omnis_plugin.yaml': _validManifest,
        'my-plugin-main/plugin.dart': '// entrypoint',
      });
      final installer = PluginInstaller(client: clientReturning(zip));

      final result =
          await installer.installFromUrl('https://github.com/user/my-plugin');

      expect(result.manifest.id, 'sample_plugin');
    });
  });

  group('listInstalled/uninstall', () {
    test('a successful install is found by listInstalled and removed by '
        'uninstall', () async {
      final zip = _buildZip({
        'my-plugin-main/omnis_plugin.yaml': _validManifest,
        'my-plugin-main/plugin.dart': '// entrypoint',
      });
      final installer = PluginInstaller(client: clientReturning(zip));
      final installed =
          await installer.installFromUrl('https://github.com/user/my-plugin');

      final listed = await installer.listInstalled();
      expect(listed.any((p) => p.manifest.id == 'sample_plugin'), isTrue);

      await installer.uninstall(installed.directory);

      expect(await Directory(installed.directory).exists(), isFalse);
      final listedAfter = await installer.listInstalled();
      expect(listedAfter.any((p) => p.manifest.id == 'sample_plugin'), isFalse);
    });
  });

  group('fetchRemoteManifest (update checking)', () {
    test('hits the raw.githubusercontent.com manifest URL for a "tree" '
        'catalog-style URL, not the codeload zip endpoint', () async {
      Uri? capturedUri;
      final installer = PluginInstaller(
        client: MockClient((request) async {
          capturedUri = request.url;
          return http.Response(_validManifest, 200);
        }),
      );

      final manifest = await installer.fetchRemoteManifest(
        'https://github.com/MrIvoe/Omnis-Plugins/tree/main/sample_logger',
      );

      expect(capturedUri.toString(),
          'https://raw.githubusercontent.com/MrIvoe/Omnis-Plugins/main/'
          'sample_logger/omnis_plugin.yaml');
      expect(manifest?.id, 'sample_plugin');
      expect(manifest?.version, '1.0.0');
    });

    test('hits the raw manifest URL at the repo root for a bare repo URL',
        () async {
      Uri? capturedUri;
      final installer = PluginInstaller(
        client: MockClient((request) async {
          capturedUri = request.url;
          return http.Response(_validManifest, 200);
        }),
      );

      await installer.fetchRemoteManifest('https://github.com/user/repo');

      expect(capturedUri.toString(),
          'https://raw.githubusercontent.com/user/repo/main/'
          'omnis_plugin.yaml');
    });

    test('returns null without any network call for a direct .zip URL — '
        'there is no raw single-file location to derive from it', () async {
      var called = false;
      final installer = PluginInstaller(
        client: MockClient((request) async {
          called = true;
          return http.Response(_validManifest, 200);
        }),
      );

      final manifest = await installer
          .fetchRemoteManifest('https://example.com/plugin.zip');

      expect(manifest, isNull);
      expect(called, isFalse);
    });

    test('returns null on a non-200 response instead of throwing', () async {
      final installer = PluginInstaller(
        client: MockClient((request) async => http.Response('', 404)),
      );

      final manifest = await installer
          .fetchRemoteManifest('https://github.com/user/repo');

      expect(manifest, isNull);
    });

    test('returns null when the response body is not a valid manifest',
        () async {
      final installer = PluginInstaller(
        client: MockClient((request) async =>
            http.Response('not: [valid, yaml, manifest', 200)),
      );

      final manifest = await installer
          .fetchRemoteManifest('https://github.com/user/repo');

      expect(manifest, isNull);
    });

    test('returns null when the http call itself throws', () async {
      final installer = PluginInstaller(
        client: MockClient((request) async {
          throw Exception('network unreachable');
        }),
      );

      final manifest = await installer
          .fetchRemoteManifest('https://github.com/user/repo');

      expect(manifest, isNull);
    });

    test('a bare repo URL falls back to the master raw manifest URL when '
        'main 404s — same fallback installFromUrl uses', () async {
      final requestedUrls = <Uri>[];
      final installer = PluginInstaller(
        client: MockClient((request) async {
          requestedUrls.add(request.url);
          if (request.url.toString().endsWith('/main/omnis_plugin.yaml')) {
            return http.Response('Not Found', 404);
          }
          return http.Response(_validManifest, 200);
        }),
      );

      final manifest =
          await installer.fetchRemoteManifest('https://github.com/user/repo');

      expect(manifest?.id, 'sample_plugin');
      expect(requestedUrls, [
        Uri.parse(
            'https://raw.githubusercontent.com/user/repo/main/omnis_plugin.yaml'),
        Uri.parse(
            'https://raw.githubusercontent.com/user/repo/master/omnis_plugin.yaml'),
      ]);
    });
  });

  group('fetchCatalog (item 30)', () {
    test('hits catalog.json at the Omnis-Plugins repo root, not the '
        'manifest/zip endpoints', () async {
      Uri? capturedUri;
      final installer = PluginInstaller(
        client: MockClient((request) async {
          capturedUri = request.url;
          return http.Response(
              jsonEncode([
                {
                  'folder': 'sample_logger',
                  'name': 'Sample Logger',
                  'description': 'Logs track starts.',
                },
              ]),
              200);
        }),
      );

      final catalog = await installer.fetchCatalog();

      expect(capturedUri.toString(),
          'https://raw.githubusercontent.com/MrIvoe/Omnis-Plugins/main/'
          'catalog.json');
      expect(catalog, hasLength(1));
      expect(catalog!.single.folder, 'sample_logger');
      expect(catalog.single.name, 'Sample Logger');
      expect(catalog.single.description, 'Logs track starts.');
      expect(catalog.single.installUrl,
          'https://github.com/MrIvoe/Omnis-Plugins/tree/main/sample_logger');
    });

    test('description defaults to empty when the JSON omits it', () async {
      final installer = PluginInstaller(
        client: MockClient((request) async => http.Response(
            jsonEncode([
              {'folder': 'x', 'name': 'X'},
            ]),
            200)),
      );

      final catalog = await installer.fetchCatalog();

      expect(catalog!.single.description, '');
    });

    test('one malformed entry is skipped, not treated as a whole-fetch '
        'failure', () async {
      final installer = PluginInstaller(
        client: MockClient((request) async => http.Response(
            jsonEncode([
              {'folder': 'good', 'name': 'Good'},
              {'name': 'Missing folder'}, // malformed — no 'folder' key
              'not even a map',
            ]),
            200)),
      );

      final catalog = await installer.fetchCatalog();

      expect(catalog, hasLength(1));
      expect(catalog!.single.folder, 'good');
    });

    test('returns null on a non-200 response instead of throwing',
        () async {
      final installer = PluginInstaller(
        client: MockClient((request) async => http.Response('', 404)),
      );

      expect(await installer.fetchCatalog(), isNull);
    });

    test('returns null when the response body is not a JSON list',
        () async {
      final installer = PluginInstaller(
        client: MockClient(
            (request) async => http.Response(jsonEncode({'not': 'a list'}), 200)),
      );

      expect(await installer.fetchCatalog(), isNull);
    });

    test('returns null when the response body is not valid JSON at all',
        () async {
      final installer = PluginInstaller(
        client: MockClient((request) async => http.Response('not json', 200)),
      );

      expect(await installer.fetchCatalog(), isNull);
    });

    test('returns null, never throws, when the http call itself throws',
        () async {
      final installer = PluginInstaller(
        client: MockClient((request) async {
          throw Exception('network unreachable');
        }),
      );

      expect(await installer.fetchCatalog(), isNull);
    });
  });

  group('backupPluginDirectory / restorePluginBackup / '
      'discardPluginBackup (item 29)', () {
    Future<Directory> writePluginDir(String name,
        {String manifestVersion = '1.0.0'}) async {
      final dir = Directory(p.join(tempDir, name));
      await dir.create(recursive: true);
      await File(p.join(dir.path, 'omnis_plugin.yaml')).writeAsString('''
id: $name
name: $name
description: Test
version: $manifestVersion
author: Tester
entrypoint: plugin.dart
''');
      await File(p.join(dir.path, 'plugin.dart'))
          .writeAsString('// entrypoint for $name');
      final assetsDir = Directory(p.join(dir.path, 'assets'));
      await assetsDir.create();
      await File(p.join(assetsDir.path, 'data.txt'))
          .writeAsString('nested content');
      return dir;
    }

    test('backs up a plugin directory\'s full contents, including a '
        'nested subdirectory, to a location outside the plugin itself',
        () async {
      final installer = PluginInstaller();
      final dir = await writePluginDir('sample');

      final backupPath = await installer.backupPluginDirectory(dir.path);

      expect(backupPath, isNotNull);
      expect(backupPath, isNot(startsWith(dir.path)));
      expect(
        await File(p.join(backupPath!, 'omnis_plugin.yaml')).readAsString(),
        contains('version: 1.0.0'),
      );
      expect(
        await File(p.join(backupPath, 'assets', 'data.txt')).readAsString(),
        'nested content',
      );
    });

    test('returns null (never throws) when the source directory does not '
        'exist — nothing to back up', () async {
      final installer = PluginInstaller();

      final backupPath = await installer
          .backupPluginDirectory(p.join(tempDir, 'does_not_exist'));

      expect(backupPath, isNull);
    });

    test('restorePluginBackup replaces the target directory\'s contents '
        'exactly, discarding anything a failed update left behind',
        () async {
      final installer = PluginInstaller();
      final dir = await writePluginDir('sample', manifestVersion: '1.0.0');
      final backupPath = await installer.backupPluginDirectory(dir.path);

      // Simulate a failed update: the original gets wiped and replaced
      // with a different, partially-written new version.
      await dir.delete(recursive: true);
      await dir.create(recursive: true);
      await File(p.join(dir.path, 'omnis_plugin.yaml'))
          .writeAsString('garbage, not even valid yaml content');

      await installer.restorePluginBackup(backupPath!, dir.path);

      final manifest =
          await File(p.join(dir.path, 'omnis_plugin.yaml')).readAsString();
      expect(manifest, contains('version: 1.0.0'));
      expect(
        await File(p.join(dir.path, 'assets', 'data.txt')).readAsString(),
        'nested content',
      );
    });

    test('restorePluginBackup deletes the backup afterward — a used '
        'backup is spent, not kept for a second rollback', () async {
      final installer = PluginInstaller();
      final dir = await writePluginDir('sample');
      final backupPath = await installer.backupPluginDirectory(dir.path);

      await installer.restorePluginBackup(backupPath!, dir.path);

      expect(await Directory(backupPath).exists(), isFalse);
    });

    test('discardPluginBackup removes a backup that is no longer needed',
        () async {
      final installer = PluginInstaller();
      final dir = await writePluginDir('sample');
      final backupPath = await installer.backupPluginDirectory(dir.path);
      expect(await Directory(backupPath!).exists(), isTrue);

      await installer.discardPluginBackup(backupPath);

      expect(await Directory(backupPath).exists(), isFalse);
    });

    test('discardPluginBackup on an already-gone path is a harmless '
        'no-op', () async {
      final installer = PluginInstaller();

      await expectLater(
        installer.discardPluginBackup(p.join(tempDir, 'never_existed')),
        completes,
      );
    });
  });
}
