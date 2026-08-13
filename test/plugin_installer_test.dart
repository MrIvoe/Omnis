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
}
