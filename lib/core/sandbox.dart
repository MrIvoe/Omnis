/// A single health record for a plugin failure.
///
/// These records power the "Plugin Health" dashboard. When a plugin
/// crashes, the record is surfaced here instead of crashing the app.
class PluginHealthRecord {
  /// Plugin id.
  final String pluginId;

  /// Plugin display name.
  final String pluginName;

  /// Hook that failed (e.g. `onTrackStart`).
  final String hook;

  /// Error message.
  final String message;

  /// Stack trace (best-effort).
  final String? stackTrace;

  /// When the failure happened.
  final DateTime timestamp;

  /// User-visible message (localised-friendly).
  final String reason;

  const PluginHealthRecord({
    required this.pluginId,
    required this.pluginName,
    required this.hook,
    required this.message,
    this.stackTrace,
    required this.timestamp,
    required this.reason,
  });
}

/// Sandbox that isolates plugin execution.
///
/// Every plugin call runs through [run]. If the plugin throws, the error is
/// recorded in [healthRecords] (backed by [healthListeners]) and `null` is
/// returned. The music player is never affected.
class PluginSandbox {
  final List<PluginHealthRecord> _records = [];
  final List<void Function(List<PluginHealthRecord>)> _healthListeners = [];

  /// Snapshot of all plugin health records.
  List<PluginHealthRecord> get healthRecords => List.unmodifiable(_records);

  /// Subscribe to health record changes (e.g. to update the dashboard UI).
  ///
  /// Callers must pair this with [removeHealthListener] in their `dispose`,
  /// otherwise every rebuilt page leaves a listener behind that holds its
  /// `setState` — and its whole element tree — alive forever.
  void addHealthListener(void Function(List<PluginHealthRecord>) listener) {
    _healthListeners.add(listener);
  }

  /// Unsubscribe a listener registered with [addHealthListener].
  void removeHealthListener(void Function(List<PluginHealthRecord>) listener) {
    _healthListeners.remove(listener);
  }

  /// Run [operation] inside the sandbox.
  ///
  /// [pluginId], [pluginName] and [hook] are used to tag any failure.
  /// Returns the operation result, or `null` on failure.
  Future<T?> run<T>({
    required String pluginId,
    required String pluginName,
    required String hook,
    required Future<T?> Function() operation,
  }) async {
    try {
      return await operation();
    } catch (e, st) {
      _record(PluginHealthRecord(
        pluginId: pluginId,
        pluginName: pluginName,
        hook: hook,
        message: '$e',
        stackTrace: '$st',
        timestamp: DateTime.now(),
        reason: 'Plugin "$pluginName" failed in $hook but the music '
            'continues playing.',
      ));
      return null;
    }
  }

  /// Synchronous counterpart to [run], for plugin-side code that can't be
  /// awaited (a `MusicPlugin` constructor, or [MusicPlugin.attach]).
  /// Returns the operation result, or `null` on failure.
  T? runSync<T>({
    required String pluginId,
    required String pluginName,
    required String hook,
    required T? Function() operation,
  }) {
    try {
      return operation();
    } catch (e, st) {
      _record(PluginHealthRecord(
        pluginId: pluginId,
        pluginName: pluginName,
        hook: hook,
        message: '$e',
        stackTrace: '$st',
        timestamp: DateTime.now(),
        reason: 'Plugin "$pluginName" failed in $hook but the music '
            'continues playing.',
      ));
      return null;
    }
  }

  /// Clear all health records (used by the dashboard's "Dismiss all").
  void clearHealth() {
    _records.clear();
    _notify();
  }

  void _record(PluginHealthRecord rec) {
    _records.add(rec);
    // Keep the dashboard bounded.
    if (_records.length > 200) {
      _records.removeRange(0, _records.length - 200);
    }
    _notify();
  }

  void _notify() {
    for (final listener in _healthListeners) {
      try {
        listener(List.unmodifiable(_records));
      } catch (_) {
        // A broken listener must not crash the core.
      }
    }
  }
}
