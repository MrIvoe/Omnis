/// The URL of Omnis's own plugin catalog repository — where downloadable
/// (non-bundled) plugins live, split out of this repo so they can be
/// versioned and published independently of the app itself.
const omnisPluginsRepoUrl = 'https://github.com/MrIvoe/Omnis-Plugins';

/// One plugin published in [omnisPluginsRepoUrl], installable in a single
/// tap via `PluginInstaller.installFromUrl`'s `tree/branch/subfolder`
/// support — no URL to find or paste.
class CatalogPluginEntry {
  final String folder;
  final String name;
  final String description;
  const CatalogPluginEntry(
      {required this.folder, required this.name, required this.description});

  /// A `tree/main/<folder>` link into [omnisPluginsRepoUrl], which
  /// `PluginInstaller` resolves to "download the whole repo zip, but only
  /// extract and validate `<folder>`" — see its doc comment.
  String get installUrl => '$omnisPluginsRepoUrl/tree/main/$folder';

  factory CatalogPluginEntry.fromJson(Map<String, dynamic> json) =>
      CatalogPluginEntry(
        folder: json['folder'] as String,
        name: json['name'] as String,
        description: json['description'] as String? ?? '',
      );
}

/// The offline/fetch-failure fallback — item 30's catalog used to be
/// *only* this hardcoded list ("nothing queries GitHub to discover
/// plugins automatically"). `PluginInstaller.fetchCatalog()` now fetches
/// a real, live `catalog.json` published at the repo root of
/// [omnisPluginsRepoUrl]; this list is what the Plugins page falls back
/// to when that fetch fails (no network, GitHub unreachable, a
/// malformed response) so the catalog card is never simply empty.
/// **Keep this in sync with `catalog.json`** — it's the last-resort
/// safety net, not a second source of truth to maintain independently.
const List<CatalogPluginEntry> officialPluginCatalog = [
  CatalogPluginEntry(
    folder: 'sample_logger',
    name: 'Sample Logger',
    description: 'Minimal example plugin — logs track starts and library '
        'scans. Good starting point for writing your own.',
  ),
];

/// Item 26's "no 'install this dependency for me' flow" gap — a missing
/// declared dependency (`PluginManager.missingDependenciesFor`) is
/// already detected and surfaced, but there's no way to act on it
/// beyond manually finding and pasting the right URL. [id] is a missing
/// dependency's plugin id, exactly as another plugin's manifest declared
/// it; a catalog entry's own [CatalogPluginEntry.folder] is that same
/// id string for every bundled/published plugin this catalog knows
/// about (confirmed by `officialPluginCatalog`'s own `sample_logger`
/// entry matching its plugin id 1:1), so a plain equality match — not a
/// name/description search — is the correct, unambiguous lookup here.
/// Returns `null` when nothing in [catalog] matches: a missing
/// dependency that isn't in the discoverable catalog has nothing safe
/// to one-tap install, and callers should keep today's warning-only
/// behavior for it rather than offering a button that can't work.
CatalogPluginEntry? findCatalogEntryForPluginId(
  String id,
  List<CatalogPluginEntry> catalog,
) {
  for (final entry in catalog) {
    if (entry.folder == id) return entry;
  }
  return null;
}
