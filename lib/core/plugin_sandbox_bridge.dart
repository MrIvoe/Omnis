import 'package:dart_eval/dart_eval_bridge.dart';
import 'package:dart_eval/dart_eval_security.dart';
import 'package:dart_eval/stdlib/core.dart';
import 'package:http/http.dart' as http;
import 'package:omnis/core/library_repository.dart';
import 'package:omnis/core/playlist_store.dart';
import 'package:omnis_plugin_api/base_track.dart';
import 'package:omnis_plugin_api/events.dart';
import 'package:omnis_plugin_api/plugin_context.dart';
import 'package:omnis_plugin_api/plugin_storage.dart';
import 'package:omnis_plugin_api/repeat_mode.dart';

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
/// `playbackPrevious`/`playbackSeek`, and — added alongside the queue/
/// volume bridge expansion — `setRepeatMode`/`setShuffleEnabled`, the same
/// risk class: a mode toggle, not a destination-changing or data-reaching
/// capability). Deliberately separate from [LibraryReadPermission] —
/// reading `currentTrack`/`queue`/`isPlaying`/`currentIndex` is inert, but
/// taking control of playback is exactly the kind of action a user should
/// see called out and confirm before installing a plugin, the same way
/// `storage`/`network` already are.
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

/// Permission domain gating queue-mutation bridge functions (`setQueue`,
/// `addTrack`, `playNext`, `removeTrack`, `playAt`) — separate from
/// [PlaybackControlPermission] because replacing or rebuilding the whole
/// queue is a materially bigger capability than pressing transport
/// buttons on whatever queue already exists: it's what actually lets a
/// sandboxed plugin *choose what plays*, not just control the existing
/// selection. A user should see "can change what's in your queue" called
/// out as its own line, not folded silently into "playback."
class QueuePermission implements Permission {
  const QueuePermission();

  static const domain = 'omnis.queue';

  @override
  List<String> get domains => const [domain];

  @override
  bool match([Object? data]) => true;

  @override
  bool operator ==(Object other) => other is QueuePermission;

  @override
  int get hashCode => domain.hashCode;
}

/// Permission domain gating volume/gain bridge functions (`getVolume`,
/// `setVolume`, `setGain`, `clearGain`). Separate from
/// [PlaybackControlPermission]/[QueuePermission] since a plugin like
/// ReplayGain or a per-device volume memory only ever needs this, never
/// transport or queue control — granular permissions mean the install
/// confirmation only ever names what a plugin actually does.
class VolumePermission implements Permission {
  const VolumePermission();

  static const domain = 'omnis.volume';

  @override
  List<String> get domains => const [domain];

  @override
  bool match([Object? data]) => true;

  @override
  bool operator ==(Object other) => other is VolumePermission;

  @override
  int get hashCode => domain.hashCode;
}

/// Permission domain gating the scoped per-plugin key-value storage
/// bridge (`pluginStorageGetString`/`SetString`/etc.) — backed by the
/// same [PluginStorage] a bundled plugin already gets, namespaced to this
/// plugin's own id. Deliberately distinct from the existing `storage`/
/// `filesystem` manifest permission, which grants raw, unscoped
/// [FilesystemPermission.any] file access: that's a fundamentally bigger
/// and more dangerous capability than "remember a few small values,"
/// and conflating the two would either force every plugin that just
/// wants to persist a setting into requesting broad file access, or
/// silently narrow what `storage` has always meant for plugins already
/// relying on it.
class PluginStatePermission implements Permission {
  const PluginStatePermission();

  static const domain = 'omnis.state';

  @override
  List<String> get domains => const [domain];

  @override
  bool match([Object? data]) => true;

  @override
  bool operator ==(Object other) => other is PluginStatePermission;

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

  /// The owning plugin's id, once known — `null` until
  /// `PluginRuntime.create`'s `createPlugin()` call returns and parses it
  /// out of the plugin's own metadata, since a bridge instance is built
  /// before that call runs. Every storage/gain bridge function below is
  /// only ever invoked later, from a hook call, by which point this is
  /// always set — see `PluginRuntime.create`'s own doc for the exact
  /// ordering. A closure (not a captured value) for the same reason
  /// [getContext] is: read fresh at call time, not snapshotted early.
  final String? Function() getPluginId;

  PluginStorage? _storage;

  /// Lazily built once per bridge (i.e. once per plugin instance), keyed
  /// by [getPluginId] — the exact same [PluginStorage] a bundled plugin
  /// already gets, just constructed for an external one instead.
  PluginStorage _requireStorage() {
    final id = getPluginId();
    if (id == null) {
      throw Exception('Plugin storage is not available before the plugin '
          'has finished loading.');
    }
    return _storage ??= PluginStorage(id);
  }

  /// Builds the `http.Client` [_HttpGet] performs its request with —
  /// injectable so tests can substitute `package:http/testing.dart`'s
  /// `MockClient` (the same pattern `RadioPlugin`/`OpenSubsonicPlugin`
  /// already use for a real, non-mocked-away HTTP call), while normal
  /// use just gets a plain `http.Client()` per call, closed immediately
  /// after — the same lifecycle the top-level `http.get()` function
  /// itself already has, just made overridable.
  final http.Client Function() _httpClientFactory;

  PluginSandboxBridge(this.getContext,
      {String? Function()? getPluginId, http.Client Function()? httpClientFactory})
      : getPluginId = getPluginId ?? (() => null),
        _httpClientFactory = httpClientFactory ?? (() => http.Client());

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
  static const _urlParam = BridgeParameter(
      'url', BridgeTypeAnnotation(BridgeTypeRef(CoreTypes.string)), false);

  // Every parameter below is its own `static const` field, matching
  // [_boolParam]/[_intParam]/[_urlParam] above exactly — a dart_eval 0.8.3
  // bug was traced to `BridgeParameter`s built by a helper *function*
  // (constructing a fresh, non-const instance per call) instead of a true
  // compile-time `const`: guest bytecode that boxed a literal argument for
  // one of those non-const-declared parameters crashed with a `BoxString`
  // null-cast deep inside dart_eval's own interpreter, reproduced in
  // isolation against bare dart_eval with no Omnis code involved at all.
  // Switching every declared parameter to a real `const` field, the same
  // as this bridge's original three, fixed it — worth the verbosity to
  // stay on a codegen path dart_eval actually exercises correctly.
  static const _dynTracksParam = BridgeParameter(
      'tracks', BridgeTypeAnnotation(BridgeTypeRef(CoreTypes.dynamic)), false);
  static const _dynTrackParam = BridgeParameter(
      'track', BridgeTypeAnnotation(BridgeTypeRef(CoreTypes.dynamic)), false);
  static const _startIndexParam = BridgeParameter(
      'startIndex', BridgeTypeAnnotation(BridgeTypeRef(CoreTypes.int)), false);
  static const _indexParam = BridgeParameter(
      'index', BridgeTypeAnnotation(BridgeTypeRef(CoreTypes.int)), false);
  static const _volumeParam = BridgeParameter(
      'volume', BridgeTypeAnnotation(BridgeTypeRef(CoreTypes.double)), false);
  static const _multiplierParam = BridgeParameter('multiplier',
      BridgeTypeAnnotation(BridgeTypeRef(CoreTypes.double)), false);
  static const _modeParam = BridgeParameter(
      'mode', BridgeTypeAnnotation(BridgeTypeRef(CoreTypes.string)), false);
  static const _enabledParam = BridgeParameter(
      'enabled', BridgeTypeAnnotation(BridgeTypeRef(CoreTypes.bool)), false);
  static const _keyParam = BridgeParameter(
      'key', BridgeTypeAnnotation(BridgeTypeRef(CoreTypes.string)), false);
  static const _valueStrParam = BridgeParameter(
      'value', BridgeTypeAnnotation(BridgeTypeRef(CoreTypes.string)), false);
  static const _valueBoolParam = BridgeParameter(
      'value', BridgeTypeAnnotation(BridgeTypeRef(CoreTypes.bool)), false);
  static const _valueNumParam = BridgeParameter(
      'value', BridgeTypeAnnotation(BridgeTypeRef(CoreTypes.double)), false);
  static const _valueIntParam = BridgeParameter(
      'value', BridgeTypeAnnotation(BridgeTypeRef(CoreTypes.int)), false);
  static const _eventTypeParam = BridgeParameter(
      'type', BridgeTypeAnnotation(BridgeTypeRef(CoreTypes.string)), false);
  static const _eventDataParam = BridgeParameter(
      'data', BridgeTypeAnnotation(BridgeTypeRef(CoreTypes.dynamic)), false);

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
    declare('httpGet', returns: _futureDynamicReturn, params: [_urlParam]);

    declare('setQueue',
        returns: _futureDynamicReturn,
        params: [_dynTracksParam, _startIndexParam]);
    declare('addTrack',
        returns: _futureDynamicReturn, params: [_dynTrackParam]);
    declare('playNextTrack',
        returns: _futureDynamicReturn, params: [_dynTrackParam]);
    declare('removeTrackAt',
        returns: _futureDynamicReturn, params: [_indexParam]);
    declare('playAt',
        returns: _futureDynamicReturn, params: [_indexParam]);

    declare('getVolume');
    declare('setVolume',
        returns: _futureDynamicReturn, params: [_volumeParam]);
    declare('setGain',
        returns: _futureDynamicReturn, params: [_multiplierParam]);
    declare('clearGain', returns: _futureDynamicReturn);

    declare('setRepeatMode',
        returns: _futureDynamicReturn, params: [_modeParam]);
    declare('setShuffleEnabled',
        returns: _futureDynamicReturn, params: [_enabledParam]);

    declare('pluginStorageGetString',
        returns: _futureDynamicReturn, params: [_keyParam]);
    declare('pluginStorageSetString',
        returns: _futureDynamicReturn,
        params: [_keyParam, _valueStrParam]);
    declare('pluginStorageGetBool',
        returns: _futureDynamicReturn, params: [_keyParam]);
    declare('pluginStorageSetBool',
        returns: _futureDynamicReturn,
        params: [_keyParam, _valueBoolParam]);
    declare('pluginStorageGetDouble',
        returns: _futureDynamicReturn, params: [_keyParam]);
    declare('pluginStorageSetDouble',
        returns: _futureDynamicReturn,
        params: [_keyParam, _valueNumParam]);
    declare('pluginStorageGetInt',
        returns: _futureDynamicReturn, params: [_keyParam]);
    declare('pluginStorageSetInt',
        returns: _futureDynamicReturn,
        params: [_keyParam, _valueIntParam]);
    declare('pluginStorageRemove',
        returns: _futureDynamicReturn, params: [_keyParam]);

    declare('emitEvent',
        params: [_eventTypeParam, _eventDataParam]);
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
    runtime.registerBridgeFunc(
        libraryUri, 'httpGet', _HttpGet(_httpClientFactory).call);

    runtime.registerBridgeFunc(
        libraryUri, 'setQueue', _SetQueue(getContext).call);
    runtime.registerBridgeFunc(
        libraryUri, 'addTrack', _AddTrack(getContext).call);
    runtime.registerBridgeFunc(
        libraryUri, 'playNextTrack', _PlayNextTrack(getContext).call);
    runtime.registerBridgeFunc(
        libraryUri, 'removeTrackAt', _RemoveTrackAt(getContext).call);
    runtime.registerBridgeFunc(
        libraryUri, 'playAt', _PlayAt(getContext).call);

    runtime.registerBridgeFunc(
        libraryUri, 'getVolume', _GetVolume(getContext).call);
    runtime.registerBridgeFunc(
        libraryUri, 'setVolume', _SetVolume(getContext).call);
    runtime.registerBridgeFunc(
        libraryUri, 'setGain', _SetGain(getContext, getPluginId).call);
    runtime.registerBridgeFunc(
        libraryUri, 'clearGain', _ClearGain(getContext, getPluginId).call);

    runtime.registerBridgeFunc(
        libraryUri, 'setRepeatMode', _SetRepeatMode(getContext).call);
    runtime.registerBridgeFunc(libraryUri, 'setShuffleEnabled',
        _SetShuffleEnabled(getContext).call);

    runtime.registerBridgeFunc(libraryUri, 'pluginStorageGetString',
        _PluginStorageGetString(_requireStorage).call);
    runtime.registerBridgeFunc(libraryUri, 'pluginStorageSetString',
        _PluginStorageSetString(_requireStorage).call);
    runtime.registerBridgeFunc(libraryUri, 'pluginStorageGetBool',
        _PluginStorageGetBool(_requireStorage).call);
    runtime.registerBridgeFunc(libraryUri, 'pluginStorageSetBool',
        _PluginStorageSetBool(_requireStorage).call);
    runtime.registerBridgeFunc(libraryUri, 'pluginStorageGetDouble',
        _PluginStorageGetDouble(_requireStorage).call);
    runtime.registerBridgeFunc(libraryUri, 'pluginStorageSetDouble',
        _PluginStorageSetDouble(_requireStorage).call);
    runtime.registerBridgeFunc(libraryUri, 'pluginStorageGetInt',
        _PluginStorageGetInt(_requireStorage).call);
    runtime.registerBridgeFunc(libraryUri, 'pluginStorageSetInt',
        _PluginStorageSetInt(_requireStorage).call);
    runtime.registerBridgeFunc(libraryUri, 'pluginStorageRemove',
        _PluginStorageRemove(_requireStorage).call);

    runtime.registerBridgeFunc(
        libraryUri, 'emitEvent', _EmitEvent(getContext).call);
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

/// The first real network capability bridged into the sandbox — before
/// this, declaring `network` in a manifest only populated the install-
/// confirmation dialog's text; there was no bridged function that could
/// actually reach the network at all, so the permission was purely
/// declarative. `runtime.assertPermission('network', url)` checks the
/// *requested URL itself* against whatever `NetworkPermission`(s)
/// `PluginRuntime.create` granted (a bare `network` grants
/// `NetworkPermission.any`; a scoped `network:host.example.com` grants
/// only that host) — the real dart_eval permission mechanism, not a
/// separate check this bridge would need to keep in sync. A non-2xx
/// response throws (the request reached the network but the server said
/// no), matching this bridge's existing "fail loud enough to notice"
/// stance for a denied permission.
class _HttpGet implements EvalCallable {
  final http.Client Function() clientFactory;
  const _HttpGet(this.clientFactory);

  @override
  $Value? call(Runtime runtime, $Value? target, List<$Value?> args) {
    final url = args.isNotEmpty ? args[0]?.$value as String? : null;
    if (url == null || url.isEmpty) {
      throw Exception('httpGet requires a non-empty URL.');
    }
    runtime.assertPermission('network', url);
    final client = clientFactory();
    final future = client.get(Uri.parse(url)).then<$Value>((response) {
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
            'httpGet: server returned ${response.statusCode} for $url');
      }
      return $String(response.body);
    }).whenComplete(client.close);
    return $Future.wrap(future);
  }
}

/// Reads the attached [PluginContext], asserting [QueuePermission] or
/// [VolumePermission] first — the queue/volume counterpart of
/// [_requireContext] above, kept separate rather than generalizing that
/// helper's third parameter further, since the two permission families
/// were added in separate passes for separate reasons (see each
/// permission class's own doc).
PluginContext _requireContextFor(
    Runtime runtime, PluginContext? Function() getContext, String domain) {
  runtime.assertPermission(domain);
  final context = getContext();
  if (context == null) {
    throw Exception('Playback is not available yet.');
  }
  return context;
}

BaseTrack _trackFromArg($Value? arg) {
  final reified = arg?.$reified;
  if (reified is! Map) {
    throw Exception('Expected a track Map.');
  }
  return BaseTrack.fromJson(Map<String, dynamic>.from(reified));
}

class _SetQueue implements EvalCallable {
  final PluginContext? Function() getContext;
  const _SetQueue(this.getContext);

  @override
  $Value? call(Runtime runtime, $Value? target, List<$Value?> args) {
    final context =
        _requireContextFor(runtime, getContext, QueuePermission.domain);
    final tracksRaw = args.isNotEmpty ? args[0]?.$reified : null;
    if (tracksRaw is! List) {
      throw Exception('setQueue requires a List of tracks.');
    }
    final tracks = tracksRaw
        .whereType<Map>()
        .map((m) => BaseTrack.fromJson(Map<String, dynamic>.from(m)))
        .toList();
    final startIndex =
        args.length > 1 ? (args[1]?.$value as int? ?? 0) : 0;
    return $Future.wrap(context
        .setQueue(tracks, startIndex: startIndex)
        .then((_) => const $null()));
  }
}

class _AddTrack implements EvalCallable {
  final PluginContext? Function() getContext;
  const _AddTrack(this.getContext);

  @override
  $Value? call(Runtime runtime, $Value? target, List<$Value?> args) {
    final context =
        _requireContextFor(runtime, getContext, QueuePermission.domain);
    final track = _trackFromArg(args.isNotEmpty ? args[0] : null);
    return $Future.wrap(context.addTrack(track).then((_) => const $null()));
  }
}

class _PlayNextTrack implements EvalCallable {
  final PluginContext? Function() getContext;
  const _PlayNextTrack(this.getContext);

  @override
  $Value? call(Runtime runtime, $Value? target, List<$Value?> args) {
    final context =
        _requireContextFor(runtime, getContext, QueuePermission.domain);
    final track = _trackFromArg(args.isNotEmpty ? args[0] : null);
    return $Future.wrap(context.playNext(track).then((_) => const $null()));
  }
}

class _RemoveTrackAt implements EvalCallable {
  final PluginContext? Function() getContext;
  const _RemoveTrackAt(this.getContext);

  @override
  $Value? call(Runtime runtime, $Value? target, List<$Value?> args) {
    final context =
        _requireContextFor(runtime, getContext, QueuePermission.domain);
    final index = args.isNotEmpty ? (args[0]?.$value as int? ?? -1) : -1;
    return $Future.wrap(
        context.removeTrack(index).then((_) => const $null()));
  }
}

class _PlayAt implements EvalCallable {
  final PluginContext? Function() getContext;
  const _PlayAt(this.getContext);

  @override
  $Value? call(Runtime runtime, $Value? target, List<$Value?> args) {
    final context =
        _requireContextFor(runtime, getContext, QueuePermission.domain);
    final index = args.isNotEmpty ? (args[0]?.$value as int? ?? 0) : 0;
    return $Future.wrap(context.playAt(index).then((_) => const $null()));
  }
}

class _GetVolume implements EvalCallable {
  final PluginContext? Function() getContext;
  const _GetVolume(this.getContext);

  @override
  $Value? call(Runtime runtime, $Value? target, List<$Value?> args) {
    final context =
        _requireContextFor(runtime, getContext, VolumePermission.domain);
    return runtime.wrap(context.volume);
  }
}

class _SetVolume implements EvalCallable {
  final PluginContext? Function() getContext;
  const _SetVolume(this.getContext);

  @override
  $Value? call(Runtime runtime, $Value? target, List<$Value?> args) {
    final context =
        _requireContextFor(runtime, getContext, VolumePermission.domain);
    final volume =
        args.isNotEmpty ? (args[0]?.$value as num?)?.toDouble() ?? 0.0 : 0.0;
    return $Future.wrap(
        context.setVolume(volume).then((_) => const $null()));
  }
}

/// Gain contributions are keyed by [getPluginId], never a caller-supplied
/// string — letting a sandboxed plugin pick its own key would let it
/// clobber or clear a *different* plugin's gain contribution (bundled or
/// external) by guessing/reusing its source string. Forcing the key to
/// the plugin's own id makes that impossible: a plugin can only ever
/// touch its own contribution, exactly the isolation `context.setGain`'s
/// own "every plugin uses its own source key" contract already assumes
/// bundled plugins police themselves.
class _SetGain implements EvalCallable {
  final PluginContext? Function() getContext;
  final String? Function() getPluginId;
  const _SetGain(this.getContext, this.getPluginId);

  @override
  $Value? call(Runtime runtime, $Value? target, List<$Value?> args) {
    final context =
        _requireContextFor(runtime, getContext, VolumePermission.domain);
    final id = getPluginId() ?? 'unknown_plugin';
    final multiplier =
        args.isNotEmpty ? (args[0]?.$value as num?)?.toDouble() ?? 1.0 : 1.0;
    return $Future.wrap(
        context.setGain(id, multiplier).then((_) => const $null()));
  }
}

class _ClearGain implements EvalCallable {
  final PluginContext? Function() getContext;
  final String? Function() getPluginId;
  const _ClearGain(this.getContext, this.getPluginId);

  @override
  $Value? call(Runtime runtime, $Value? target, List<$Value?> args) {
    final context =
        _requireContextFor(runtime, getContext, VolumePermission.domain);
    final id = getPluginId() ?? 'unknown_plugin';
    return $Future.wrap(context.clearGain(id).then((_) => const $null()));
  }
}

class _SetRepeatMode implements EvalCallable {
  final PluginContext? Function() getContext;
  const _SetRepeatMode(this.getContext);

  @override
  $Value? call(Runtime runtime, $Value? target, List<$Value?> args) {
    final context = _requireContextFor(
        runtime, getContext, PlaybackControlPermission.domain);
    final name = args.isNotEmpty ? args[0]?.$value as String? : null;
    final mode = RepeatMode.values
        .where((m) => m.name == name)
        .cast<RepeatMode?>()
        .firstWhere((_) => true, orElse: () => null);
    if (mode == null) {
      throw Exception('setRepeatMode: unknown mode "$name" — expected one '
          'of ${RepeatMode.values.map((m) => m.name).join(', ')}.');
    }
    return $Future.wrap(
        context.setRepeatMode(mode).then((_) => const $null()));
  }
}

class _SetShuffleEnabled implements EvalCallable {
  final PluginContext? Function() getContext;
  const _SetShuffleEnabled(this.getContext);

  @override
  $Value? call(Runtime runtime, $Value? target, List<$Value?> args) {
    final context = _requireContextFor(
        runtime, getContext, PlaybackControlPermission.domain);
    final enabled = args.isNotEmpty ? args[0]?.$value as bool? ?? false : false;
    return $Future.wrap(
        context.setShuffleEnabled(enabled).then((_) => const $null()));
  }
}

/// Warms [storage] (idempotent — a no-op if already warm) before reading
/// one of its normally-synchronous getters, since a bridge call has no
/// other opportunity to await [PluginStorage.initialize] first the way
/// `PluginManager` does for a bundled plugin before its `initialize()`
/// hook runs.
Future<T> _readAfterWarm<T>(PluginStorage storage, T Function() read) async {
  await storage.initialize();
  return read();
}

String _requireStringArg(List<$Value?> args, int index, String fnName) {
  final value = args.length > index ? args[index]?.$value as String? : null;
  if (value == null) {
    throw Exception('$fnName requires a non-null String argument.');
  }
  return value;
}

class _PluginStorageGetString implements EvalCallable {
  final PluginStorage Function() requireStorage;
  const _PluginStorageGetString(this.requireStorage);

  @override
  $Value? call(Runtime runtime, $Value? target, List<$Value?> args) {
    runtime.assertPermission(PluginStatePermission.domain);
    final key = _requireStringArg(args, 0, 'pluginStorageGetString');
    final storage = requireStorage();
    return $Future.wrap(_readAfterWarm(storage, () => storage.getString(key))
        .then<$Value?>((v) => v == null ? null : $String(v)));
  }
}

class _PluginStorageSetString implements EvalCallable {
  final PluginStorage Function() requireStorage;
  const _PluginStorageSetString(this.requireStorage);

  @override
  $Value? call(Runtime runtime, $Value? target, List<$Value?> args) {
    runtime.assertPermission(PluginStatePermission.domain);
    final key = _requireStringArg(args, 0, 'pluginStorageSetString');
    final value = _requireStringArg(args, 1, 'pluginStorageSetString');
    return $Future.wrap(
        requireStorage().setString(key, value).then((_) => const $null()));
  }
}

class _PluginStorageGetBool implements EvalCallable {
  final PluginStorage Function() requireStorage;
  const _PluginStorageGetBool(this.requireStorage);

  @override
  $Value? call(Runtime runtime, $Value? target, List<$Value?> args) {
    runtime.assertPermission(PluginStatePermission.domain);
    final key = _requireStringArg(args, 0, 'pluginStorageGetBool');
    final storage = requireStorage();
    return $Future.wrap(_readAfterWarm(storage, () => storage.getBool(key))
        .then<$Value?>((v) => v == null ? null : $bool(v)));
  }
}

class _PluginStorageSetBool implements EvalCallable {
  final PluginStorage Function() requireStorage;
  const _PluginStorageSetBool(this.requireStorage);

  @override
  $Value? call(Runtime runtime, $Value? target, List<$Value?> args) {
    runtime.assertPermission(PluginStatePermission.domain);
    final key = _requireStringArg(args, 0, 'pluginStorageSetBool');
    final value = args.length > 1 ? args[1]?.$value as bool? ?? false : false;
    return $Future.wrap(
        requireStorage().setBool(key, value).then((_) => const $null()));
  }
}

class _PluginStorageGetDouble implements EvalCallable {
  final PluginStorage Function() requireStorage;
  const _PluginStorageGetDouble(this.requireStorage);

  @override
  $Value? call(Runtime runtime, $Value? target, List<$Value?> args) {
    runtime.assertPermission(PluginStatePermission.domain);
    final key = _requireStringArg(args, 0, 'pluginStorageGetDouble');
    final storage = requireStorage();
    return $Future.wrap(_readAfterWarm(storage, () => storage.getDouble(key))
        .then<$Value?>((v) => v == null ? null : runtime.wrap(v)));
  }
}

class _PluginStorageSetDouble implements EvalCallable {
  final PluginStorage Function() requireStorage;
  const _PluginStorageSetDouble(this.requireStorage);

  @override
  $Value? call(Runtime runtime, $Value? target, List<$Value?> args) {
    runtime.assertPermission(PluginStatePermission.domain);
    final key = _requireStringArg(args, 0, 'pluginStorageSetDouble');
    final value =
        args.length > 1 ? (args[1]?.$value as num?)?.toDouble() ?? 0.0 : 0.0;
    return $Future.wrap(
        requireStorage().setDouble(key, value).then((_) => const $null()));
  }
}

class _PluginStorageGetInt implements EvalCallable {
  final PluginStorage Function() requireStorage;
  const _PluginStorageGetInt(this.requireStorage);

  @override
  $Value? call(Runtime runtime, $Value? target, List<$Value?> args) {
    runtime.assertPermission(PluginStatePermission.domain);
    final key = _requireStringArg(args, 0, 'pluginStorageGetInt');
    final storage = requireStorage();
    return $Future.wrap(_readAfterWarm(storage, () => storage.getInt(key))
        .then<$Value?>((v) => v == null ? null : runtime.wrap(v)));
  }
}

class _PluginStorageSetInt implements EvalCallable {
  final PluginStorage Function() requireStorage;
  const _PluginStorageSetInt(this.requireStorage);

  @override
  $Value? call(Runtime runtime, $Value? target, List<$Value?> args) {
    runtime.assertPermission(PluginStatePermission.domain);
    final key = _requireStringArg(args, 0, 'pluginStorageSetInt');
    final value = args.length > 1 ? args[1]?.$value as int? ?? 0 : 0;
    return $Future.wrap(
        requireStorage().setInt(key, value).then((_) => const $null()));
  }
}

class _PluginStorageRemove implements EvalCallable {
  final PluginStorage Function() requireStorage;
  const _PluginStorageRemove(this.requireStorage);

  @override
  $Value? call(Runtime runtime, $Value? target, List<$Value?> args) {
    runtime.assertPermission(PluginStatePermission.domain);
    final key = _requireStringArg(args, 0, 'pluginStorageRemove');
    return $Future.wrap(requireStorage().remove(key).then((_) => const $null()));
  }
}

/// Outbound event emission — the counterpart `_wireEventForwarding`'s own
/// doc comment (`plugin_manager.dart`) flagged as deliberately out of
/// scope when inbound forwarding was built. A small, fixed, reviewed
/// switch over known event types — never a generic serializer — the same
/// shape [providedCapabilityHooks] already uses for `provides:`: adding a
/// second emittable event type is one more `case`, not new plumbing, and
/// a sandboxed plugin can never construct or emit an event type this
/// switch doesn't explicitly know about.
class _EmitEvent implements EvalCallable {
  final PluginContext? Function() getContext;
  const _EmitEvent(this.getContext);

  @override
  $Value? call(Runtime runtime, $Value? target, List<$Value?> args) {
    runtime.assertPermission(EventsPermission.domain);
    final context = getContext();
    if (context == null) return const $null();
    final type = args.isNotEmpty ? args[0]?.$value as String? : null;
    final data = args.length > 1 ? args[1]?.$reified : null;
    switch (type) {
      case 'favorite_changed':
        if (data is Map) {
          final trackId = data['trackId']?.toString() ?? '';
          final isFavorite = data['isFavorite'] == true;
          context.events.emit(FavoriteChangedEvent(trackId, isFavorite));
        }
      default:
        throw Exception('emitEvent: unknown event type "$type".');
    }
    return const $null();
  }
}
