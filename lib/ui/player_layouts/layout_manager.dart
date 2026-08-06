import 'dart:async';

import 'package:omnis/core/bootstrap.dart' show locator;
import 'package:omnis/ui/player_layouts/declarative/declarative_layout.dart';
import 'package:omnis/ui/player_layouts/declarative/layout_installer.dart';
import 'package:omnis/ui/player_layouts/declarative/layout_manifest.dart';
import 'package:omnis/ui/player_layouts/player_layout.dart';
import 'package:omnis/ui/player_layouts/registry.dart';

/// Owns the combined set of Now Playing layouts: the six bundled ones
/// (`createPlayerLayouts()`) plus whatever the user has imported via
/// [LayoutInstaller]. `NowPlayingPage` and the Settings picker both read
/// through this instead of the static registry directly, so an installed
/// layout shows up everywhere immediately.
class LayoutManager {
  final LayoutInstaller _installer;
  final List<DeclarativeLayout> _installed = [];
  final StreamController<List<PlayerLayout>> _changes =
      StreamController.broadcast();
  bool _disposed = false;

  LayoutManager({LayoutInstaller? installer})
      : _installer = installer ?? LayoutInstaller();

  /// Every selectable layout: bundled first, then imported.
  List<PlayerLayout> get allLayouts =>
      List.unmodifiable([...createPlayerLayouts(), ..._installed]);

  /// Fires whenever a layout is installed or removed.
  Stream<List<PlayerLayout>> get changes => _changes.stream;

  /// Load previously-installed layouts from disk. Call once at startup.
  ///
  /// Defensively drops any on-disk layout whose id collides with a
  /// bundled one — [_validateAndPersist] should never let one get written
  /// in the first place, but a stale file from before that check existed,
  /// or a future bug, must not silently start shadowing a built-in layout
  /// on the very next launch.
  Future<void> loadInstalled() async {
    final manifests = await _installer.listInstalled();
    final reserved = createPlayerLayouts().map((l) => l.id).toSet();
    _installed
      ..clear()
      ..addAll(manifests
          .where((m) => !reserved.contains(m.id))
          .map(DeclarativeLayout.new));
    _emit();
  }

  /// Install a layout from a direct link to its YAML/JSON text.
  Future<DeclarativeLayout> installFromUrl(String url) async {
    final text = await _installer.fetchFromUrl(url);
    return _validateAndPersist(text, sourceUrl: url);
  }

  /// Install a layout from a local file on disk.
  Future<DeclarativeLayout> installFromFile(String path) async {
    final text = await _installer.readFromFile(path);
    return _validateAndPersist(text, sourceUrl: 'file://$path');
  }

  /// Parses and validates [text] — including the reserved-id check —
  /// *before* anything is written to disk, so a rejected import never
  /// gets a chance to persist and resurrect itself on the next
  /// [loadInstalled].
  Future<DeclarativeLayout> _validateAndPersist(
    String text, {
    required String sourceUrl,
  }) async {
    final manifest = LayoutManifest.parse(text, sourceUrl: sourceUrl);
    if (manifest == null) {
      throw LayoutInstallException(
        'Not a valid layout file — a layout needs at least id, name, and '
        'a root node. See lib/ui/player_layouts/declarative/ for the format.',
      );
    }
    final reserved = createPlayerLayouts().map((l) => l.id).toSet();
    if (reserved.contains(manifest.id)) {
      // A layout can't shadow a built-in one — resolve() below always
      // prefers the bundled list, so a colliding import would silently
      // never be selectable; reject it up front instead so the failure
      // is visible at install time.
      throw LayoutInstallException(
        'The id "${manifest.id}" is used by a built-in layout — pick a '
        'different id in the layout file and try again.',
      );
    }
    await _installer.persist(manifest, text);
    _installed.removeWhere((l) => l.id == manifest.id);
    final layout = DeclarativeLayout(manifest);
    _installed.add(layout);
    _emit();
    return layout;
  }

  /// Remove an imported layout. No-op for a bundled layout (nothing to
  /// remove; there's no file on disk for it).
  Future<void> uninstall(PlayerLayout layout) async {
    if (layout is! DeclarativeLayout) return;
    await _installer.uninstall(layout.id);
    _installed.removeWhere((l) => l.id == layout.id);
    _emit();
  }

  /// Resolve a layout by id, bundled layouts taking priority, falling
  /// back to the first bundled layout (Standard) when nothing matches —
  /// e.g. an imported layout was uninstalled after being selected.
  PlayerLayout resolve(String id) {
    for (final layout in allLayouts) {
      if (layout.id == id) return layout;
    }
    return allLayouts.first;
  }

  void _emit() {
    if (!_changes.isClosed) _changes.add(allLayouts);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _changes.close();
  }
}

/// Build and register the app-wide [LayoutManager] exactly once.
///
/// Lives here (`lib/ui/`) rather than alongside [ensureCoreReady] in
/// `lib/core/bootstrap.dart` on purpose: a [LayoutManager] deals entirely
/// in `Widget build()` — it's a UI-layer concept — and `lib/core/` must
/// never import anything from `lib/ui/` or `lib/plugins/` (see
/// `main_core.dart`'s doc comment). This keeps that invariant intact while
/// still using the same GetIt locator and the same "call from both
/// `main()` and the page that actually needs it" idempotent pattern as
/// `ensureCoreReady`.
Future<LayoutManager> ensureLayoutManagerReady() async {
  if (locator.isRegistered<LayoutManager>()) {
    return locator<LayoutManager>();
  }
  final manager = LayoutManager();
  await manager.loadInstalled();
  if (!locator.isRegistered<LayoutManager>()) {
    locator.registerSingleton<LayoutManager>(manager);
  }
  return locator<LayoutManager>();
}
