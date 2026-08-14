import 'package:yaml/yaml.dart';

/// Parsed `omnis_plugin.yaml` manifest from an installed plugin bundle.
class PluginManifest {
  /// Plugin id (e.g. `lyrics_provider`).
  final String id;

  /// Display name.
  final String name;

  /// One-line description.
  final String description;

  /// Plugin version (e.g. `1.0.0`).
  final String version;

  /// Author of the plugin.
  final String author;

  /// Entrypoint file (defaults to `plugin.dart`).
  final String entrypoint;

  /// Minimum Omnis core version required.
  final String? minOmnisVersion;

  /// Hooks this plugin declares support for.
  final List<String> hooks;

  /// Permissions requested (e.g. `network`, `storage`) — what this plugin
  /// needs *from* the app.
  final List<String> permissions;

  /// Plugin ids this plugin declares it needs already installed to
  /// function — item 26's "dependency resolution" gap: previously
  /// `dependencies:` in a manifest was parsed by nothing at all, so a
  /// plugin depending on another simply failed at runtime (a missing
  /// service, a null lookup) with no diagnosable connection back to
  /// "you're missing a dependency." Checked at install time
  /// (`PluginManager._registerInstalledPlugin`) and re-checked whenever
  /// the installed set changes (`PluginManager.missingDependenciesFor`),
  /// so a dependency that's since been uninstalled is detectable too —
  /// not just a one-time install-time gate.
  final List<String> dependencies;

  /// Capabilities this plugin registers itself as a provider of (e.g.
  /// `lyrics`, `queue_builder`) — the reverse direction from
  /// [permissions]: what this plugin offers *to* the app, for other code
  /// (bundled or external) to consume through the normal `ServiceRegistry`
  /// lookup. Shown to the user separately from [permissions] before
  /// install (see `plugins_page.dart`'s `_confirmPermissions`) since the
  /// two read very differently — "wants access to" vs. "will supply."
  /// Gates registration in `PluginManager` against a small, fixed catalog
  /// of supported capabilities — declaring an unsupported value here is
  /// simply never registered, not an error.
  final List<String> provides;

  /// Source URL the plugin was installed from.
  final String sourceUrl;

  const PluginManifest({
    required this.id,
    required this.name,
    required this.description,
    required this.version,
    required this.author,
    required this.entrypoint,
    this.minOmnisVersion,
    this.hooks = const [],
    this.permissions = const [],
    this.dependencies = const [],
    this.provides = const [],
    required this.sourceUrl,
  });

  /// Parse a manifest from raw YAML text.
  static PluginManifest? parse(String yamlText, {required String sourceUrl}) {
    try {
      final doc = loadYaml(yamlText);
      if (doc is! Map) return null;
      final id = _asString(doc['id']);
      final name = _asString(doc['name']);
      if (id == null || name == null) return null;
      return PluginManifest(
        id: id,
        name: name,
        description: _asString(doc['description']) ?? 'No description',
        version: _asString(doc['version']) ?? '0.0.1',
        author: _asString(doc['author']) ?? 'Unknown',
        entrypoint: _asString(doc['entrypoint']) ?? 'plugin.dart',
        minOmnisVersion: _asString(doc['min_omnis_version']),
        hooks: _asStringList(doc['hooks']),
        permissions: _asStringList(doc['permissions']),
        dependencies: _asStringList(doc['dependencies']),
        provides: _asStringList(doc['provides']),
        sourceUrl: sourceUrl,
      );
    } catch (e) {
      return null;
    }
  }

  static String? _asString(dynamic value) => value is String ? value : null;

  static List<String> _asStringList(dynamic value) {
    if (value is YamlList) {
      return value.whereType<String>().toList();
    }
    return const [];
  }
}
