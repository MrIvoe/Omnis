import 'dart:async';
import 'dart:io';

/// spec §8's "filesystem watchers" gap (item 5) — automatically
/// triggers a rescan shortly after files change in a watched folder,
/// instead of requiring a manual "rescan" tap every time. Desktop-only
/// by design: Android already gets live results from `on_audio_query`'s
/// MediaStore index (see `MediaScanner._scanAndroid`), which the OS
/// itself keeps current, so a filesystem watcher there would just be
/// redundant background work — this class doesn't know or care about
/// that distinction itself, the caller decides whether to [start] it.
///
/// Debounces bursts of events (a batch copy/move fires many individual
/// filesystem events, one per file) into a single rescan after
/// [quietPeriod] of no further activity, rather than rescanning on
/// every single event.
class LibraryWatcher {
  final Future<void> Function() _onSettled;
  final Stream<FileSystemEvent> Function(String path) _watch;
  final Duration _quietPeriod;

  StreamSubscription<FileSystemEvent>? _subscription;
  Timer? _debounce;

  LibraryWatcher({
    required Future<void> Function() onSettled,
    Stream<FileSystemEvent> Function(String path)? watch,
    Duration quietPeriod = const Duration(seconds: 3),
  })  : _onSettled = onSettled,
        _watch = watch ?? ((path) => Directory(path).watch(recursive: true)),
        _quietPeriod = quietPeriod;

  /// Whether [start] has been called without a matching [stop] — not a
  /// guarantee the underlying OS watch actually succeeded (a
  /// platform/sandbox that throws from `Directory.watch` degrades
  /// silently, see [start]'s own doc), just this object's own intent.
  bool get isWatching => _subscription != null;

  /// Starts watching [path]. A platform/sandbox that doesn't support
  /// `Directory.watch` (some containers/restricted environments throw
  /// rather than returning an empty stream) degrades to "not watching"
  /// rather than crashing — the same "denial degrades, never blocks
  /// boot" contract `OmnisPermissions` already follows for permission
  /// gating. Calling [start] again (e.g. the watched folder changed in
  /// Settings) replaces whatever was previously watched.
  void start(String path) {
    stop();
    try {
      _subscription = _watch(path).listen(
        (_) => _scheduleRescan(),
        onError: (_) {},
      );
    } catch (_) {
      // Unsupported platform/sandbox — watching just never starts.
    }
  }

  void _scheduleRescan() {
    _debounce?.cancel();
    _debounce = Timer(_quietPeriod, () {
      unawaited(_onSettled());
    });
  }

  /// Stops watching and cancels any pending debounced rescan that
  /// hasn't fired yet.
  void stop() {
    _debounce?.cancel();
    _debounce = null;
    _subscription?.cancel();
    _subscription = null;
  }
}
