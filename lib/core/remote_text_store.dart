import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Exception thrown by [RemoteTextStore].
class RemoteTextStoreException implements Exception {
  final String message;
  RemoteTextStoreException(this.message);
  @override
  String toString() => message;
}

/// Fetches and persists a single user-authored text file (YAML/JSON) —
/// the shared shape behind both `LayoutInstaller` (Now Playing layouts,
/// `lib/ui/player_layouts/declarative/`) and `ThemeInstaller` (themes,
/// `lib/ui/theme/declarative/`). Both deal in exactly one flat data file
/// per install, not a code repository: no zip download, no archive
/// extraction, no zip-slip surface at all — the whole install path never
/// writes anything except the exact bytes of the one file the user
/// pointed at, under this app's own per-kind directory.
///
/// Deliberately knows nothing about the file's *content* — parsing and
/// validating a manifest (including id-collision checks against bundled
/// entries) is each caller's job, done *before* [persist] is ever
/// called, so a rejected import never gets written to disk in the first
/// place. This class only ever answers "where do this kind of file's
/// bytes live on disk."
class RemoteTextStore {
  final String _subdirectory;
  final http.Client _client;

  RemoteTextStore(this._subdirectory, {http.Client? client})
      : _client = client ?? http.Client();

  Future<Directory> _root() async {
    final docs = await getApplicationSupportDirectory();
    final dir = Directory(p.join(docs.path, _subdirectory));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Fetch raw text from a direct link — a GitHub "raw" file URL, a gist
  /// raw URL, or any plain-text URL. Not a repo URL: point this at the
  /// file itself. Does not validate or persist anything.
  Future<String> fetchFromUrl(String url) async {
    final http.Response response;
    try {
      response = await _client.get(Uri.parse(url)).timeout(
            const Duration(seconds: 15),
          );
    } catch (e) {
      throw RemoteTextStoreException('Could not download: $e');
    }
    if (response.statusCode != 200) {
      throw RemoteTextStoreException(
        'Download failed (HTTP ${response.statusCode}).',
      );
    }
    return response.body;
  }

  /// Read raw text from a local file (e.g. picked via `file_picker`).
  /// Does not validate or persist anything.
  Future<String> readFromFile(String path) async {
    try {
      return await File(path).readAsString();
    } catch (e) {
      throw RemoteTextStoreException('Could not read "$path": $e');
    }
  }

  /// Write [rawText] to disk under [id]. Callers must validate first —
  /// this trusts the caller completely and will happily overwrite an
  /// existing entry with the same id.
  Future<void> persist(String id, String rawText) async {
    final root = await _root();
    final file = File(p.join(root.path, '${_safeFileName(id)}.yaml'));
    await file.writeAsString(rawText);
  }

  /// Raw text of every installed file, for the caller to parse itself —
  /// a corrupt file is skipped rather than failing the whole list.
  Future<List<String>> listInstalledRaw() async {
    final root = await _root();
    final result = <String>[];
    if (!await root.exists()) return result;
    await for (final entity in root.list()) {
      if (entity is! File) continue;
      final ext = p.extension(entity.path).toLowerCase();
      if (ext != '.yaml' && ext != '.yml' && ext != '.json') continue;
      try {
        result.add(await entity.readAsString());
      } catch (_) {
        // A corrupt file on disk shouldn't block loading the rest.
      }
    }
    return result;
  }

  /// Remove an installed entry's file from disk.
  Future<void> uninstall(String id) async {
    final root = await _root();
    final file = File(p.join(root.path, '${_safeFileName(id)}.yaml'));
    if (await file.exists()) {
      await file.delete();
    }
  }

  static String _safeFileName(String id) =>
      id.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
}
