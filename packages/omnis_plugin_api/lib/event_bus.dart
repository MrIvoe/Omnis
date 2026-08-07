import 'dart:async';

/// Typed publish/subscribe bus for decoupled plugin-to-plugin (and
/// plugin-to-UI) communication.
///
/// Before this, the only way for one plugin's state to reach another part
/// of the app was a direct lookup (`pluginManager.bundled<T>()`) followed
/// by reading a getter — workable for "the UI pulls a plugin's current
/// state to render a frame," but there was no way for a plugin to
/// *announce* something happened (a track was favorited, lyrics changed)
/// without the UI polling for it. Events fill that gap: a plugin emits a
/// plain data object describing what happened; anything else — another
/// plugin, a page, a widget — subscribes to that object's type without
/// either side knowing the other exists. Matching is by *exact* runtime
/// type, not `is`-subtyping, so a listener for one event never
/// accidentally also receives an unrelated one that happens to share a
/// supertype.
class EventBus {
  final StreamController<Object> _controller =
      StreamController<Object>.broadcast();

  /// Publishes [event] to every current subscriber of its exact type.
  /// A no-op after [dispose].
  void emit(Object event) {
    if (!_controller.isClosed) _controller.add(event);
  }

  /// A stream of events of exactly type [T].
  Stream<T> on<T>() => _controller.stream.where((e) => e is T).cast<T>();

  Future<void> dispose() async {
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }
}
