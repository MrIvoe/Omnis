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
///  - A declarative `Map` describing a tiny widget (`{'type': 'text', ...}`
///    or `{'type': 'badge', 'text': ..., 'icon': ...}`) — the only way a
///    *downloaded* plugin can contribute UI, since dart_eval plugins are
///    sandboxed away from `dart:ui` and cannot construct real widgets.
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
        .map((item) => renderPluginSlotItem(context, item))
        .whereType<Widget>()
        .toList();
    if (rendered.isEmpty) return const SizedBox.shrink();
    return widget.direction == Axis.vertical
        ? Column(mainAxisSize: MainAxisSize.min, children: rendered)
        : Wrap(spacing: 8, runSpacing: 8, children: rendered);
  }
}

/// Renders a single `uiSlot()` payload: a real [Widget] (bundled plugins),
/// a declarative `Map` (`{'type': 'text'|'badge', 'text': ..., 'icon': ...}`,
/// the only way a `dart_eval`-sandboxed downloaded plugin can contribute
/// UI), or a bare non-empty [String]. Anything else — `null`, garbage from
/// a misbehaving plugin — renders as nothing rather than crashing the page
/// it's injected into.
///
/// Shared by [PluginSlotView] (aggregates every enabled plugin at one
/// location) and `PluginSettingsPage` (renders exactly one plugin's
/// `'plugin_settings'` payload).
Widget? renderPluginSlotItem(BuildContext context, dynamic item) {
  if (item is Widget) return item;
  if (item is Map) return _renderDeclarative(context, item);
  if (item is String && item.trim().isNotEmpty) return Text(item);
  return null;
}

Widget? _renderDeclarative(BuildContext context, Map item) {
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
