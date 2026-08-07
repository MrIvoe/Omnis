import 'dart:async';

import 'package:omnis/core/bootstrap.dart' show locator;
import 'package:omnis/ui/theme/declarative/theme_installer.dart';
import 'package:omnis/ui/theme/declarative/theme_manifest.dart';

/// Owns the set of user-imported themes, the theme equivalent of
/// `LayoutManager`. There's no "bundled theme manifest" list to merge
/// against the way layouts merge with `createPlayerLayouts()` — the four
/// built-in presets are [AppThemePreset] entries handled directly by
/// [OmnisTheme]/[AppSettings], not [ThemeManifest]s — so [allThemes] here
/// is purely what the user has imported.
class ThemeManager {
  final ThemeInstaller _installer;
  final List<ThemeManifest> _installed = [];
  final StreamController<List<ThemeManifest>> _changes =
      StreamController.broadcast();
  bool _disposed = false;

  ThemeManager({ThemeInstaller? installer})
      : _installer = installer ?? ThemeInstaller();

  /// Every imported theme.
  List<ThemeManifest> get allThemes => List.unmodifiable(_installed);

  /// Fires whenever a theme is installed or removed.
  Stream<List<ThemeManifest>> get changes => _changes.stream;

  /// Load previously-installed themes from disk. Call once at startup.
  Future<void> loadInstalled() async {
    final manifests = await _installer.listInstalled();
    _installed
      ..clear()
      ..addAll(manifests);
    _emit();
  }

  /// Install a theme from a direct link to its YAML/JSON text.
  Future<ThemeManifest> installFromUrl(String url) async {
    final text = await _installer.fetchFromUrl(url);
    return _validateAndPersist(text, sourceUrl: url);
  }

  /// Install a theme from a local file on disk.
  Future<ThemeManifest> installFromFile(String path) async {
    final text = await _installer.readFromFile(path);
    return _validateAndPersist(text, sourceUrl: 'file://$path');
  }

  Future<ThemeManifest> _validateAndPersist(
    String text, {
    required String sourceUrl,
  }) async {
    final manifest = ThemeManifest.parse(text, sourceUrl: sourceUrl);
    if (manifest == null) {
      throw ThemeInstallException(
        'Not a valid theme file — a theme needs at least id, name, and a '
        'colors.primary value. See lib/ui/theme/declarative/ for the '
        'format.',
      );
    }
    await _installer.persist(manifest, text);
    _installed.removeWhere((t) => t.id == manifest.id);
    _installed.add(manifest);
    _emit();
    return manifest;
  }

  /// Remove an imported theme.
  Future<void> uninstall(ThemeManifest manifest) async {
    await _installer.uninstall(manifest.id);
    _installed.removeWhere((t) => t.id == manifest.id);
    _emit();
  }

  /// Resolve an installed theme by id, or `null` if it's not (or no
  /// longer) installed — e.g. a previously-selected theme was uninstalled.
  ThemeManifest? resolve(String id) {
    for (final theme in _installed) {
      if (theme.id == id) return theme;
    }
    return null;
  }

  void _emit() {
    if (!_changes.isClosed) _changes.add(allThemes);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _changes.close();
  }
}

/// Build and register the app-wide [ThemeManager] exactly once — same
/// idempotent "call from wherever needs it" pattern as
/// `ensureLayoutManagerReady`. Lives here (`lib/ui/`) for the same reason
/// that does: `lib/core/` must never import anything from `lib/ui/`.
Future<ThemeManager> ensureThemeManagerReady() async {
  if (locator.isRegistered<ThemeManager>()) {
    return locator<ThemeManager>();
  }
  final manager = ThemeManager();
  await manager.loadInstalled();
  if (!locator.isRegistered<ThemeManager>()) {
    locator.registerSingleton<ThemeManager>(manager);
  }
  return locator<ThemeManager>();
}
