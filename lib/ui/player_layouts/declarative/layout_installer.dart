import 'package:http/http.dart' as http;
import 'package:omnis/core/remote_text_store.dart';
import 'package:omnis/ui/player_layouts/declarative/layout_manifest.dart';

/// Exception thrown by [LayoutInstaller] and [LayoutManager].
class LayoutInstallException implements Exception {
  final String message;
  LayoutInstallException(this.message);
  @override
  String toString() => message;
}

/// Reads and persists user-authored Now Playing layouts on disk.
///
/// A layout is one YAML/JSON text file, not a code repository — see
/// [RemoteTextStore]'s doc comment for why that makes it safe to install
/// from a URL with no sandbox at all. This class is a thin,
/// layout-flavored wrapper over that shared store: it just re-throws
/// [RemoteTextStoreException] as [LayoutInstallException] so existing
/// callers (`LayoutManager`, tests) keep seeing the exception type
/// they've always expected.
///
/// Deliberately split into "fetch/read raw text" ([fetchFromUrl],
/// [readFromFile]) versus "persist an already-validated manifest"
/// ([persist]): [LayoutManager] parses and checks the manifest (including
/// rejecting an id that collides with a bundled layout) *before* calling
/// [persist], so a rejected import is never written to disk in the first
/// place — earlier code validated only after writing, which meant a
/// rejected id could still resurface on the next app start via
/// [listInstalled] reading the orphaned file back.
class LayoutInstaller {
  final RemoteTextStore _store;

  LayoutInstaller({http.Client? client})
      : _store = RemoteTextStore('layouts', client: client);

  Future<String> fetchFromUrl(String url) => _wrap(_store.fetchFromUrl(url));

  Future<String> readFromFile(String path) =>
      _wrap(_store.readFromFile(path));

  Future<void> persist(LayoutManifest manifest, String rawText) =>
      _wrap(_store.persist(manifest.id, rawText));

  /// All layouts previously installed on disk.
  Future<List<LayoutManifest>> listInstalled() async {
    final texts = await _wrap(_store.listInstalledRaw());
    final result = <LayoutManifest>[];
    for (final text in texts) {
      final manifest = LayoutManifest.parse(text, sourceUrl: 'local');
      if (manifest != null) result.add(manifest);
    }
    return result;
  }

  Future<void> uninstall(String id) => _wrap(_store.uninstall(id));

  static Future<T> _wrap<T>(Future<T> future) async {
    try {
      return await future;
    } on RemoteTextStoreException catch (e) {
      throw LayoutInstallException(e.message);
    }
  }
}
