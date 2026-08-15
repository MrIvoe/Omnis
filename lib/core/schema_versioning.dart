/// A single version-to-version upgrade step: given the *previous*
/// version's decoded payload, returns the next version's shape. Stored
/// per store, keyed by the version it upgrades *from* (so migration
/// `0` takes a v0 payload and returns a v1 one).
///
/// This file (`wrapVersioned`/`unwrapVersioned`/`runMigrations`) is the
/// shared versioned-envelope + migration-dispatch scaffold every
/// JSON-backed store in this app (`LibraryStore`, `PlaylistStore`,
/// `PlayHistoryStore`, `RecoveryJournal`) builds on — item 4's "no
/// schema migration system" gap. Before this, a future field rename or
/// shape change to any of those stores' persisted JSON had no real
/// upgrade path: an old file would either silently mis-parse under a
/// changed `fromJson`, or (thanks to this session's own
/// per-entry-defensive decoding work) just quietly drop the affected
/// records — safe, but not a real migration. Deliberately a small set
/// of free functions, not a class each store subclasses or mixes in —
/// every store here already has its own independent atomic-write/
/// per-entry-decode logic (matching how this session applied both of
/// *those* patterns individually to each store rather than through one
/// shared base type), and the one genuinely common piece across all
/// four is this envelope shape and the migration-dispatch loop, not the
/// surrounding read/write mechanics.
typedef SchemaMigration = dynamic Function(dynamic data);

/// Wraps [payload] in the standard versioned-envelope shape:
/// `{"schemaVersion": N, "data": payload}`. Always writes
/// [currentVersion] — there's never anything to migrate on write, only
/// on read, so a save always produces the newest known shape.
Map<String, dynamic> wrapVersioned(dynamic payload, int currentVersion) => {
      'schemaVersion': currentVersion,
      'data': payload,
    };

/// Reads the `(version, payload)` pair out of a store's raw decoded
/// JSON. Understands the pre-versioning "bare" shape every file this
/// app has ever written looks like today: no `schemaVersion` key at
/// all, because the payload itself — a bare list, a bare map, a bare
/// object — *is* the whole file. That shape decodes as version `0` with
/// [decoded] itself as the payload, so nothing already on disk needs a
/// one-time conversion pass; the very next `save()` from any store
/// upgrades it to the versioned envelope transparently, the same
/// "old data still reads fine, new data gets the new shape" contract
/// every additive `BaseTrack`/`PluginManifest` field already follows in
/// this codebase.
({int version, dynamic data}) unwrapVersioned(dynamic decoded) {
  if (decoded is Map && decoded.containsKey('schemaVersion')) {
    return (version: decoded['schemaVersion'] as int, data: decoded['data']);
  }
  return (version: 0, data: decoded);
}

/// Runs every migration step from [fromVersion] up to (not including)
/// [toVersion] in order, using whichever of [migrations] apply — a
/// store with nothing registered for a given version (the common case:
/// today, every store's map is empty, since nothing has needed a real
/// payload transformation yet) just leaves the payload as-is for that
/// step, so a gap in the map is a no-op, never an error.
dynamic runMigrations(
  dynamic data,
  int fromVersion,
  int toVersion,
  Map<int, SchemaMigration> migrations,
) {
  var result = data;
  for (var version = fromVersion; version < toVersion; version++) {
    final migrate = migrations[version];
    if (migrate != null) result = migrate(result);
  }
  return result;
}
