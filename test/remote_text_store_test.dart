import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omnis/core/remote_text_store.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Fake path_provider that returns a temp directory, same pattern as
/// playlist_store_test.dart/plugin_installer_test.dart.
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String tempDir;
  _FakePathProvider(this.tempDir);

  @override
  Future<String?> getApplicationSupportPath() async => tempDir;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late String tempDir;

  setUp(() async {
    tempDir = (await Directory.systemTemp.createTemp('omnis_remote_text_test'))
        .path;
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
  });

  tearDown(() async {
    final dir = Directory(tempDir);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  });

  group('fetchFromUrl', () {
    test('returns the response body on a 200', () async {
      final store = RemoteTextStore(
        'themes',
        client: MockClient((request) async => http.Response('id: x', 200)),
      );

      final body = await store.fetchFromUrl('https://example.com/theme.yaml');

      expect(body, 'id: x');
    });

    test('a non-200 response throws RemoteTextStoreException', () async {
      final store = RemoteTextStore(
        'themes',
        client: MockClient((request) async => http.Response('nope', 404)),
      );

      await expectLater(
        store.fetchFromUrl('https://example.com/missing.yaml'),
        throwsA(isA<RemoteTextStoreException>().having(
            (e) => e.message, 'message', contains('404'))),
      );
    });

    test('a network failure throws RemoteTextStoreException, not the raw '
        'exception', () async {
      final store = RemoteTextStore(
        'themes',
        client: MockClient((request) => throw const SocketException('down')),
      );

      await expectLater(
        store.fetchFromUrl('https://example.com/theme.yaml'),
        throwsA(isA<RemoteTextStoreException>()),
      );
    });
  });

  group('readFromFile', () {
    test('reads a real local file', () async {
      final file = File(p.join(tempDir, 'local.yaml'));
      await file.writeAsString('id: local');
      final store = RemoteTextStore('themes');

      final content = await store.readFromFile(file.path);

      expect(content, 'id: local');
    });

    test('a missing file throws RemoteTextStoreException, not the raw '
        'exception', () async {
      final store = RemoteTextStore('themes');

      await expectLater(
        store.readFromFile(p.join(tempDir, 'does_not_exist.yaml')),
        throwsA(isA<RemoteTextStoreException>()),
      );
    });
  });

  group('persist / listInstalledRaw / uninstall round trip', () {
    test('persist writes under the store\'s own subdirectory, and '
        'listInstalledRaw finds it back', () async {
      final store = RemoteTextStore('themes');

      await store.persist('my_theme', 'id: my_theme\ncolor: blue');

      expect(await Directory(p.join(tempDir, 'themes')).exists(), isTrue);
      final listed = await store.listInstalledRaw();
      expect(listed, ['id: my_theme\ncolor: blue']);
    });

    test('two stores with different subdirectories never see each other\'s '
        'files', () async {
      final themes = RemoteTextStore('themes');
      final layouts = RemoteTextStore('layouts');

      await themes.persist('a', 'theme content');
      await layouts.persist('a', 'layout content');

      expect(await themes.listInstalledRaw(), ['theme content']);
      expect(await layouts.listInstalledRaw(), ['layout content']);
    });

    test('persisting the same id twice overwrites rather than duplicating',
        () async {
      final store = RemoteTextStore('themes');

      await store.persist('my_theme', 'version 1');
      await store.persist('my_theme', 'version 2');

      expect(await store.listInstalledRaw(), ['version 2']);
    });

    test('uninstall removes the file; a repeat uninstall is a no-op',
        () async {
      final store = RemoteTextStore('themes');
      await store.persist('my_theme', 'content');
      expect(await store.listInstalledRaw(), hasLength(1));

      await store.uninstall('my_theme');
      expect(await store.listInstalledRaw(), isEmpty);

      await expectLater(store.uninstall('my_theme'), completes);
    });

    test('listInstalledRaw only considers .yaml/.yml/.json files', () async {
      final store = RemoteTextStore('themes');
      await store.persist('real_theme', 'id: real');
      // A stray non-matching file dropped in the same directory by
      // something else must not be picked up as an installed entry.
      final stray = File(p.join(tempDir, 'themes', 'notes.txt'));
      await stray.create(recursive: true);
      await stray.writeAsString('not a theme');

      final listed = await store.listInstalledRaw();

      expect(listed, ['id: real']);
    });

    test('an id with filesystem-unsafe characters is sanitized to a safe '
        'filename, not rejected or written unsafely', () async {
      final store = RemoteTextStore('themes');

      await store.persist('../../etc/passwd', 'malicious id, safe content');

      // The sanitized file must land inside the store's own directory —
      // nowhere else — and still round-trip correctly.
      final files = await Directory(p.join(tempDir, 'themes')).list().toList();
      expect(files, hasLength(1));
      expect(p.dirname(files.single.path),
          p.normalize(p.join(tempDir, 'themes')));
      expect(await store.listInstalledRaw(), ['malicious id, safe content']);
    });

    test('listInstalledRaw returns empty (not an error) when the '
        'subdirectory was never created', () async {
      final store = RemoteTextStore('never_used');
      expect(await store.listInstalledRaw(), isEmpty);
    });
  });
}
