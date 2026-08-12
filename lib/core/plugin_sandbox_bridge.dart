import 'package:dart_eval/dart_eval_bridge.dart';
import 'package:dart_eval/dart_eval_security.dart';
import 'package:dart_eval/stdlib/core.dart';
import 'package:omnis/core/library_repository.dart';
import 'package:omnis/core/playlist_store.dart';
import 'package:omnis_plugin_api/plugin_context.dart';

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

/// Permission domain gating the *mutating* transport-control bridge
/// functions (`playbackPlay`/`playbackPause`/`playbackNext`/
/// `playbackPrevious`/`playbackSeek`). Deliberately separate from
/// [LibraryReadPermission] — reading `currentTrack`/`queue`/`isPlaying`/
/// `currentIndex` is inert, but taking control of playback is exactly the
/// kind of action a user should see called out and confirm before
/// installing a plugin, the same way `storage`/`network` already are.
class PlaybackControlPermission implements Permission {
  const PlaybackControlPermission();

  static const domain = 'omnis.playback';

  @override
  List<String> get domains => const [domain];

  @override
  bool match([Object? data]) => true;

  @override
  bool operator ==(Object other) => other is PlaybackControlPermission;

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
  /// Returns the app's current [PluginContext], or `null` if none is
  /// attached yet. A closure, not a captured value — `PluginManager`
  /// attaches its context after some plugins have already loaded (see
  /// `attachContext`'s "reaches plugins registered before and after it"
  /// contract), so every playback bridge call must re-read the live
  /// context rather than one snapshotted at `PluginRuntime.create` time.
  final PluginContext? Function() getContext;

  const PluginSandboxBridge(this.getContext);

  static const libraryUri = 'package:omnis/sandbox_api.dart';

  @override
  String get identifier => 'omnis_sandbox_bridge';

  static const _dynamicReturn =
      BridgeTypeAnnotation(BridgeTypeRef(CoreTypes.dynamic));
  static const _futureDynamicReturn = BridgeTypeAnnotation(
      BridgeTypeRef(CoreTypes.future, [_dynamicReturn]));
  static const _boolParam =
      BridgeParameter('wrap', BridgeTypeAnnotation(BridgeTypeRef(CoreTypes.bool)), false);
  static const _intParam = BridgeParameter(
      'positionMs', BridgeTypeAnnotation(BridgeTypeRef(CoreTypes.int)), false);

  @override
  void configureForCompile(BridgeDeclarationRegistry registry) {
    void declare(String name,
        {BridgeTypeAnnotation returns = _dynamicReturn,
        List<BridgeParameter> params = const []}) {
      registry.defineBridgeTopLevelFunction(BridgeFunctionDeclaration(
          libraryUri,
          name,
          BridgeFunctionDef(returns: returns, params: params, namedParams: const [])));
    }

    declare('loadLibraryTracks', returns: _futureDynamicReturn);
    declare('getCurrentTrack');
    declare('getQueue');
    declare('getIsPlaying');
    declare('getCurrentIndex');
    declare('loadPlaylists', returns: _futureDynamicReturn);
    declare('playbackPlay', returns: _futureDynamicReturn);
    declare('playbackPause', returns: _futureDynamicReturn);
    declare('playbackNext',
        returns: _futureDynamicReturn, params: [_boolParam]);
    declare('playbackPrevious', returns: _futureDynamicReturn);
    declare('playbackSeek',
        returns: _futureDynamicReturn, params: [_intParam]);
  }

  @override
  void configureForRuntime(Runtime runtime) {
    runtime.registerBridgeFunc(
        libraryUri, 'loadLibraryTracks', const _LoadLibraryTracks().call);
    runtime.registerBridgeFunc(
        libraryUri, 'getCurrentTrack', _GetCurrentTrack(getContext).call);
    runtime.registerBridgeFunc(
        libraryUri, 'getQueue', _GetQueue(getContext).call);
    runtime.registerBridgeFunc(
        libraryUri, 'getIsPlaying', _GetIsPlaying(getContext).call);
    runtime.registerBridgeFunc(
        libraryUri, 'getCurrentIndex', _GetCurrentIndex(getContext).call);
    runtime.registerBridgeFunc(
        libraryUri, 'loadPlaylists', const _LoadPlaylists().call);
    runtime.registerBridgeFunc(
        libraryUri, 'playbackPlay', _PlaybackPlay(getContext).call);
    runtime.registerBridgeFunc(
        libraryUri, 'playbackPause', _PlaybackPause(getContext).call);
    runtime.registerBridgeFunc(
        libraryUri, 'playbackNext', _PlaybackNext(getContext).call);
    runtime.registerBridgeFunc(libraryUri, 'playbackPrevious',
        _PlaybackPrevious(getContext).call);
    runtime.registerBridgeFunc(
        libraryUri, 'playbackSeek', _PlaybackSeek(getContext).call);
  }
}

/// Reads the attached [PluginContext], asserting [PlaybackControlPermission]
/// or [LibraryReadPermission] first — shared by every playback-state and
/// transport-control bridge function below so each one is a one-line body.
PluginContext _requireContext(
    Runtime runtime, PluginContext? Function() getContext, String domain) {
  runtime.assertPermission(domain);
  final context = getContext();
  if (context == null) {
    throw Exception('Playback is not available yet.');
  }
  return context;
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

class _LoadPlaylists implements EvalCallable {
  const _LoadPlaylists();

  @override
  $Value? call(Runtime runtime, $Value? target, List<$Value?> args) {
    runtime.assertPermission(LibraryReadPermission.domain);
    final future = PlaylistStore.instance.load().then<$Value>((playlists) =>
        runtime.wrap(playlists.map((p) => p.toJson()).toList(),
            recursive: true));
    return $Future.wrap(future);
  }
}

class _GetCurrentTrack implements EvalCallable {
  final PluginContext? Function() getContext;
  const _GetCurrentTrack(this.getContext);

  @override
  $Value? call(Runtime runtime, $Value? target, List<$Value?> args) {
    final context =
        _requireContext(runtime, getContext, LibraryReadPermission.domain);
    final track = context.currentTrack;
    return track == null
        ? null
        : runtime.wrap(track.toJson(), recursive: true);
  }
}

class _GetQueue implements EvalCallable {
  final PluginContext? Function() getContext;
  const _GetQueue(this.getContext);

  @override
  $Value? call(Runtime runtime, $Value? target, List<$Value?> args) {
    final context =
        _requireContext(runtime, getContext, LibraryReadPermission.domain);
    return runtime.wrap(
        context.queue.map((t) => t.toJson()).toList(),
        recursive: true);
  }
}

class _GetIsPlaying implements EvalCallable {
  final PluginContext? Function() getContext;
  const _GetIsPlaying(this.getContext);

  @override
  $Value? call(Runtime runtime, $Value? target, List<$Value?> args) {
    final context =
        _requireContext(runtime, getContext, LibraryReadPermission.domain);
    return runtime.wrap(context.isPlaying);
  }
}

class _GetCurrentIndex implements EvalCallable {
  final PluginContext? Function() getContext;
  const _GetCurrentIndex(this.getContext);

  @override
  $Value? call(Runtime runtime, $Value? target, List<$Value?> args) {
    final context =
        _requireContext(runtime, getContext, LibraryReadPermission.domain);
    return runtime.wrap(context.currentIndex);
  }
}

class _PlaybackPlay implements EvalCallable {
  final PluginContext? Function() getContext;
  const _PlaybackPlay(this.getContext);

  @override
  $Value? call(Runtime runtime, $Value? target, List<$Value?> args) {
    final context = _requireContext(
        runtime, getContext, PlaybackControlPermission.domain);
    return $Future.wrap(context.play().then((_) => const $null()));
  }
}

class _PlaybackPause implements EvalCallable {
  final PluginContext? Function() getContext;
  const _PlaybackPause(this.getContext);

  @override
  $Value? call(Runtime runtime, $Value? target, List<$Value?> args) {
    final context = _requireContext(
        runtime, getContext, PlaybackControlPermission.domain);
    return $Future.wrap(context.pause().then((_) => const $null()));
  }
}

class _PlaybackNext implements EvalCallable {
  final PluginContext? Function() getContext;
  const _PlaybackNext(this.getContext);

  @override
  $Value? call(Runtime runtime, $Value? target, List<$Value?> args) {
    final context = _requireContext(
        runtime, getContext, PlaybackControlPermission.domain);
    final wrap = args.isNotEmpty ? args[0]?.$value as bool? ?? false : false;
    return $Future.wrap(
        context.next(wrap: wrap).then((didAdvance) => $bool(didAdvance)));
  }
}

class _PlaybackPrevious implements EvalCallable {
  final PluginContext? Function() getContext;
  const _PlaybackPrevious(this.getContext);

  @override
  $Value? call(Runtime runtime, $Value? target, List<$Value?> args) {
    final context = _requireContext(
        runtime, getContext, PlaybackControlPermission.domain);
    return $Future.wrap(
        context.previous().then((didAdvance) => $bool(didAdvance)));
  }
}

class _PlaybackSeek implements EvalCallable {
  final PluginContext? Function() getContext;
  const _PlaybackSeek(this.getContext);

  @override
  $Value? call(Runtime runtime, $Value? target, List<$Value?> args) {
    final context = _requireContext(
        runtime, getContext, PlaybackControlPermission.domain);
    final positionMs = args.isNotEmpty ? args[0]?.$value as int? ?? 0 : 0;
    return $Future.wrap(context
        .seek(Duration(milliseconds: positionMs))
        .then((_) => const $null()));
  }
}
