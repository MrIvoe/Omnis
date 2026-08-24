import 'package:flutter/material.dart';
import 'package:omnis/core/custom_mood.dart';
import 'package:omnis/core/plugin_manager.dart';
import 'package:omnis/core/playlist_store.dart';
import 'package:omnis/core/sidebar_config.dart';
import 'package:omnis/plugin_api/service_interfaces.dart';
import 'package:omnis/ui/home_navigation.dart';
import 'package:omnis/ui/home_page.dart' show MoodsPageState;
import 'package:omnis/ui/playlist_page.dart';
import 'package:omnis/ui/widgets/reorder_menu_button.dart';

/// UI_SPEC §3-5's "pop-out sidebar" — "a global sidebar drawer that can
/// be summoned from anywhere," "not just navigation... the user's
/// personal music command center." Built as a real Flutter [Drawer]
/// (`Scaffold.drawer`), which already gives §5's "Mobile drawer: swipe
/// from left" and "Floating: overlays content" for free — a drawer is,
/// by definition, an overlay reached by a gesture/tap, not permanently
/// occupying layout space. §5's other four modes (Compact, Pinned,
/// Hidden-behind-hotkey, Auto-hide-on-cursor-to-edge) are a real,
/// named, deliberately out-of-scope gap for a future pass — this is one
/// mode (functionally closest to "Floating"), not mode-switching UI.
///
/// §4's item kinds are scoped to [SidebarItemKind]'s two values
/// (playlist, mood) — see that enum's own doc for why the spec's fuller
/// list (smart playlist/library/provider/server/favorite album or
/// artist/radio station/shortcut) isn't built here. Sections are
/// likewise scoped to a fixed kind each (no mixed-kind custom groups,
/// no "add a new section" UI) — [defaultSidebarSections] seeds exactly
/// the two the spec's own mockup shows ("MY PLAYLISTS"/"MY MOODS").
///
/// Tapping a playlist switches to the Playlist tab and opens it (mirrors
/// the §37 command-palette's own `onSelectPlaylist` wiring in
/// `home_page.dart` exactly); tapping a mood plays it directly, custom or
/// preset (mirrors `MoodsPageState.playMood`/`playCustomMood` — resolved
/// here by checking the custom-mood list first, falling back to treating
/// the name as a preset `IQueueBuilder` query), reusing
/// `MoodsPageState`'s already-tested queue-building/snackbar-feedback
/// logic via the same `GlobalKey`-into-an-already-mounted-`IndexedStack`-
/// page pattern this app already established for
/// `HomeDashboardPageState.openCustomizeSheet`/`PlaylistPageState.
/// openPlaylist`/`MoodsPageState.playMood` itself.
class GlobalSidebarDrawer extends StatefulWidget {
  final PluginManager pluginManager;
  final int selectedIndex;
  final List<HomeDestinationInfo> destinations;

  /// The id of each entry in [destinations], in the same order — 1:1
  /// with `home_page.dart`'s own `destinationIds`. Needed so the "jump
  /// to Playlist" shortcut in [_selectPlaylist] can resolve `'playlist'`
  /// to whatever index it currently occupies, rather than assuming a
  /// fixed position (a bare literal here previously assumed core tab
  /// index 2, which broke the moment the core tab list's order/length
  /// changed — see [_selectPlaylist]'s own doc comment).
  final List<String> destinationIds;

  final GlobalKey<PlaylistPageState> playlistKey;
  final GlobalKey<MoodsPageState> moodsKey;

  /// Switches `HomePage`'s own selected tab — the drawer itself has no
  /// navigation state of its own, matching every other cross-tab jump in
  /// this app (the command palette's own `onSelectPlaylist`/
  /// `onSelectMood`).
  final ValueChanged<int> onSelectDestination;

  const GlobalSidebarDrawer({
    super.key,
    required this.pluginManager,
    required this.selectedIndex,
    required this.destinations,
    required this.destinationIds,
    required this.playlistKey,
    required this.moodsKey,
    required this.onSelectDestination,
  });

  @override
  State<GlobalSidebarDrawer> createState() => _GlobalSidebarDrawerState();
}

class _GlobalSidebarDrawerState extends State<GlobalSidebarDrawer> {
  List<SidebarSection> _sections = [];
  List<Playlist> _playlists = [];
  List<CustomMood> _customMoods = [];
  List<String> _presetMoods = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sections = await SidebarConfigStore.instance.load();
    final playlists = await PlaylistStore.instance.load();
    final customMoods = await CustomMoodStore.instance.load();
    final presetMoods = <String>{
      for (final builder
          in widget.pluginManager.services.getAll<IQueueBuilder>())
        ...builder.supportedQueries,
    }.toList();
    if (!mounted) return;
    setState(() {
      _sections = sections;
      _playlists = playlists;
      _customMoods = customMoods;
      _presetMoods = presetMoods;
      _loaded = true;
    });
  }

  Future<void> _persist() async {
    await SidebarConfigStore.instance.save(_sections);
  }

  /// Jumps to the Playlist tab before opening [playlist] — resolved by id
  /// via [GlobalSidebarDrawer.destinationIds] rather than a hardcoded
  /// index, since "Playlist"'s index among the core tabs isn't fixed
  /// (mirrors `home_page.dart`'s own id-to-index resolution). Falls back
  /// to `0` if `'playlist'` is somehow absent, matching that same
  /// fallback pattern — 'playlist' is a permanently-core id, so
  /// `indexOf` returning `-1` should never actually happen.
  void _selectPlaylist(Playlist playlist) {
    Navigator.of(context).pop();
    final playlistIndex = widget.destinationIds.indexOf('playlist');
    widget.onSelectDestination(playlistIndex < 0 ? 0 : playlistIndex);
    widget.playlistKey.currentState?.openPlaylist(playlist);
  }

  void _selectMood(String name) {
    Navigator.of(context).pop();
    CustomMood? custom;
    for (final m in _customMoods) {
      if (m.name == name) {
        custom = m;
        break;
      }
    }
    if (custom != null) {
      widget.moodsKey.currentState?.playCustomMood(custom);
    } else {
      widget.moodsKey.currentState?.playMood(name);
    }
  }

  Future<void> _addItem(SidebarSection section) async {
    final available = section.kind == SidebarItemKind.playlist
        ? _playlists
            .where((p) => !section.items.any((i) => i.refId == p.id))
            .map((p) => (id: p.id, label: p.name))
            .toList()
        : {..._presetMoods, ..._customMoods.map((m) => m.name)}
            .where((name) => !section.items.any((i) => i.refId == name))
            .map((name) => (id: name, label: name))
            .toList();
    if (available.isEmpty) return;
    final picked = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('Add to ${section.title}'),
        children: [
          for (final entry in available)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(entry.id),
              child: Text(entry.label),
            ),
        ],
      ),
    );
    if (picked == null) return;
    final updatedSection = section.copyWith(items: [
      ...section.items,
      SidebarItem(kind: section.kind, refId: picked),
    ]);
    setState(() {
      _sections = [
        for (final s in _sections)
          if (s.id == section.id) updatedSection else s,
      ];
    });
    await _persist();
  }

  Future<void> _removeItem(SidebarSection section, SidebarItem item) async {
    final updatedSection = section.copyWith(
      items: section.items.where((i) => i != item).toList(),
    );
    setState(() {
      _sections = [
        for (final s in _sections)
          if (s.id == section.id) updatedSection else s,
      ];
    });
    await _persist();
  }

  /// [oldIndex]/[newIndex] arrive in `ReorderableListView.onReorder`'s own
  /// convention — but critically, indexed by *rendered position*, i.e.
  /// position within `visible` below, not within `section.items`. That's
  /// not a choice this method makes: `ReorderableListView`'s `children:`
  /// constructor (used by `_buildSectionReorderList`) always numbers
  /// `onReorder` by position among the *supplied* children — here,
  /// `visible`, since any stale item (`_labelFor` == null) is never
  /// rendered as a child at all — regardless of what other bookkeeping
  /// this class does. [ReorderMenuButton] deliberately mirrors that same
  /// convention (see its own doc comment) so both paths feed this method
  /// identically.
  ///
  /// Splicing `moved` into the *full* `section.items` list therefore
  /// can't be a plain `removeAt`/`insert` at [oldIndex]/[newIndex] — those
  /// would silently target the wrong element the moment any stale item
  /// exists anywhere in the section (verified: with `[stale, p1, p2]`,
  /// moving p1 down past p2 arrives as visible-index `(0, 2)`; naively
  /// applied to the 3-item full list that removes `stale`, not `p1`).
  /// Instead: identify `moved` by its *visible* position, compute its new
  /// *visible* neighbor, then splice it into the full list immediately
  /// before that neighbor's own full-list position (or at the very end
  /// if it's now last) — every stale item's position relative to the
  /// visible items around it is left exactly as it was, and the visible
  /// ordering ends up exactly as the drag/menu action intended.
  Future<void> _reorderItem(
      SidebarSection section, int oldIndex, int newIndex) async {
    final visible = [
      for (final item in section.items)
        if (_labelFor(item) != null) item,
    ];
    if (oldIndex < 0 || oldIndex >= visible.length) return;
    if (newIndex > oldIndex) newIndex -= 1;
    final moved = visible[oldIndex];

    final newVisible = [...visible]..removeAt(oldIndex);
    final insertAt = newIndex.clamp(0, newVisible.length);
    newVisible.insert(insertAt, moved);
    final followingVisibleItem =
        insertAt + 1 < newVisible.length ? newVisible[insertAt + 1] : null;

    final items = [...section.items]..remove(moved);
    final insertFullIndex = followingVisibleItem == null
        ? items.length
        : items.indexOf(followingVisibleItem);
    items.insert(insertFullIndex, moved);

    final updatedSection = section.copyWith(items: items);
    setState(() {
      _sections = [
        for (final s in _sections)
          if (s.id == section.id) updatedSection else s,
      ];
    });
    await _persist();
  }

  /// Resolves [item] to a display label, or `null` if its referenced
  /// playlist/mood no longer exists — a stale reference is skipped when
  /// rendering rather than shown as a broken entry.
  String? _labelFor(SidebarItem item) {
    if (item.kind == SidebarItemKind.playlist) {
      final match = _playlists.where((p) => p.id == item.refId);
      return match.isEmpty ? null : match.first.name;
    }
    if (_presetMoods.contains(item.refId) ||
        _customMoods.any((m) => m.name == item.refId)) {
      return item.refId;
    }
    return null;
  }

  /// Builds [section]'s drag-to-reorder item list. Extracted to its own
  /// method (rather than inlined in the `ListView`'s `children` literal)
  /// so `visibleItems` — the items actually rendered, skipping any whose
  /// `_labelFor` has gone stale — can be computed once as a local
  /// variable and reused both for the drag handles and for each row's
  /// [ReorderMenuButton], which must index by the same "position among
  /// rendered children" convention `ReorderableListView.onReorder` itself
  /// uses (not `section.items`' own, possibly-larger index space).
  Widget _buildSectionReorderList(SidebarSection section) {
    final visibleItems = [
      for (final item in section.items)
        if (_labelFor(item) != null) item,
    ];
    return ReorderableListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      onReorder: (oldIndex, newIndex) =>
          _reorderItem(section, oldIndex, newIndex),
      children: [
        for (var i = 0; i < visibleItems.length; i++)
          ListTile(
            key: ValueKey('${section.id}_${visibleItems[i].refId}'),
            contentPadding: const EdgeInsets.only(left: 32, right: 8),
            title: Text(_labelFor(visibleItems[i])!),
            leading: ReorderableDragStartListener(
              index: i,
              child: const Icon(Icons.drag_indicator, size: 18),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ReorderMenuButton(
                  index: i,
                  lastIndex: visibleItems.length - 1,
                  onReorder: (oldIndex, newIndex) =>
                      _reorderItem(section, oldIndex, newIndex),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: 'Remove',
                  onPressed: () => _removeItem(section, visibleItems[i]),
                ),
              ],
            ),
            onTap: () => section.kind == SidebarItemKind.playlist
                ? _selectPlaylist(
                    _playlists.firstWhere((p) => p.id == visibleItems[i].refId))
                : _selectMood(visibleItems[i].refId),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Drawer(
      child: SafeArea(
        child: !_loaded
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                children: [
                  DrawerHeader(
                    decoration: BoxDecoration(color: theme.colorScheme.surface),
                    child: Align(
                      alignment: Alignment.bottomLeft,
                      child:
                          Text('OMNIS', style: theme.textTheme.headlineSmall),
                    ),
                  ),
                  for (var i = 0; i < widget.destinations.length; i++)
                    ListTile(
                      leading: Icon(widget.destinations[i].icon),
                      title: Text(widget.destinations[i].label),
                      selected: i == widget.selectedIndex,
                      onTap: () {
                        Navigator.of(context).pop();
                        widget.onSelectDestination(i);
                      },
                    ),
                  const Divider(),
                  for (final section in _sections) ...[
                    ListTile(
                      dense: true,
                      title: Text(
                        section.title.toUpperCase(),
                        style: theme.textTheme.labelSmall,
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.add, size: 20),
                        tooltip: 'Add to ${section.title}',
                        onPressed: () => _addItem(section),
                      ),
                    ),
                    _buildSectionReorderList(section),
                  ],
                ],
              ),
      ),
    );
  }
}
