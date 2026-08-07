import 'package:http/http.dart' as http;
import 'package:omnis/core/remote_text_store.dart';
import 'package:omnis/ui/theme/declarative/theme_manifest.dart';

/// Exception thrown by [ThemeInstaller] and [ThemeManager].
class ThemeInstallException implements Exception {
  final String message;
  ThemeInstallException(this.message);
  @override
  String toString() => message;
}

/// Reads and persists user-authored themes on disk.
///
/// A theme is one YAML/JSON text file — see [RemoteTextStore]'s doc
/// comment for why that makes it safe to install with no sandbox. This is
/// the theme-flavored twin of `LayoutInstaller`: both are thin wrappers
/// over the same shared store, re-thrown as their own exception type so
/// callers keep seeing the type they expect for their domain, rather than
/// this project growing a second copy of the same fetch/persist/list
/// boilerplate.
class ThemeInstaller {
  final RemoteTextStore _store;

  ThemeInstaller({http.Client? client})
      : _store = RemoteTextStore('themes', client: client);

  Future<String> fetchFromUrl(String url) => _wrap(_store.fetchFromUrl(url));

  Future<String> readFromFile(String path) =>
      _wrap(_store.readFromFile(path));

  Future<void> persist(ThemeManifest manifest, String rawText) =>
      _wrap(_store.persist(manifest.id, rawText));

  /// All themes previously installed on disk.
  Future<List<ThemeManifest>> listInstalled() async {
    final texts = await _wrap(_store.listInstalledRaw());
    final result = <ThemeManifest>[];
    for (final text in texts) {
      final manifest = ThemeManifest.parse(text, sourceUrl: 'local');
      if (manifest != null) result.add(manifest);
    }
    return result;
  }

  Future<void> uninstall(String id) => _wrap(_store.uninstall(id));

  static Future<T> _wrap<T>(Future<T> future) async {
    try {
      return await future;
    } on RemoteTextStoreException catch (e) {
      throw ThemeInstallException(e.message);
    }
  }
}
