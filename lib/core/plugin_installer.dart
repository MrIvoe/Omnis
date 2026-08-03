import 'dart:io';
import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:omnis/core/plugin_manifest.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Exception thrown by the plugin installer.
class PluginInstallException implements Exception {
  final String message;
  PluginInstallException(this.message);
  @override
  String toString() => message;
}

/// Result of a successful plugin install.
class InstalledPlugin {
  final PluginManifest manifest;

  /// Absolute path of the plugin directory.
  final String directory;

  /// Absolute path of the entrypoint (plugin.dart).
  final String entrypointPath;

  const InstalledPlugin({
    required this.manifest,
    required this.directory,
    required this.entrypointPath,
  });
}

/// A plugin found on disk (manifest + its directory).
class InstalledPluginInfo {
  final PluginManifest manifest;
  final String directory;

  const InstalledPluginInfo({required this.manifest, required this.directory});
}

/// Installs plugins from GitHub (or any direct zip) URLs.
///
/// Flow: user pastes `https://github.com/user/repo` →
/// we download the repo as a zip → extract → validate
/// `omnis_plugin.yaml` → register entrypoint.
class PluginInstaller {
  final http.Client _client;

  PluginInstaller({http.Client? client}) : _client = client ?? http.Client();

  /// The directory where all plugins are stored on disk.
  Future<Directory> _pluginsRoot() async {
    final docs = await getApplicationSupportDirectory();
    final dir = Directory(p.join(docs.path, 'plugins'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Installs a plugin from a GitHub URL.
  ///
  /// Supported inputs:
  ///  - `https://github.com/user/repo`
  ///  - `https://github.com/user/repo/tree/branch`
  ///  - `https://github.com/user/repo/archive/refs/heads/main.zip`
  ///  - any direct `.zip` URL
  Future<InstalledPlugin> installFromUrl(String url) async {
    final resolved = _resolveDownloadUrl(url);

    final zipPath = p.join(
      (await _pluginsRoot()).path,
      'download_${DateTime.now().millisecondsSinceEpoch}.zip',
    );
    final zipFile = File(zipPath);

    // Download
    try {
      final resp = await _client.get(resolved);
      if (resp.statusCode != 200) {
        throw PluginInstallException(
            'Download failed (HTTP ${resp.statusCode})');
      }
      await zipFile.writeAsBytes(resp.bodyBytes);
    } catch (e) {
      if (e is PluginInstallException) rethrow;
      throw PluginInstallException('Could not download plugin: $e');
    }

    // Extract
    final archive = ZipDecoder().decodeBytes(await zipFile.readAsBytes());
    final files = archive.files;
    if (files.isEmpty) {
      throw PluginInstallException('Zip archive is empty.');
    }

    // Find the top-level folder name inside the zip (github wraps in one).
    final topLevel = _findTopLevel(files);

    final targetDir = Directory(
      p.join((await _pluginsRoot()).path, 'plugin_$topLevel'),
    );
    if (await targetDir.exists()) {
      // Reinstall: clear old files.
      await targetDir.delete(recursive: true);
    }
    await targetDir.create(recursive: true);

    for (final file in files) {
      if (file.isFile) {
        // Remove the top-level prefix from the stored path.
        final rel = _stripTopLevel(file.name, topLevel);
        if (rel.isEmpty) continue;
        final out = File(p.join(targetDir.path, rel));
        await out.create(recursive: true);
        await out.writeAsBytes(file.content as List<int>);
      }
    }

    // Cleanup zip
    try {
      await zipFile.delete();
    } catch (_) {}

    // Validate manifest
    final manifestFile = File(p.join(targetDir.path, 'omnis_plugin.yaml'));
    if (!await manifestFile.exists()) {
      throw PluginInstallException(
          'Plugin is missing omnis_plugin.yaml manifest.');
    }
    final manifestText = await manifestFile.readAsString();
    final manifest = PluginManifest.parse(manifestText, sourceUrl: url);
    if (manifest == null) {
      throw PluginInstallException('Invalid omnis_plugin.yaml manifest.');
    }

    // Validate entrypoint exists
    final entry = File(p.join(targetDir.path, manifest.entrypoint));
    if (!await entry.exists()) {
      throw PluginInstallException(
        'Plugin entrypoint ${manifest.entrypoint} does not exist.',
      );
    }

    return InstalledPlugin(
      manifest: manifest,
      directory: targetDir.path,
      entrypointPath: entry.path,
    );
  }

  /// Lists all previously installed plugins (manifest + directory path).
  Future<List<InstalledPluginInfo>> listInstalled() async {
    final root = await _pluginsRoot();
    final result = <InstalledPluginInfo>[];
    await for (final entity in root.list()) {
      if (entity is Directory) {
        final manifestFile = File(p.join(entity.path, 'omnis_plugin.yaml'));
        if (await manifestFile.exists()) {
          final text = await manifestFile.readAsString();
          final m = PluginManifest.parse(text, sourceUrl: 'local');
          if (m != null) {
            result
                .add(InstalledPluginInfo(manifest: m, directory: entity.path));
          }
        }
      }
    }
    return result;
  }

  /// Returns plugin metadata for an installed plugin by reading its entrypoint.
  Future<String> readEntrypoint(String directory) async {
    final manifestFile = File(p.join(directory, 'omnis_plugin.yaml'));
    if (!await manifestFile.exists()) return '';
    final text = await manifestFile.readAsString();
    final m = PluginManifest.parse(text, sourceUrl: 'local');
    if (m == null) return '';
    final entry = File(p.join(directory, m.entrypoint));
    if (!await entry.exists()) return '';
    return entry.readAsString();
  }

  /// Uninstalls a plugin by directory.
  Future<void> uninstall(String directory) async {
    final dir = Directory(directory);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  /// Resolves a user-friendly GitHub URL into a direct zip download URL.
  static Uri _resolveDownloadUrl(String input) {
    var url = input.trim();
    if (url.isEmpty) {
      throw PluginInstallException('URL is empty.');
    }

    // https://github.com/user/repo/tree/branch → branch zip
    final treeMatch =
        RegExp(r'^https?://github\.com/([^/]+)/([^/]+)/tree/(.+)$')
            .firstMatch(url);
    if (treeMatch != null) {
      final user = treeMatch.group(1)!;
      final repo = treeMatch.group(2)!;
      final branch = treeMatch.group(3)!;
      return Uri.parse(
        'https://codeload.github.com/$user/$repo/zip/refs/heads/$branch',
      );
    }

    // https://github.com/user/repo/archive/refs/heads/main.zip → direct
    final archiveMatch = RegExp(r'^(https?://.*\.zip)$').firstMatch(url);
    if (archiveMatch != null) {
      return Uri.parse(url);
    }

    // https://github.com/user/repo → default branch zip
    final bareMatch =
        RegExp(r'^https?://github\.com/([^/]+)/([^/]+)/?$').firstMatch(url);
    if (bareMatch != null) {
      final user = bareMatch.group(1)!;
      final repo = bareMatch.group(2)!;
      return Uri.parse(
          'https://codeload.github.com/$user/$repo/zip/refs/heads/main');
    }

    // Maybe a raw plugin.dart URL? Not supported yet.
    throw PluginInstallException(
      'Unsupported URL. Use a GitHub repository URL or a direct .zip link.',
    );
  }

  static String? _findTopLevel(Iterable<ArchiveFile> files) {
    for (final f in files) {
      if (f.isFile) {
        final parts = f.name.split('/');
        if (parts.isNotEmpty) return parts.first;
      }
    }
    return null;
  }

  static String _stripTopLevel(String name, String? top) {
    if (top == null) return name;
    if (name.startsWith('$top/')) {
      return name.substring(top.length + 1);
    }
    return name;
  }
}
