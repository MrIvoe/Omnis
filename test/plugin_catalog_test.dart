import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/plugin_catalog.dart';

void main() {
  group('findCatalogEntryForPluginId', () {
    const catalog = [
      CatalogPluginEntry(
        folder: 'sample_logger',
        name: 'Sample Logger',
        description: 'Logs track starts.',
      ),
      CatalogPluginEntry(
        folder: 'radio',
        name: 'Radio Browser',
        description: 'Live internet radio stations.',
      ),
    ];

    test('finds the catalog entry whose folder matches the plugin id', () {
      final entry = findCatalogEntryForPluginId('radio', catalog);

      expect(entry, isNotNull);
      expect(entry!.name, 'Radio Browser');
    });

    test('returns null when nothing in the catalog matches', () {
      expect(
        findCatalogEntryForPluginId('totally_unknown_plugin', catalog),
        isNull,
      );
    });

    test('an empty catalog never matches anything', () {
      expect(findCatalogEntryForPluginId('sample_logger', const []), isNull);
    });

    test('the match is case-sensitive — ids are exact identifiers, not '
        'free text', () {
      expect(findCatalogEntryForPluginId('Sample_Logger', catalog), isNull);
    });

    test('the official hardcoded fallback catalog matches its own '
        "sample_logger entry by id", () {
      final entry =
          findCatalogEntryForPluginId('sample_logger', officialPluginCatalog);

      expect(entry, isNotNull);
      expect(entry!.folder, 'sample_logger');
    });
  });
}
