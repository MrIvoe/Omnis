import 'package:yaml/yaml.dart';

/// A parsed, user-authored Now Playing layout description.
///
/// Unlike a downloaded *plugin* (a `plugin.dart` + `omnis_plugin.yaml`
/// pair — code plus metadata), a layout is a single data file: there is no
/// code to compile or interpret, only a tree of node descriptions that
/// [DeclarativeLayoutRenderer] walks against a **fixed, closed** set of
/// components. That's what makes this safely importable from a URL or a
/// local file with no sandbox, no permission dialog, and no dart_eval
/// involved at all — the file cannot describe anything the renderer
/// doesn't already know how to build, so it cannot reach the network,
/// the filesystem, or any Core capability beyond rearranging the same
/// building blocks every bundled layout already uses.
///
/// ### File format (`omnis_layout.yaml`)
///
/// ```yaml
/// id: my_layout            # stable, unique — see LayoutManager collision check
/// name: My Layout
/// description: One line shown in the picker
/// author: Your Name
/// version: 1.0.0
/// defines_own_gestures: false   # true = tap/swipe drive playback directly
/// background:                   # optional
///   type: color                # 'color' | 'gradient'
///   value: surface              # a ColorScheme role name or "#RRGGBB"
/// root:                         # a node tree — see DeclarativeLayoutRenderer
///   type: column
///   children:
///     - { type: component, component: album_art }
///     - { type: component, component: track_info }
///     - { type: component, component: controls_row }
/// ```
class LayoutManifest {
  final String id;
  final String name;
  final String description;
  final String author;
  final String version;
  final bool definesOwnGestures;
  final Map<String, dynamic>? background;
  final Map<String, dynamic> root;

  /// Where this was installed from (a URL, or `local`/`file://...`).
  final String sourceUrl;

  const LayoutManifest({
    required this.id,
    required this.name,
    required this.description,
    required this.author,
    required this.version,
    required this.definesOwnGestures,
    required this.background,
    required this.root,
    required this.sourceUrl,
  });

  /// Parse a layout file's raw text (YAML or JSON — JSON is a YAML
  /// subset, so one parser handles both). Returns `null` for anything
  /// that doesn't have at least `id`, `name`, and a `root` node — never
  /// throws.
  static LayoutManifest? parse(String text, {required String sourceUrl}) {
    try {
      final doc = loadYaml(text);
      if (doc is! Map) return null;
      final id = _asString(doc['id']);
      final name = _asString(doc['name']);
      final root = _asMap(doc['root']);
      if (id == null || id.isEmpty || name == null || root == null) {
        return null;
      }
      return LayoutManifest(
        id: id,
        name: name,
        description: _asString(doc['description']) ?? 'No description',
        author: _asString(doc['author']) ?? 'Unknown',
        version: _asString(doc['version']) ?? '0.0.1',
        definesOwnGestures: doc['defines_own_gestures'] == true,
        background: _asMap(doc['background']),
        root: root,
        sourceUrl: sourceUrl,
      );
    } catch (_) {
      return null;
    }
  }

  static String? _asString(dynamic value) => value is String ? value : null;

  /// Recursively converts `YamlMap`/`YamlList` (or already-plain
  /// `Map`/`List`, e.g. from a JSON file) into plain `Map<String,
  /// dynamic>`/`List<dynamic>` once, at parse time — so
  /// [DeclarativeLayoutRenderer] only ever walks ordinary Dart
  /// collections and never needs to know about the `yaml` package.
  static Map<String, dynamic>? _asMap(dynamic value) {
    final converted = _deepConvert(value);
    return converted is Map<String, dynamic> ? converted : null;
  }

  static dynamic _deepConvert(dynamic value) {
    if (value is Map) {
      return {
        for (final entry in value.entries)
          entry.key.toString(): _deepConvert(entry.value),
      };
    }
    if (value is Iterable) {
      return [for (final item in value) _deepConvert(item)];
    }
    return value;
  }
}
