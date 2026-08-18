import 'dart:async';

import 'package:flutter/material.dart';
import 'package:omnis/core/plugin_manager.dart';

/// Renders whatever plugins inject at [locationId] via `uiSlot()`.
///
/// [PluginManager.uiSlot] and the `now_playing_overlay` / `now_playing_bottom`
/// / `library_header` / `settings_page` / `sidebar_item` location IDs it
/// documents have existed since the Core hook system was built, but no page
/// ever called it — the injection point was real plumbing with nothing
/// plugged into either end. This widget is the missing consumer.
///
/// Two kinds of payload are supported:
///  - A real Flutter [Widget] — only possible from bundled (in-process)
///    plugins, since they're compiled Dart and can import `package:flutter`.
///  - A declarative `Map` describing a tiny widget (`{'type': 'text', ...}`,
///    `{'type': 'badge', 'text': ..., 'icon': ...}`, `{'type': 'toggle',
///    'text': ..., 'value': bool, 'hook': 'hookName'}`, `{'type':
///    'button', 'text': ..., 'hook': 'hookName'}`, or `{'type': 'nav_item',
///    'text': ..., 'icon': ..., 'hook': ...}`) — the only way a
///    *downloaded* plugin can contribute UI, since dart_eval plugins are
///    sandboxed away from `dart:ui` and cannot construct real widgets. The
///    interactive types call back into the plugin's own declared `hook`
///    function via [PluginManager.callPluginHook] (a fire-and-forget
///    mutation — a toggle flip, a button press) or
///    [PluginManager.callPluginHookForResult] (`nav_item`'s tap, which
///    needs the hook's *return value* to know what panel to show) rather
///    than returning a real Dart closure, which a sandboxed plugin cannot
///    produce.
///
///    `nav_item` is the one exception to "downloaded plugins only": a
///    *bundled* (in-process) plugin may also return a `nav_item` Map, with
///    its `hook` field set to a real `Widget Function(BuildContext)`
///    instead of a `String` — since a bundled plugin is compiled Dart, it
///    can put a real closure inside a `Map` it constructs itself (nothing
///    crosses the dart_eval sandbox boundary for it, unlike an external
///    plugin's payload, which must stay JSON-shaped). Tapping that variant
///    pushes the returned builder as a real page via `Navigator.push`
///    directly, no hook-name indirection involved. Tapping the `String`
///    (external-plugin) variant instead fetches a small declarative panel
///    from the hook and opens it in a bottom sheet, built from this same
///    closed vocabulary — a sandboxed plugin can never open an arbitrary
///    page, only ever hand back more of this same restricted shape.
///
/// Anything else (a bare String, null, garbage from a misbehaving plugin)
/// is rendered defensively or skipped — a malformed value must never crash
/// the page it's injected into. `uiSlot` calls are already sandboxed by
/// [PluginManager], so a *throwing* plugin can't reach here at all; this
/// covers a plugin that returns something nonsensical instead.
class PluginSlotView extends StatefulWidget {
  final PluginManager pluginManager;
  final String locationId;
  final Axis direction;

  const PluginSlotView({
    super.key,
    required this.pluginManager,
    required this.locationId,
    this.direction = Axis.horizontal,
  });

  @override
  State<PluginSlotView> createState() => _PluginSlotViewState();
}

class _PluginSlotViewState extends State<PluginSlotView> {
  List<dynamic> _items = const [];
  StreamSubscription<List<ManagedPlugin>>? _sub;

  @override
  void initState() {
    super.initState();
    _refresh();
    // Re-fetch whenever plugins are installed/enabled/disabled, not just
    // once at first build — otherwise enabling a plugin that injects a
    // badge would require leaving and re-entering the page to see it.
    _sub = widget.pluginManager.changes.listen((_) => _refresh());
  }

  @override
  void didUpdateWidget(covariant PluginSlotView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.locationId != widget.locationId ||
        oldWidget.pluginManager != widget.pluginManager) {
      _refresh();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final items = await widget.pluginManager.uiSlot(widget.locationId);
    if (mounted) setState(() => _items = items);
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const SizedBox.shrink();
    final rendered = _items
        .map((item) {
          final pluginId =
              item is Map && item['_pluginId'] is String ? item['_pluginId'] as String : null;
          return renderPluginSlotItem(
            context,
            item,
            onAction: pluginId == null
                ? null
                : (hook, args) =>
                    widget.pluginManager.callPluginHook(pluginId, hook, args),
            onFetchPanel: pluginId == null
                ? null
                : (hook, args) => widget.pluginManager
                    .callPluginHookForResult(pluginId, hook, args),
          );
        })
        .whereType<Widget>()
        .toList();
    if (rendered.isEmpty) return const SizedBox.shrink();
    return widget.direction == Axis.vertical
        ? Column(mainAxisSize: MainAxisSize.min, children: rendered)
        : Wrap(spacing: 8, runSpacing: 8, children: rendered);
  }
}

/// Fires an interactive `uiSlot` item's declared `hook` — e.g. a toggle's
/// `onChanged` or a button's `onPressed` — with whatever arguments that
/// interaction implies (a toggle passes its new value).
typedef PluginSlotAction = void Function(String hook, List<dynamic> args);

/// Fetches a `nav_item`'s panel by calling its declared `hook` and
/// returning whatever the plugin hands back — distinct from
/// [PluginSlotAction], which is fire-and-forget, because a `nav_item` tap
/// needs the hook's *return value* (the panel to display), not just to
/// trigger it.
typedef PluginSlotPanelFetcher = Future<dynamic> Function(
  String hook,
  List<dynamic> args,
);

/// Renders a single `uiSlot()` payload: a real [Widget] (bundled plugins),
/// a declarative `Map` (`{'type': 'text'|'badge'|'toggle'|'button', 'text':
/// ..., ...}` — the only way a `dart_eval`-sandboxed downloaded plugin can
/// contribute UI), or a bare non-empty [String]. Anything else — `null`,
/// garbage from a misbehaving plugin — renders as nothing rather than
/// crashing the page it's injected into.
///
/// [onAction], when the item is an interactive type (`toggle`/`button`/
/// the external-plugin variant of `nav_item`'s nested panel items), is
/// called with the item's declared `hook` name and any arguments that
/// interaction implies. `null` for a non-interactive item, a real [Widget]
/// (which wires its own real closures directly, having no need for a
/// hook-name indirection), or a caller that doesn't know which plugin
/// produced this item (e.g. before `_pluginId` stamping existed).
///
/// [onFetchPanel], when the item is a `nav_item` whose `hook` is a
/// `String` (an external/sandboxed plugin), is called to fetch the small
/// declarative panel the tap should open in a bottom sheet. `null` for
/// every other item type, or the same "caller doesn't know the plugin"
/// cases [onAction] covers.
///
/// Shared by [PluginSlotView] (aggregates every enabled plugin at one
/// location) and `PluginSettingsPage` (renders exactly one plugin's
/// `'plugin_settings'` payload, which already knows its own plugin and
/// wires [onAction]/[onFetchPanel] directly rather than through
/// `_pluginId`).
Widget? renderPluginSlotItem(
  BuildContext context,
  dynamic item, {
  PluginSlotAction? onAction,
  PluginSlotPanelFetcher? onFetchPanel,
}) {
  if (item is Widget) return item;
  if (item is Map) {
    return _renderDeclarative(context, item, onAction, onFetchPanel);
  }
  if (item is String && item.trim().isNotEmpty) return Text(item);
  return null;
}

Widget? _renderDeclarative(
  BuildContext context,
  Map item,
  PluginSlotAction? onAction,
  PluginSlotPanelFetcher? onFetchPanel,
) {
  final type = item['type']?.toString();
  final text = item['text']?.toString();
  if (text == null || text.isEmpty) return null;
  final theme = Theme.of(context);

  switch (type) {
    case 'text':
      return Text(text, style: theme.textTheme.bodySmall);
    case 'badge':
      final iconName = item['icon']?.toString();
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: theme.colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (iconName != null) ...[
              Icon(_iconFor(iconName),
                  size: 14, color: theme.colorScheme.onSecondaryContainer),
              const SizedBox(width: 6),
            ],
            Text(
              text,
              style: TextStyle(
                color: theme.colorScheme.onSecondaryContainer,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    case 'toggle':
      final hook = item['hook']?.toString();
      final value = item['value'];
      if (hook == null || value is! bool) return null;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text, style: theme.textTheme.bodyMedium),
          Switch(
            value: value,
            onChanged: onAction == null
                ? null
                : (newValue) => onAction(hook, [newValue]),
          ),
        ],
      );
    case 'button':
      final hook = item['hook']?.toString();
      if (hook == null) return null;
      return OutlinedButton(
        onPressed: onAction == null ? null : () => onAction(hook, const []),
        child: Text(text),
      );
    case 'nav_item':
      final hook = item['hook'];
      final isExternalHook = hook is String && hook.isNotEmpty;
      final isBundledPageHook = hook is WidgetBuilder;
      if (!isExternalHook && !isBundledPageHook) return null;
      final iconName = item['icon']?.toString();
      return _PluginNavItemTile(
        text: text,
        icon: _iconFor(iconName ?? ''),
        hook: hook,
        onAction: onAction,
        onFetchPanel: onFetchPanel,
      );
    default:
      return null;
  }
}

/// Renders a single `nav_item` payload as an icon-above-label tile
/// matching [NavigationDestination]/[NavigationRailDestination]'s visual
/// style, and handles its tap per this file's own module doc: a `String`
/// [hook] (a downloaded/sandboxed plugin) fetches a declarative panel via
/// [onFetchPanel] and opens it in a bottom sheet; a [WidgetBuilder] [hook]
/// (a bundled/in-process plugin, unrestricted) is pushed directly as a
/// real page via `Navigator.push`.
class _PluginNavItemTile extends StatelessWidget {
  final String text;
  final IconData icon;
  final dynamic hook;
  final PluginSlotAction? onAction;
  final PluginSlotPanelFetcher? onFetchPanel;

  const _PluginNavItemTile({
    required this.text,
    required this.icon,
    required this.hook,
    required this.onAction,
    required this.onFetchPanel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _handleTap(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 24, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 4),
            Text(
              text,
              style: theme.textTheme.labelSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleTap(BuildContext context) async {
    final hookValue = hook;
    if (hookValue is WidgetBuilder) {
      // Bundled (in-process) plugin: unrestricted — a real page, pushed
      // by the host UI exactly the way any other in-app navigation would.
      Navigator.of(context).push(MaterialPageRoute(builder: hookValue));
      return;
    }
    if (hookValue is String) {
      // Downloaded/sandboxed plugin: the hook can only ever hand back
      // more of this same closed declarative vocabulary, never a real
      // page — that panel opens in a bottom sheet instead.
      final fetch = onFetchPanel;
      if (fetch == null) return;
      // A genuinely empty args list here hits a real dart_eval bug: a
      // sandboxed hook function that returns a Map/List literal with
      // string values throws "type 'Null' is not a subtype of type
      // 'String'" while building that literal, but only when called with
      // zero arguments — the same one-argument shape every other guest
      // hook in this bridge already uses (`uiSlot(locationId)`,
      // `onTrackStart(track)`, ...) works fine. A single `null` argument
      // keeps the call one-argument-shaped without implying any real
      // input the hook is expected to use.
      final result = await fetch(hookValue, const [null]);
      if (!context.mounted) return;
      final panelItems = _panelItemsFrom(result);
      if (panelItems.isEmpty) return;
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: panelItems
                .map((panelItem) => renderPluginSlotItem(
                      sheetContext,
                      panelItem,
                      onAction: onAction,
                      onFetchPanel: onFetchPanel,
                    ))
                .whereType<Widget>()
                .toList(),
          ),
        ),
      );
    }
  }

  /// Normalises a hook's result into the list of items to render in the
  /// panel — a `List` is used as-is, a single `Map`/`String` becomes a
  /// one-item list, and anything else (`null`, garbage from a misbehaving
  /// plugin) becomes an empty list, matching this file's "malformed value
  /// renders nothing, never crashes" guarantee.
  static List<dynamic> _panelItemsFrom(dynamic result) {
    if (result is List) return result;
    if (result == null) return const [];
    return [result];
  }
}

IconData _iconFor(String name) {
  switch (name) {
    case 'info':
      return Icons.info_outline;
    case 'music':
      return Icons.music_note;
    case 'history':
      return Icons.history;
    case 'star':
      return Icons.star_outline;
    default:
      return Icons.extension;
  }
}
