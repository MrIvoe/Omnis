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
///    'text': ..., 'value': bool, 'hook': 'hookName'}`, or `{'type':
///    'button', 'text': ..., 'hook': 'hookName'}`) — the only way a
///    *downloaded* plugin can contribute UI, since dart_eval plugins are
///    sandboxed away from `dart:ui` and cannot construct real widgets. The
///    two interactive types call back into the plugin's own declared
///    `hook` function via [PluginManager.callPluginHook] rather than
///    returning a real Dart closure, which a sandboxed plugin cannot
///    produce.
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
        .map((item) => renderPluginSlotItem(
              context,
              item,
              onAction: item is Map && item['_pluginId'] is String
                  ? (hook, args) => widget.pluginManager
                      .callPluginHook(item['_pluginId'] as String, hook, args)
                  : null,
            ))
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

/// Renders a single `uiSlot()` payload: a real [Widget] (bundled plugins),
/// a declarative `Map` (`{'type': 'text'|'badge'|'toggle'|'button', 'text':
/// ..., ...}` — the only way a `dart_eval`-sandboxed downloaded plugin can
/// contribute UI), or a bare non-empty [String]. Anything else — `null`,
/// garbage from a misbehaving plugin — renders as nothing rather than
/// crashing the page it's injected into.
///
/// [onAction], when the item is an interactive type (`toggle`/`button`),
/// is called with the item's declared `hook` name and any arguments that
/// interaction implies. `null` for a non-interactive item, a real [Widget]
/// (which wires its own real closures directly, having no need for a
/// hook-name indirection), or a caller that doesn't know which plugin
/// produced this item (e.g. before `_pluginId` stamping existed).
///
/// Shared by [PluginSlotView] (aggregates every enabled plugin at one
/// location) and `PluginSettingsPage` (renders exactly one plugin's
/// `'plugin_settings'` payload, which already knows its own plugin and
/// wires [onAction] directly rather than through `_pluginId`).
Widget? renderPluginSlotItem(
  BuildContext context,
  dynamic item, {
  PluginSlotAction? onAction,
}) {
  if (item is Widget) return item;
  if (item is Map) return _renderDeclarative(context, item, onAction);
  if (item is String && item.trim().isNotEmpty) return Text(item);
  return null;
}

Widget? _renderDeclarative(
  BuildContext context,
  Map item,
  PluginSlotAction? onAction,
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
    default:
      return null;
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
