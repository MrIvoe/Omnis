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

  /// Hard cap on a downloaded plugin zip's size (as transferred, i.e.
  /// compressed) — a plugin repo has no legitimate reason to be this
  /// large. Without this, a huge or malicious download had no limit at
  /// all: nothing stopped it from hanging the install indefinitely or
  /// filling the device's storage. Overridable (like [_client]) so a
  /// test can exercise the limit without actually transferring 50MB.
  final int maxDownloadBytes;
  static const _defaultMaxDownloadBytes = 50 * 1024 * 1024; // 50 MB

  /// Hard cap on total *uncompressed* bytes extracted from one plugin
  /// archive — the zip-bomb defense a compressed-size cap alone doesn't
  /// cover, since a small download can still expand to gigabytes on
  /// disk. Checked twice: against the archive's own declared per-entry
  /// size before decompressing anything (cheap, but trusts zip
  /// metadata), and again against actual bytes as each file is
  /// extracted (catches a maliciously mislabeled entry, just after that
  /// one file's worth of memory has already been decompressed — see
  /// [installFromUrl]).
  final int maxExtractedBytes;
  static const _defaultMaxExtractedBytes = 200 * 1024 * 1024; // 200 MB

  /// Applied to both the initial response (so a server that never
  /// answers doesn't hang the install forever) and every chunk of the
  /// download stream (so a connection that stalls partway through does
  /// the same) — not one timeout over the whole transfer, since a large
  /// but genuinely slow download that keeps making progress shouldn't be
  /// punished the same as a stalled one.
  static const _downloadTimeout = Duration(seconds: 30);

  PluginInstaller({
    http.Client? client,
    this.maxDownloadBytes = _defaultMaxDownloadBytes,
    this.maxExtractedBytes = _defaultMaxExtractedBytes,
  }) : _client = client ?? http.Client();

  static String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${bytes}B';
  }

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
  ///  - `https://github.com/user/repo` (manifest at the repo root)
  ///  - `https://github.com/user/repo/tree/branch` (manifest at the repo
  ///    root, on a non-default branch)
  ///  - `https://github.com/user/repo/tree/branch/some/subfolder` (a
  ///    monorepo-style catalog — e.g. this project's own
  ///    `MrIvoe/Omnis-Plugins` — with the manifest inside `subfolder`
  ///    rather than at the repo root; the whole repo is still downloaded
  ///    as one zip since that's all GitHub's zip endpoint offers, but only
  ///    `subfolder`'s contents are extracted and validated)
  ///  - `https://github.com/user/repo/archive/refs/heads/main.zip`
  ///  - any direct `.zip` URL
  Future<InstalledPlugin> installFromUrl(String url) async {
    final resolved = _resolveDownloadUrl(url);

    final zipPath = p.join(
      (await _pluginsRoot()).path,
      'download_${DateTime.now().millisecondsSinceEpoch}.zip',
    );
    final zipFile = File(zipPath);

    // Download — streamed rather than a single `_client.get()`, so a
    // size cap can be enforced as bytes arrive instead of only after the
    // whole (potentially huge) response has already been buffered in
    // memory.
    try {
      final request = http.Request('GET', resolved.downloadUri);
      final response = await _client.send(request).timeout(_downloadTimeout);
      if (response.statusCode != 200) {
        throw PluginInstallException(
            'Download failed (HTTP ${response.statusCode})');
      }
      final declaredLength = response.contentLength;
      if (declaredLength != null && declaredLength > maxDownloadBytes) {
        throw PluginInstallException(
          'Plugin download is too large '
          '(${_formatBytes(declaredLength)}, limit is '
          '${_formatBytes(maxDownloadBytes)}).',
        );
      }
      final sink = zipFile.openWrite();
      var received = 0;
      try {
        await response.stream.timeout(_downloadTimeout).forEach((chunk) {
          received += chunk.length;
          if (received > maxDownloadBytes) {
            throw PluginInstallException(
              'Plugin download exceeded the '
              '${_formatBytes(maxDownloadBytes)} size limit.',
            );
          }
          sink.add(chunk);
        });
      } finally {
        await sink.close();
      }
    } catch (e) {
      if (await zipFile.exists()) {
        try {
          await zipFile.delete();
        } catch (_) {}
      }
      if (e is PluginInstallException) rethrow;
      throw PluginInstallException('Could not download plugin: $e');
    }

    // Extract
    final archive = ZipDecoder().decodeBytes(await zipFile.readAsBytes());
    final files = archive.files;
    if (files.isEmpty) {
      throw PluginInstallException('Zip archive is empty.');
    }

    // Zip-bomb guard, pass one: reject before decompressing anything if
    // the archive's own declared (uncompressed) sizes already exceed the
    // cap. `ArchiveFile.size` reads zip metadata only — unlike `.content`,
    // reading it doesn't trigger decompression — so this check stays
    // cheap even for a maliciously huge archive.
    final declaredTotal = files.fold<int>(0, (sum, f) => sum + f.size);
    if (declaredTotal > maxExtractedBytes) {
      throw PluginInstallException(
        'Plugin archive would extract to more than '
        '${_formatBytes(maxExtractedBytes)} (declared '
        '${_formatBytes(declaredTotal)}) — refusing to install.',
      );
    }

    // Find the top-level folder name inside the zip (github wraps in one).
    final topLevel = _findTopLevel(files);
    final subPath = resolved.subPath;

    final targetDir = Directory(
      p.join((await _pluginsRoot()).path,
          _targetDirName(topLevel, url, subPath)),
    );
    if (await targetDir.exists()) {
      // Reinstall: clear old files.
      await targetDir.delete(recursive: true);
    }
    await targetDir.create(recursive: true);

    // `p.normalize`, not `p.canonicalize`, deliberately: targetDir.path is
    // built entirely from our own trusted segments (_pluginsRoot() +
    // _targetDirName()), never from the untrusted zip content, so there's
    // nothing here that needs symlink/`..` resolution. canonicalize also
    // lowercases the path on Windows (case-folds the drive letter and
    // every segment) while normalize below preserves case — comparing a
    // canonicalized root against a merely-normalized candidate meant this
    // check failed for every entry, safe or not, on any case-preserving
    // filesystem (Windows, and macOS's default HFS+/APFS mode), rejecting
    // every install as a false-positive "path traversal attempt."
    final targetRoot = p.normalize(targetDir.path);
    var extractedBytes = 0;
    for (final file in files) {
      if (file.isFile) {
        // Remove the top-level prefix from the stored path.
        var rel = _stripTopLevel(file.name, topLevel);
        if (rel.isEmpty) continue;

        // A catalog install (`.../tree/branch/subfolder`) only wants
        // `subfolder`'s files, extracted as if they were the whole repo —
        // otherwise every other plugin living alongside it in the same
        // catalog repo would get downloaded and written to disk for
        // nothing, and the manifest would end up one directory deeper
        // than `listInstalled()`/`uninstall()` expect.
        if (subPath != null) {
          final prefix = '$subPath/';
          if (!rel.startsWith(prefix)) continue;
          rel = rel.substring(prefix.length);
          if (rel.isEmpty) continue;
        }

        // --- Zip-slip guard -------------------------------------------------
        // Plugins are downloaded from arbitrary, untrusted GitHub URLs, so a
        // malicious archive entry (e.g. "../../../etc/whatever" or an
        // absolute path) must never be allowed to write outside targetDir.
        final candidate = p.join(targetDir.path, rel);
        final candidateNormalized = p.normalize(candidate);
        final candidateDir = p.normalize(p.dirname(candidateNormalized));
        // Reject absolute-looking entries and anything that normalizes
        // outside of targetRoot.
        if (p.isAbsolute(rel) ||
            rel.split(RegExp(r'[\\/]')).contains('..') ||
            !(candidateDir == targetRoot ||
                candidateDir.startsWith('$targetRoot${p.separator}'))) {
          throw PluginInstallException(
            'Rejected unsafe archive entry: "${file.name}" '
            '(path traversal attempt).',
          );
        }
        // ---------------------------------------------------------------

        final content = file.content as List<int>;
        // Zip-bomb guard, pass two: the declared-size check above only
        // trusted zip metadata — a maliciously mislabeled entry can still
        // decompress to more than it claimed. This catches that after
        // the fact, bounding the damage to at most one oversized entry's
        // worth of memory (already decompressed by `file.content` above)
        // before aborting, rather than writing gigabytes of it to disk.
        extractedBytes += content.length;
        if (extractedBytes > maxExtractedBytes) {
          throw PluginInstallException(
            'Plugin archive extracted more than '
            '${_formatBytes(maxExtractedBytes)} — refusing to continue.',
          );
        }

        final out = File(candidateNormalized);
        await out.create(recursive: true);
        await out.writeAsBytes(content);
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
          subPath == null
              ? 'Plugin is missing omnis_plugin.yaml manifest.'
              : 'No omnis_plugin.yaml found in "$subPath".');
    }
    final manifestText = await manifestFile.readAsString();
    final manifest = PluginManifest.parse(manifestText, sourceUrl: url);
    if (manifest == null) {
      throw PluginInstallException('Invalid omnis_plugin.yaml manifest.');
    }

    // Validate entrypoint exists and cannot escape the plugin directory.
    // manifest.entrypoint comes from omnis_plugin.yaml, which is part of
    // the same untrusted download, so it gets the same traversal check.
    final entrypointRel = manifest.entrypoint;
    if (p.isAbsolute(entrypointRel) ||
        entrypointRel.split(RegExp(r'[\\/]')).contains('..')) {
      throw PluginInstallException(
        'Plugin manifest entrypoint is not allowed to reference paths '
        'outside the plugin directory.',
      );
    }
    final entry = File(p.join(targetDir.path, entrypointRel));
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

  /// Fetches just the manifest currently published at [sourceUrl], for an
  /// update check — never the full zip [installFromUrl] downloads.
  /// GitHub's raw-content CDN serves one file directly, which is orders
  /// of magnitude lighter than downloading and extracting an entire repo
  /// archive just to read one version string.
  ///
  /// Returns `null` (never throws) for anything that isn't a GitHub
  /// `tree`/bare-repo URL this can resolve to a raw manifest path, a
  /// network failure, a non-200 response, or an unparseable manifest —
  /// an update check is inherently best-effort, and one plugin's source
  /// URL not supporting it must not abort checking the rest.
  Future<PluginManifest?> fetchRemoteManifest(String sourceUrl) async {
    final rawUri = _resolveManifestRawUrl(sourceUrl);
    if (rawUri == null) return null;
    try {
      final response =
          await _client.get(rawUri).timeout(_downloadTimeout);
      if (response.statusCode != 200) return null;
      return PluginManifest.parse(response.body, sourceUrl: sourceUrl);
    } catch (_) {
      return null;
    }
  }

  /// Resolves a GitHub repo URL (the same shapes [_resolveDownloadUrl]
  /// accepts) to a direct `raw.githubusercontent.com` URL for its
  /// `omnis_plugin.yaml`. Returns `null` for a direct `.zip` URL — there
  /// is no general way to derive a single raw file's location from an
  /// arbitrary zip download link, so those plugins simply aren't
  /// update-checkable this way.
  static Uri? _resolveManifestRawUrl(String input) {
    final url = input.trim();

    final treeMatch =
        RegExp(r'^https?://github\.com/([^/]+)/([^/]+)/tree/([^/]+)(?:/(.+))?$')
            .firstMatch(url);
    if (treeMatch != null) {
      final user = treeMatch.group(1)!;
      final repo = treeMatch.group(2)!;
      final branch = treeMatch.group(3)!;
      final subPath = treeMatch.group(4);
      final manifestPath = subPath == null || subPath.isEmpty
          ? 'omnis_plugin.yaml'
          : '$subPath/omnis_plugin.yaml';
      return Uri.parse(
        'https://raw.githubusercontent.com/$user/$repo/$branch/$manifestPath',
      );
    }

    final bareMatch =
        RegExp(r'^https?://github\.com/([^/]+)/([^/]+)/?$').firstMatch(url);
    if (bareMatch != null) {
      final user = bareMatch.group(1)!;
      final repo = bareMatch.group(2)!;
      // Same "main" assumption _resolveDownloadUrl's bare-repo case
      // already makes — a repo whose default branch is actually
      // "master" (or anything else) isn't resolvable here either way,
      // a pre-existing simplification this doesn't newly introduce.
      return Uri.parse(
        'https://raw.githubusercontent.com/$user/$repo/main/omnis_plugin.yaml',
      );
    }

    return null;
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

  /// Resolves a user-friendly GitHub URL into a direct zip download URL,
  /// plus (for a `.../tree/branch/subfolder` catalog link) the subfolder
  /// within the extracted zip that actually holds the plugin.
  static ({Uri downloadUri, String? subPath}) _resolveDownloadUrl(
      String input) {
    var url = input.trim();
    if (url.isEmpty) {
      throw PluginInstallException('URL is empty.');
    }

    // https://github.com/user/repo/tree/branch[/subfolder/...] → branch
    // zip, with an optional subfolder for a monorepo-style catalog.
    final treeMatch =
        RegExp(r'^https?://github\.com/([^/]+)/([^/]+)/tree/([^/]+)(?:/(.+))?$')
            .firstMatch(url);
    if (treeMatch != null) {
      final user = treeMatch.group(1)!;
      final repo = treeMatch.group(2)!;
      final branch = treeMatch.group(3)!;
      final subPath = treeMatch.group(4);
      return (
        downloadUri: Uri.parse(
          'https://codeload.github.com/$user/$repo/zip/refs/heads/$branch',
        ),
        subPath: subPath,
      );
    }

    // https://github.com/user/repo/archive/refs/heads/main.zip → direct
    final archiveMatch = RegExp(r'^(https?://.*\.zip)$').firstMatch(url);
    if (archiveMatch != null) {
      return (downloadUri: Uri.parse(url), subPath: null);
    }

    // https://github.com/user/repo → default branch zip
    final bareMatch =
        RegExp(r'^https?://github\.com/([^/]+)/([^/]+)/?$').firstMatch(url);
    if (bareMatch != null) {
      final user = bareMatch.group(1)!;
      final repo = bareMatch.group(2)!;
      return (
        downloadUri: Uri.parse(
            'https://codeload.github.com/$user/$repo/zip/refs/heads/main'),
        subPath: null,
      );
    }

    // Maybe a raw plugin.dart URL? Not supported yet.
    throw PluginInstallException(
      'Unsupported URL. Use a GitHub repository URL or a direct .zip link.',
    );
  }

  /// The single directory every entry in the archive sits under, if there
  /// is one (GitHub wraps a repo zip in `repo-branch/`).
  ///
  /// This used to return the first segment of the first file unconditionally,
  /// so a zip whose files sit at the root (`omnis_plugin.yaml`,
  /// `plugin.dart`) reported a "top level" of `omnis_plugin.yaml` and
  /// installed into a directory named `plugin_omnis_plugin.yaml`. Requiring
  /// that *every* entry share the prefix — and that it actually be a
  /// directory — makes both zip layouts work.
  static String? _findTopLevel(Iterable<ArchiveFile> files) {
    String? candidate;
    for (final f in files) {
      if (!f.isFile) continue;
      final parts = f.name.split('/');
      // A file at the archive root means there is no common wrapper.
      if (parts.length < 2) return null;
      final first = parts.first;
      if (candidate == null) {
        candidate = first;
      } else if (candidate != first) {
        return null;
      }
    }
    return candidate;
  }

  /// A stable, filesystem-safe directory name for an installed plugin.
  ///
  /// Prefers the archive's wrapper directory (`repo-main`) so reinstalling
  /// the same plugin replaces it instead of piling up copies. Falls back to
  /// the source URL when the zip has no wrapper. [subPath] is folded in too
  /// — without it, installing two different plugins out of the same
  /// catalog repo (e.g. `Omnis-Plugins/sample_logger` and
  /// `Omnis-Plugins/some_other_plugin`) would both resolve to the same
  /// `plugin_Omnis-Plugins-main` directory and silently overwrite one
  /// another on install.
  static String _targetDirName(String? topLevel, String url, String? subPath) {
    final raw = (topLevel != null && topLevel.isNotEmpty)
        ? topLevel
        : Uri.tryParse(url)
                ?.pathSegments
                .where((s) => s.isNotEmpty)
                .join('_') ??
            'unknown';
    final combined = subPath == null || subPath.isEmpty ? raw : '${raw}_$subPath';
    final safe = combined.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return 'plugin_${safe.isEmpty ? 'unknown' : safe}';
  }

  static String _stripTopLevel(String name, String? top) {
    if (top == null) return name;
    if (name.startsWith('$top/')) {
      return name.substring(top.length + 1);
    }
    return name;
  }
}
