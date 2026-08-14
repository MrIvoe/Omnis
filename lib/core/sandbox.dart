import 'dart:async';

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

  /// Default wall-clock budget for a single hook call. Closes the "no
  /// CPU/time budget on a hook call" gap called out in
  /// docs/PLUGIN_SECURITY.md: [PluginSandbox] previously isolated only
  /// *faults* (a thrown exception), not *resource use* — a plugin with an
  /// infinite loop or a stuck await inside a hook could hang the caller
  /// indefinitely. This only bounds the `await` on [run]'s Future; it can't
  /// preempt synchronous, non-yielding work inside the interpreter (that
  /// would require a separate isolate), but it does guarantee callers of
  /// [run] always get control back within [defaultTimeout].
  static const Duration defaultTimeout = Duration(seconds: 8);

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
  ///
  /// [timeout] bounds how long [run] will wait for [operation] before
  /// abandoning it and recording a timeout failure — defaults to
  /// [defaultTimeout]. Pass `null` to wait indefinitely (not recommended
  /// for anything driven by untrusted downloaded plugin code).
  Future<T?> run<T>({
    required String pluginId,
    required String pluginName,
    required String hook,
    required Future<T?> Function() operation,
    Duration? timeout = defaultTimeout,
  }) async {
    try {
      final future = operation();
      return timeout == null ? await future : await future.timeout(timeout);
    } on TimeoutException {
      _record(PluginHealthRecord(
        pluginId: pluginId,
        pluginName: pluginName,
        hook: hook,
        message: 'Timed out after ${timeout!.inMilliseconds}ms',
        stackTrace: null,
        timestamp: DateTime.now(),
        reason: 'Plugin "$pluginName" took too long in $hook and was '
            'abandoned so the music keeps playing.',
      ));
      return null;
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

  /// Clear only [pluginId]'s health records — used after a plugin is
  /// reset, so its dashboard entry doesn't keep showing failures from
  /// before the reset once it's had a fresh start.
  void clearHealthFor(String pluginId) {
    _records.removeWhere((r) => r.pluginId == pluginId);
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
