import 'package:flutter/foundation.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/library_store.dart';

/// The single in-memory source of truth for the persisted library.
///
/// Previously every page that needed the library — `home_page.dart`'s
/// mood player, `home_dashboard_page.dart`, `playlist_page.dart`, and
/// `library_page.dart` — called `LibraryStore.instance.load()`
/// independently, each in its own `initState`. `LibraryStore` itself has
/// no cache, so each of those calls re-read and re-parsed the entire
/// library JSON file from disk, and each page then held its own separate
/// copy of the result in its own widget state. Because `HomePage`'s
/// `IndexedStack` builds every tab immediately rather than lazily on
/// first visit, that meant up to four redundant disk reads before the
/// user ever switched a tab — and four copies that could silently drift
/// out of sync with each other.
///
/// This repository is now the only class that talks to [LibraryStore]
/// directly. [load] resolves once and caches the result in memory;
/// concurrent callers during that first load (all four pages construct in
/// the same frame) share the same in-flight [Future] rather than each
/// issuing their own disk read. [save] updates the in-memory copy,
/// notifies listeners, and persists.
///
/// Pages that only ever *read* the library (`home_dashboard_page.dart`,
/// `playlist_page.dart`, the mood player in `home_page.dart`) call [load]
/// instead of talking to [LibraryStore] directly, and [addListener] to
/// react when another page saves a change — that's what actually
/// delivers "a favorite toggled in Library is visible in Home without
/// Home needing its own reload trigger for it," not [load] alone.
/// `library_page.dart` owns the library's read/modify/write lifecycle
/// (scanning, tag edits, favorites, deletes) and calls [save] wherever it
/// previously called `LibraryStore.instance.save` — its existing local
/// `_tracks` field and `setState` patterns don't need to change, only
/// which class they persist through.
class LibraryRepository extends ChangeNotifier {
  LibraryRepository._();

  static final LibraryRepository instance = LibraryRepository._();

  List<BaseTrack> _tracks = const [];
  bool _loaded = false;
  Future<List<BaseTrack>>? _pendingLoad;

  /// The current in-memory library. Empty until [load] has resolved at
  /// least once. Unmodifiable — go through [save] to change it, so every
  /// change is persisted and every listener is notified.
  List<BaseTrack> get tracks => List.unmodifiable(_tracks);

  /// Whether [load] has resolved at least once this process.
  bool get isLoaded => _loaded;

  /// Loads the library into memory.
  ///
  /// Safe to call from every page's `initState` — after the first real
  /// load, subsequent calls return the already-loaded in-memory copy
  /// instantly instead of re-reading the file, unless [forceReload] is
  /// true (e.g. after a scan or an external change the caller knows
  /// about). Concurrent callers during an in-flight load share the same
  /// [Future] instead of each starting their own disk read.
  Future<List<BaseTrack>> load({bool forceReload = false}) {
    if (_loaded && !forceReload) return Future.value(tracks);
    if (_pendingLoad != null && !forceReload) return _pendingLoad!;
    final future = LibraryStore.instance.load().then((loaded) {
      _tracks = loaded;
      _loaded = true;
      _pendingLoad = null;
      notifyListeners();
      return tracks;
    });
    _pendingLoad = future;
    return future;
  }

  /// Replaces the in-memory library with [newTracks], notifies every
  /// listener immediately (matching the rest of the app's existing
  /// pattern of an instant local update followed by a persisted write —
  /// see `library_page.dart`'s own `setState` calls before each of its
  /// prior `LibraryStore.instance.save` calls), then persists.
  ///
  /// Copies [newTracks] rather than adopting the caller's own list
  /// object directly — `library_page.dart` passes its own live,
  /// repeatedly-mutated `_tracks` field here, and aliasing it would mean
  /// a later in-place mutation on that field (`_tracks[i] = updated`)
  /// silently changed this repository's "current" value before the next
  /// [save] call, with no [notifyListeners] for that change and no
  /// guarantee [tracks] readers elsewhere saw a consistent snapshot.
  ///
  /// [LibraryStore.save] already swallows its own errors as a
  /// best-effort persistence guarantee (a failure there must never crash
  /// the app), so this doesn't need its own try/catch on top of it.
  Future<void> save(List<BaseTrack> newTracks) async {
    _tracks = List<BaseTrack>.from(newTracks);
    _loaded = true;
    notifyListeners();
    await LibraryStore.instance.save(_tracks);
  }

  /// Test-only: resets in-memory state without touching the persisted
  /// file, so each test starts from a clean cache regardless of what an
  /// earlier test in the same file loaded.
  @visibleForTesting
  void resetForTesting() {
    _tracks = const [];
    _loaded = false;
    _pendingLoad = null;
  }
}
