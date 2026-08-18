import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/sidebar_config.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String tempDir;

  _FakePathProvider(this.tempDir);

  @override
  Future<String?> getApplicationDocumentsPath() async => tempDir;

  @override
  Future<String?> getApplicationSupportPath() async => tempDir;

  @override
  Future<String?> getTemporaryPath() async => tempDir;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SidebarItem/SidebarSection JSON round-trip', () {
    test('SidebarItem toJson/fromJson', () {
      const item = SidebarItem(kind: SidebarItemKind.playlist, refId: 'p1');
      final decoded = SidebarItem.fromJson(item.toJson())!;
      expect(decoded.kind, SidebarItemKind.playlist);
      expect(decoded.refId, 'p1');
    });

    test('a malformed SidebarItem entry decodes to null', () {
      expect(SidebarItem.fromJson({'kind': 'not_a_real_kind', 'refId': 'x'}),
          isNull);
      expect(SidebarItem.fromJson({'refId': 'x'}), isNull);
    });

    test('SidebarSection toJson/fromJson preserves items and order', () {
      const section = SidebarSection(
        id: 's1',
        title: 'My playlists',
        kind: SidebarItemKind.playlist,
        items: [
          SidebarItem(kind: SidebarItemKind.playlist, refId: 'p1'),
          SidebarItem(kind: SidebarItemKind.playlist, refId: 'p2'),
        ],
      );
      final decoded = SidebarSection.fromJson(section.toJson())!;
      expect(decoded.id, 's1');
      expect(decoded.title, 'My playlists');
      expect(decoded.kind, SidebarItemKind.playlist);
      expect(decoded.items.map((i) => i.refId), ['p1', 'p2']);
    });

    test('a malformed SidebarSection entry decodes to null', () {
      expect(SidebarSection.fromJson({'title': 'No id'}), isNull);
    });

    test('a corrupt item inside a valid section is skipped, not fatal', () {
      final decoded = SidebarSection.fromJson({
        'id': 's1',
        'title': 'Mixed',
        'kind': 'playlist',
        'items': [
          {'kind': 'playlist', 'refId': 'good'},
          {'kind': 'not_real', 'refId': 'bad'},
        ],
      })!;
      expect(decoded.items.map((i) => i.refId), ['good']);
    });
  });

  group('defaultSidebarSections', () {
    test('seeds exactly the two spec-named sections, both empty', () {
      final defaults = defaultSidebarSections();
      expect(defaults, hasLength(2));
      expect(defaults[0].kind, SidebarItemKind.playlist);
      expect(defaults[0].items, isEmpty);
      expect(defaults[1].kind, SidebarItemKind.mood);
      expect(defaults[1].items, isEmpty);
    });
  });

  group('SidebarConfigStore', () {
    late String tempDir;

    setUp(() async {
      tempDir =
          (await Directory.systemTemp.createTemp('omnis_sidebar_test')).path;
      PathProviderPlatform.instance = _FakePathProvider(tempDir);
      SidebarConfigStore.instance.resetForTesting();
    });

    test('loading with no saved file returns the defaults, not empty',
        () async {
      final loaded = await SidebarConfigStore.instance.load();
      expect(loaded, hasLength(2));
      expect(loaded.map((s) => s.id), ['my_playlists', 'my_moods']);
    });

    test('a real save/load round-trip', () async {
      const sections = [
        SidebarSection(
          id: 'my_playlists',
          title: 'My playlists',
          kind: SidebarItemKind.playlist,
          items: [SidebarItem(kind: SidebarItemKind.playlist, refId: 'p1')],
        ),
      ];
      await SidebarConfigStore.instance.save(sections);
      final reloaded = await SidebarConfigStore.instance.load();
      expect(reloaded, hasLength(1));
      expect(reloaded.single.items.single.refId, 'p1');
    });

    test('saving an explicitly empty list is a real, distinct choice — '
        'not silently treated as "use the defaults"', () async {
      await SidebarConfigStore.instance.save(const []);
      final reloaded = await SidebarConfigStore.instance.load();
      expect(reloaded, isEmpty);
    });

    test('a corrupt file falls back to the defaults, never throws',
        () async {
      final file = File('$tempDir/omnis_sidebar_config.json');
      await file.writeAsString('{not valid json');
      final loaded = await SidebarConfigStore.instance.load();
      expect(loaded, hasLength(2));
    });
  });
}
