import 'package:dart_eval/dart_eval_bridge.dart';
import 'package:dart_eval/dart_eval_security.dart';
import 'package:dart_eval/stdlib/core.dart';
import 'package:omnis/core/library_repository.dart';

/// Permission domain gating [PluginSandboxBridge.loadLibraryTracks] and any
/// future read-only library capability bridged into the sandbox. Granted
/// only when a plugin's manifest declares `library` in its `permissions:`
/// list — see `PluginRuntime.create`. Mirrors the existing
/// `FilesystemPermission` gate that same factory already applies for
/// `storage`/`filesystem`, using dart_eval's own permission mechanism
/// (`Runtime.grant`/`assertPermission`) rather than a separate ad hoc check.
class LibraryReadPermission implements Permission {
  const LibraryReadPermission();

  static const domain = 'omnis.library';

  @override
  List<String> get domains => const [domain];

  @override
  bool match([Object? data]) => true;

  @override
  bool operator ==(Object other) => other is LibraryReadPermission;

  @override
  int get hashCode => domain.hashCode;
}

/// Permission domain gating whether a plugin receives forwarded app events
/// (today: `FavoriteChangedEvent`, via `onPluginEvent` — see
/// `PluginManager`'s event-forwarding subscription). Granted only when a
/// plugin's manifest declares `events` in its `permissions:` list, checked
/// through `PluginRuntime.hasPermission` at forwarding time — the same
/// dart_eval-native permission bookkeeping [LibraryReadPermission] uses,
/// deliberately not a separate parallel list to keep in sync.
class EventsPermission implements Permission {
  const EventsPermission();

  static const domain = 'omnis.events';

  @override
  List<String> get domains => const [domain];

  @override
  bool match([Object? data]) => true;

  @override
  bool operator ==(Object other) => other is EventsPermission;

  @override
  int get hashCode => domain.hashCode;
}

/// Host capabilities bridged into the dart_eval sandbox for external
/// (downloaded) plugins.
///
/// Before this existed, an external plugin's hooks could only react to
/// whatever JSON value the host happened to pass them (`onTrackStart`'s
/// track, `onLibraryScan`'s file path) — there was no way for sandboxed
/// code to reach back into the app for anything, which is the real reason
/// a plugin needing to *do* something (not just passively react) had to
/// become a bundled, compiled-in plugin instead. This is the first bridged
/// capability: read-only library access.
///
/// Registered against the synthesized library
/// `package:omnis/sandbox_api.dart` — no real Dart source file backs it;
/// dart_eval synthesizes a `Library` for a URI that has bridge declarations
/// but no compiled unit (`Compiler.compileSources`), so a plugin just does:
/// ```dart
/// import 'package:omnis/sandbox_api.dart';
///
/// dynamic onSomeHook(dynamic arg) async {
///   final tracks = await loadLibraryTracks();
///   // tracks is a List of the same JSON-shaped Maps onTrackStart's
///   // argument already uses (BaseTrack.toJson()).
/// }
/// ```
/// Every bridged function checks its own permission at call time via
/// `runtime.assertPermission` — a plugin whose manifest didn't declare the
/// matching capability gets a catchable exception in the guest, not silent
/// empty data, the same "fail loud enough to notice, not silently wrong"
/// principle the rest of this codebase's degrade paths follow.
class PluginSandboxBridge implements EvalPlugin {
  const PluginSandboxBridge();

  static const libraryUri = 'package:omnis/sandbox_api.dart';

  @override
  String get identifier => 'omnis_sandbox_bridge';

  @override
  void configureForCompile(BridgeDeclarationRegistry registry) {
    registry.defineBridgeTopLevelFunction(const BridgeFunctionDeclaration(
        libraryUri,
        'loadLibraryTracks',
        BridgeFunctionDef(
          returns: BridgeTypeAnnotation(BridgeTypeRef(CoreTypes.future, [
            BridgeTypeAnnotation(BridgeTypeRef(CoreTypes.dynamic)),
          ])),
          params: [],
          namedParams: [],
        )));
  }

  @override
  void configureForRuntime(Runtime runtime) {
    runtime.registerBridgeFunc(
        libraryUri, 'loadLibraryTracks', const _LoadLibraryTracks().call);
  }
}

class _LoadLibraryTracks implements EvalCallable {
  const _LoadLibraryTracks();

  @override
  $Value? call(Runtime runtime, $Value? target, List<$Value?> args) {
    runtime.assertPermission(LibraryReadPermission.domain);
    // recursive: true is required, not cosmetic — a shallow $List.wrap
    // leaves each track's Map (and its own nested Lists, e.g. `artists`)
    // as plain unwrapped Dart values. That's fine for a value only ever
    // handed back out to the host untouched (like a hook's argument), but
    // guest bytecode indexing into it (`tracks[0]['title']`) expects a
    // $Value at every level and throws resuming the Await opcode
    // otherwise — confirmed by hitting exactly that failure with a plain
    // $List.wrap here before switching to Runtime.wrap(recursive: true).
    final future = LibraryRepository.instance.load().then<$Value>((tracks) =>
        runtime.wrap(tracks.map((t) => t.toJson()).toList(),
            recursive: true));
    return $Future.wrap(future);
  }
}
