import 'package:dart_eval/dart_eval.dart';
import 'package:dart_eval/dart_eval_bridge.dart';
import 'package:dart_eval/dart_eval_security.dart';
import 'package:dart_eval/stdlib/core.dart';

/// Compilation/interpreter error thrown by [PluginRuntime].
class PluginRuntimeException implements Exception {
  final String message;
  PluginRuntimeException(this.message);
  @override
  String toString() => message;
}

/// Executes external plugin Dart source code at runtime using dart_eval.
///
/// External plugins (downloaded from GitHub) are **self-contained**: they
/// cannot import `dart:ui` or `package:omnis`, because dart_eval compiles
/// them against an isolated `package:default` library. This is the sandbox.
///
/// ## Plugin contract (v1)
///
/// A plugin exports a `createPlugin` function that returns a metadata Map,
/// plus optional top-level hook functions. The runtime calls hooks via
/// `executeLib`, so each hook is a standalone top-level function:
///
/// ```dart
/// // plugin.dart
/// dynamic createPlugin(dynamic api) {
///   return {
///     'id': 'my_plugin',
///     'name': 'My Plugin',
///     'description': 'Does something cool',
///     'version': '1.0.0',
///     'author': 'Community',
///     'hooks': ['onTrackStart', 'onLibraryScan'],
///   };
/// }
///
/// dynamic onTrackStart(dynamic track) {
///   // track is a JSON Map; react to playback here
///   return null;
/// }
///
/// dynamic onLibraryScan(dynamic file) {
///   // file is a String path
///   return null;
/// }
/// ```
///
/// Hooks receive JSON-serialisable values (Maps, Strings, numbers), so a
/// crashing plugin can never take the music player down.
class PluginRuntime {
  final Map<String, dynamic> _metadata;
  final Runtime _runtime;
  final Set<String> _declaredHooks;

  PluginRuntime._(this._metadata, this._runtime, this._declaredHooks);

  /// Compile and execute `pluginSource`, calling `createPlugin(api)`.
  factory PluginRuntime.create(String pluginSource) {
    Map<dynamic, dynamic> metadata;
    Runtime runtime;
    try {
      final program = Compiler().compile({
        'default': {'main.dart': pluginSource},
      });
      runtime = Runtime.ofProgram(program);
      runtime.grant(FilesystemPermission.any);
      runtime.args = [
        <String, dynamic>{'omnisVersion': '0.1.0'},
      ];
      final raw = runtime.executeLib(
        'package:default/main.dart',
        'createPlugin',
      );
      final unboxed = raw is $Value ? raw.$reified : raw;
      if (unboxed is! Map) {
        throw PluginRuntimeException(
          'createPlugin must return a Map with plugin metadata.',
        );
      }
      metadata = unboxed;
    } catch (e) {
      if (e is PluginRuntimeException) rethrow;
      throw PluginRuntimeException('Failed to load plugin: $e');
    }

    // Read the list of declared hooks from metadata (if present).
    final declared = <String>{};
    final hooksRaw = metadata['hooks'];
    if (hooksRaw is List) {
      for (final h in hooksRaw) {
        declared.add(h.toString());
      }
    }

    // Normalise keys to String for the typed _metadata field.
    final typed = <String, dynamic>{};
    for (final entry in metadata.entries) {
      typed[entry.key.toString()] = entry.value;
    }
    return PluginRuntime._(typed, runtime, declared);
  }

  /// Plugin id from the returned metadata.
  String get id => _metadata['id']?.toString() ?? 'unknown';

  /// Plugin display name.
  String get name => _metadata['name']?.toString() ?? id;

  /// Plugin description.
  String get description =>
      _metadata['description']?.toString() ?? 'External plugin';

  /// Plugin version.
  String get version => _metadata['version']?.toString() ?? '0.0.1';

  /// Plugin author.
  String get author => _metadata['author']?.toString() ?? 'Unknown';

  /// Whether the plugin declares a handler for the given hook name.
  ///
  /// A hook is "declared" if it appears in the `hooks` list of the
  /// metadata Map returned by `createPlugin`.
  bool hasHook(String hook) => _declaredHooks.contains(hook);

  /// Invoke a hook with JSON-serialisable arguments.
  ///
  /// The hook is called as a top-level function via `executeLib`. Returns
  /// the raw interpreter result (JSON-compatible) or `null` if the plugin
  /// doesn't declare the hook.
  ///
  /// Throws [PluginRuntimeException] on interpreter failure, which callers
  /// wrap inside their sandbox.
  /// Wrap a plain Dart value into a dart_eval `$Value` for `executeLib`.
  static dynamic _wrap(dynamic value) {
    if (value is $Value) return value;
    if (value is String) return $String(value);
    if (value is int) return $int(value);
    if (value is double) return $double(value);
    if (value is bool) return $bool(value);
    if (value is Map) return $Map.wrap(value);
    if (value is List) return $List.wrap(value);
    return value;
  }

  dynamic callHook(String hook, List<dynamic> args) {
    if (!hasHook(hook)) return null;
    try {
      final raw = _runtime.executeLib(
        'package:default/main.dart',
        hook,
        args.map(_wrap).toList(),
      );
      return raw is $Value ? raw.$reified : raw;
    } catch (e) {
      throw PluginRuntimeException('Hook "$hook" failed: $e');
    }
  }
}
