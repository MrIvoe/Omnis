import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:omnis/ui/player_layouts/declarative/layout_manifest.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Exception thrown by [LayoutInstaller] and [LayoutManager].
class LayoutInstallException implements Exception {
  final String message;
  LayoutInstallException(this.message);
  @override
  String toString() => message;
}

/// Reads and persists user-authored Now Playing layouts on disk.
///
/// A layout is one YAML/JSON text file, not a code repository — there is
/// no `plugin.dart` equivalent to compile or sandbox, so installing one is
/// just "fetch or read the text, then save it." No zip download, no
/// archive extraction, no zip-slip surface: the whole install path never
/// writes anything to disk except the exact bytes of the one file the
/// user pointed at, under this app's own layouts directory.
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
  final http.Client _client;

  LayoutInstaller({http.Client? client}) : _client = client ?? http.Client();

  Future<Directory> _layoutsRoot() async {
    final docs = await getApplicationSupportDirectory();
    final dir = Directory(p.join(docs.path, 'layouts'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Fetch a layout's raw text from a direct link — a GitHub "raw" file
  /// URL, a gist raw URL, or any plain-text URL. Not a GitHub repo URL
  /// (there is no archive to extract): point this at the file itself.
  /// Does not validate or persist anything.
  Future<String> fetchFromUrl(String url) async {
    final http.Response response;
    try {
      response = await _client.get(Uri.parse(url)).timeout(
            const Duration(seconds: 15),
          );
    } catch (e) {
      throw LayoutInstallException('Could not download layout: $e');
    }
    if (response.statusCode != 200) {
      throw LayoutInstallException(
        'Download failed (HTTP ${response.statusCode}).',
      );
    }
    return response.body;
  }

  /// Read a layout's raw text from a local file (e.g. picked via
  /// `file_picker`). Does not validate or persist anything.
  Future<String> readFromFile(String path) async {
    try {
      return await File(path).readAsString();
    } catch (e) {
      throw LayoutInstallException('Could not read "$path": $e');
    }
  }

  /// Write [rawText] to disk under [manifest]'s id. Callers must validate
  /// first — this trusts [manifest] completely and will happily overwrite
  /// an existing layout with the same id.
  Future<void> persist(LayoutManifest manifest, String rawText) async {
    final root = await _layoutsRoot();
    final file = File(p.join(root.path, '${_safeFileName(manifest.id)}.yaml'));
    await file.writeAsString(rawText);
  }

  /// All layouts previously installed on disk.
  Future<List<LayoutManifest>> listInstalled() async {
    final root = await _layoutsRoot();
    final result = <LayoutManifest>[];
    if (!await root.exists()) return result;
    await for (final entity in root.list()) {
      if (entity is! File) continue;
      final ext = p.extension(entity.path).toLowerCase();
      if (ext != '.yaml' && ext != '.yml' && ext != '.json') continue;
      try {
        final text = await entity.readAsString();
        final manifest = LayoutManifest.parse(text, sourceUrl: 'local');
        if (manifest != null) result.add(manifest);
      } catch (_) {
        // A corrupt file on disk shouldn't block loading the rest.
      }
    }
    return result;
  }

  /// Remove an installed layout's file from disk.
  Future<void> uninstall(String id) async {
    final root = await _layoutsRoot();
    final file = File(p.join(root.path, '${_safeFileName(id)}.yaml'));
    if (await file.exists()) {
      await file.delete();
    }
  }

  static String _safeFileName(String id) =>
      id.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
}
