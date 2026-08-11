import 'package:dart_eval/dart_eval.dart';
import 'package:dart_eval/dart_eval_bridge.dart';
import 'package:dart_eval/dart_eval_security.dart';
import 'package:dart_eval/stdlib/core.dart';
import 'package:omnis/core/plugin_sandbox_bridge.dart';

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
///
/// ## Bridged host capabilities
///
/// A plugin that declared `library` in its manifest's `permissions:` can
/// also `import 'package:omnis/sandbox_api.dart';` and call real host
/// functions — see [PluginSandboxBridge] for what's bridged and why this
/// (not a JSON-only side channel) is the mechanism for giving a downloaded
/// plugin real capability without making it a bundled, compiled-in plugin.
class PluginRuntime {
  final Map<String, dynamic> _metadata;
  final Runtime _runtime;
  final Set<String> _declaredHooks;

  PluginRuntime._(this._metadata, this._runtime, this._declaredHooks);

  /// Compile and execute `pluginSource`, calling `createPlugin(api)`.
  ///
  /// [declaredPermissions] comes from the plugin's `omnis_plugin.yaml`
  /// manifest (the `permissions:` list). Runtime permissions are granted
  /// **only** for what the plugin explicitly declared — this used to grant
  /// `FilesystemPermission.any` unconditionally to every plugin regardless
  /// of its manifest, which meant any pasted GitHub URL got full file
  /// system access. That defeated the sandbox story entirely, so the grant
  /// is now opt-in per declared permission.
  ///
  /// NOTE: dart_eval's `FilesystemPermission.any` is still all-or-nothing —
  /// there is no per-directory scoping available at this layer. A plugin
  /// that declares `storage` still gets broad file access, it's just no
  /// longer silent/automatic. Before shipping, the install UI
  /// (`plugins_page.dart`) should show the declared permission list to the
  /// user and require confirmation before a `storage` or `network` plugin
  /// is installed, the same way a mobile OS shows a permission prompt.
  factory PluginRuntime.create(
    String pluginSource, {
    List<String> declaredPermissions = const [],
  }) {
    Map<dynamic, dynamic> metadata;
    Runtime runtime;
    try {
      // Bridge declarations must be registered on both the Compiler (so
      // guest code importing package:omnis/sandbox_api.dart type-checks)
      // and the Runtime (so the call actually resolves) — and both before
      // the first executeLib call below, since Runtime.registerBridgeFunc
      // is applied lazily on first setup, which executeLib triggers.
      // Registering only one side leaves the guest call throwing
      // UnimplementedError instead of doing anything.
      const bridge = PluginSandboxBridge();
      final compiler = Compiler()..addPlugin(bridge);
      final program = compiler.compile({
        'default': {'main.dart': pluginSource},
      });
      runtime = Runtime.ofProgram(program)..addPlugin(bridge);
      final wantsStorage = declaredPermissions.any(
        (p) => p == 'storage' || p == 'filesystem',
      );
      if (wantsStorage) {
        runtime.grant(FilesystemPermission.any);
      }
      if (declaredPermissions.contains('library')) {
        runtime.grant(const LibraryReadPermission());
      }
      if (declaredPermissions.contains('events')) {
        runtime.grant(const EventsPermission());
      }
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

  /// Whether this plugin was granted the bridge permission domain
  /// [domain] (e.g. [EventsPermission.domain]) — checked through
  /// dart_eval's own `Runtime.checkPermission`, the same bookkeeping
  /// [PluginSandboxBridge]'s bridged functions already assert against
  /// themselves, rather than a separate list `PluginManager` would need
  /// to keep in sync.
  bool hasPermission(String domain) => _runtime.checkPermission(domain);

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
      // dart_eval 0.8.3's own $Future.$reified only shallow-unwraps its
      // settled value (`.$value`, not `.$reified`) — confirmed directly:
      // an async guest hook that awaits a bridged Future and returns a
      // Map/List built from the result comes back with $Value-wrapped
      // keys/entries still inside what otherwise looks like a plain Dart
      // collection. Deep-reify explicitly for the Future case instead of
      // trusting $Future's own (shallow) $reified.
      if (raw is $Future) {
        return raw.$value.then((v) => v is $Value ? v.$reified : v);
      }
      return raw is $Value ? raw.$reified : raw;
    } catch (e) {
      throw PluginRuntimeException('Hook "$hook" failed: $e');
    }
  }
}
