import 'dart:convert';
import 'dart:io';

import 'package:omnis/core/schema_versioning.dart';
import 'package:path_provider/path_provider.dart';

/// UI_SPEC §4's closed set of item kinds the pop-out sidebar (§3) can pin
/// — deliberately just the two this app already has stable, named,
/// user-owned collections for. The spec's fuller list (smart playlist,
/// library, provider, server, favorite album/artist, radio station,
/// shortcut) is a real, named, out-of-scope gap for a future pass, not
/// silently dropped — see `docs/OMNIS_2_0_FINISHED_TASK.md`'s entry for
/// this feature.
enum SidebarItemKind { playlist, mood }

/// One pinned entry. [refId] is a `Playlist.id` for [SidebarItemKind.
/// playlist], or a mood's display name (works for both a `CustomMood.name`
/// and a preset `IQueueBuilder.supportedQueries` entry — both are plain
/// strings already used as identity elsewhere in this app, e.g.
/// `MoodsPageState.playMood`) for [SidebarItemKind.mood]. Resolved to a
/// real label/tap target at render time by `GlobalSidebarDrawer`, not
/// cached here — a stale reference (the playlist/mood was since deleted)
/// is simply skipped when rendering, the same "a bad reference is
/// skipped, not a crash" discipline this app's other JSON-backed stores
/// already follow for a malformed record.
class SidebarItem {
  final SidebarItemKind kind;
  final String refId;

  const SidebarItem({required this.kind, required this.refId});

  Map<String, dynamic> toJson() => {'kind': kind.name, 'refId': refId};

  static SidebarItem? fromJson(Map<String, dynamic> json) {
    final kindName = json['kind'];
    final refId = json['refId'];
    if (kindName is! String || refId is! String) return null;
    SidebarItemKind? kind;
    for (final k in SidebarItemKind.values) {
      if (k.name == kindName) {
        kind = k;
        break;
      }
    }
    if (kind == null) return null;
    return SidebarItem(kind: kind, refId: refId);
  }
}

/// UI_SPEC §4's "group" — a named group of pinned items, all the same
/// [kind] (a simpler, still-real subset of the spec's fully mixed-kind
/// groups — see [SidebarItemKind]'s own doc for why). [id] is a stable
/// identity independent of [title] so renaming a section doesn't orphan
/// anything referencing it (nothing currently does, but the same
/// id-vs-display-name separation every other named collection in this app
/// already uses).
class SidebarSection {
  final String id;
  final String title;
  final SidebarItemKind kind;
  final List<SidebarItem> items;

  const SidebarSection({
    required this.id,
    required this.title,
    required this.kind,
    this.items = const [],
  });

  SidebarSection copyWith({String? title, List<SidebarItem>? items}) =>
      SidebarSection(
        id: id,
        title: title ?? this.title,
        kind: kind,
        items: items ?? this.items,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'kind': kind.name,
        'items': items.map((i) => i.toJson()).toList(),
      };

  static SidebarSection? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final title = json['title'];
    final kindName = json['kind'];
    if (id is! String || title is! String || kindName is! String) {
      return null;
    }
    SidebarItemKind? kind;
    for (final k in SidebarItemKind.values) {
      if (k.name == kindName) {
        kind = k;
        break;
      }
    }
    if (kind == null) return null;
    final rawItems = json['items'];
    final items = <SidebarItem>[];
    if (rawItems is List) {
      for (final entry in rawItems) {
        if (entry is! Map) continue;
        final item = SidebarItem.fromJson(Map<String, dynamic>.from(entry));
        if (item != null) items.add(item);
      }
    }
    return SidebarSection(id: id, title: title, kind: kind, items: items);
  }
}

/// The default sections a fresh install starts with — matches UI_SPEC
/// §3's own mockup ("MY PLAYLISTS" / "MY MOODS"), both empty until the
/// user pins something via the drawer's own "+ Add" affordance.
List<SidebarSection> defaultSidebarSections() => const [
      SidebarSection(
          id: 'my_playlists',
          title: 'My playlists',
          kind: SidebarItemKind.playlist),
      SidebarSection(
          id: 'my_moods', title: 'My moods', kind: SidebarItemKind.mood),
    ];

const _currentSchemaVersion = 1;
const _migrations = <int, SchemaMigration>{};

/// Persists the pop-out sidebar's configured sections — the same load/
/// save-JSON-file, caller-owns-the-list shape `PlaylistStore`/
/// `CustomMoodStore` already established.
class SidebarConfigStore {
  SidebarConfigStore._();

  static final SidebarConfigStore instance = SidebarConfigStore._();

  File? _file;

  Future<File> _getFile() async {
    if (_file != null) return _file!;
    final dir = await getApplicationDocumentsDirectory();
    _file = File('${dir.path}/omnis_sidebar_config.json');
    return _file!;
  }

  /// Loads the persisted sections, or [defaultSidebarSections] if none
  /// have ever been saved (distinct from "saved as empty," which a user
  /// who deletes every default section can genuinely reach) — never
  /// throws.
  Future<List<SidebarSection>> load() async {
    try {
      final file = await _getFile();
      if (!await file.exists()) return defaultSidebarSections();
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return defaultSidebarSections();
      final decoded = jsonDecode(raw);
      final unwrapped = unwrapVersioned(decoded);
      final migrated = runMigrations(unwrapped.data, unwrapped.version,
          _currentSchemaVersion, _migrations);
      if (migrated is! List) return defaultSidebarSections();
      final sections = <SidebarSection>[];
      for (final entry in migrated) {
        if (entry is! Map) continue;
        final section =
            SidebarSection.fromJson(Map<String, dynamic>.from(entry));
        if (section != null) sections.add(section);
      }
      return sections;
    } catch (e) {
      return defaultSidebarSections();
    }
  }

  /// Persist [sections]. Atomic write (sibling `.tmp` + rename), the same
  /// crash/power-loss-safe pattern every other JSON store in this app
  /// already uses.
  Future<void> save(List<SidebarSection> sections) async {
    try {
      final file = await _getFile();
      final json = jsonEncode(wrapVersioned(
          sections.map((s) => s.toJson()).toList(), _currentSchemaVersion));
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(json, flush: true);
      await tmp.rename(file.path);
    } catch (e) {
      // Best-effort persistence; a failure here must never crash the app.
    }
  }

  /// Test-only: drops the cached file handle so each test starts clean.
  void resetForTesting() {
    _file = null;
  }
}
