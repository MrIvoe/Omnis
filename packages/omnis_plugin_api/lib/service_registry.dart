import 'dart:async';

/// A capability lookup keyed by *interface* type, not concrete class.
///
/// This is the generalization of the pattern `PluginManager.bundled<T>()`
/// already used for concrete plugin types (`bundled<LyricsPlugin>()`).
/// That pattern works, but it means a caller has to know which concrete
/// plugin implements a feature — swapping `LyricsPlugin` for a future
/// `LrclibLyricsPlugin` would mean touching every call site. Here, a
/// plugin registers itself against the *interface* it implements
/// (`ILyricsProvider`, `IPlayHistoryProvider`, ...), and callers ask the
/// registry for that interface without ever naming the concrete plugin —
/// the same "ask for a capability, not an implementation" idea the
/// service currently reachable via [PluginContext] already applies to a
/// handful of hardcoded audio-engine operations, just generalized to
/// arbitrary plugin-defined capabilities.
///
/// A plugin registers (typically in `initialize()`/`enable()`) and
/// unregisters (in `disable()`/`dispose()`) itself explicitly — the
/// registry has no opinion about a plugin's enabled state; that's the
/// same responsibility plugins already have for gain contributions
/// (`ReplayGainPlugin`/`EqualizerPlugin` already clear their contribution
/// on `disable()`), just applied to service registration instead.
///
/// More than one implementation of the same interface can register at
/// once (e.g. multiple lyrics sources) — [get] returns the first
/// (primary) one, [getAll] returns every one, in registration order.
class ServiceRegistry {
  final Map<Type, List<Object>> _services = {};
  final StreamController<void> _changesController =
      StreamController<void>.broadcast();

  /// Fires whenever a service is registered or unregistered — lets UI
  /// react to a capability appearing/disappearing (e.g. a provider
  /// becoming available only once its plugin is enabled) without polling.
  Stream<void> get changes => _changesController.stream;

  /// Registers [service] as an implementation of [serviceType].
  ///
  /// [serviceType] is a normal value argument (not a generic type
  /// parameter inferred from [service]) deliberately: a plugin class can
  /// implement several interfaces, so the caller must say *which one*
  /// it's registering as — `registry.register(ILyricsProvider, this)`,
  /// not `registry.register(this)`, which would silently key the
  /// registration under the concrete class instead and never be found by
  /// [get]/[getAll] callers asking for the interface.
  void register(Type serviceType, Object service) {
    final list = _services.putIfAbsent(serviceType, () => []);
    if (!list.contains(service)) {
      list.add(service);
      _emit();
    }
  }

  /// Removes a previously [register]ed service.
  void unregister(Type serviceType, Object service) {
    final removed = _services[serviceType]?.remove(service) ?? false;
    if (removed) _emit();
  }

  /// The first (primary) registered implementation of [T], or `null` if
  /// nothing has registered one.
  T? get<T>() {
    final list = _services[T];
    if (list == null || list.isEmpty) return null;
    return list.first as T;
  }

  /// Every registered implementation of [T], in registration order.
  List<T> getAll<T>() {
    final list = _services[T];
    if (list == null || list.isEmpty) return const [];
    return List<T>.from(list.cast<T>());
  }

  /// Whether any implementation of [T] is currently registered.
  bool has<T>() => (_services[T]?.isNotEmpty ?? false);

  void _emit() {
    if (!_changesController.isClosed) _changesController.add(null);
  }

  Future<void> dispose() async {
    _services.clear();
    if (!_changesController.isClosed) {
      await _changesController.close();
    }
  }
}
