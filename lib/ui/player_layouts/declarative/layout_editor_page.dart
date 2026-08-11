import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/ui/player_layouts/declarative/layout_installer.dart'
    show LayoutInstallException;
import 'package:omnis/ui/player_layouts/layout_manager.dart';

/// One placeable Now Playing building block, drawn from the same closed
/// vocabulary [DeclarativeLayoutRenderer] already knows how to render
/// (`lib/ui/player_layouts/declarative/declarative_layout_renderer.dart`)
/// — this editor never invents a new component type, it only arranges the
/// existing ones. [footprint] is a fixed placement size, not a resize
/// handle: a first cut of "move things around" rather than "resize things
/// too," which would need its own handle/aspect-ratio-locking UI.
class _ComponentSpec {
  final String id;
  final String label;
  final IconData icon;
  final Size footprint;

  const _ComponentSpec(this.id, this.label, this.icon, this.footprint);
}

const _availableComponents = [
  _ComponentSpec('album_art', 'Album Art', Icons.album, Size(180, 180)),
  _ComponentSpec('track_info', 'Track Info', Icons.text_fields, Size(260, 64)),
  _ComponentSpec(
      'controls_row', 'Controls', Icons.play_circle_outline, Size(280, 64)),
  _ComponentSpec(
      'progress_bar', 'Progress Bar', Icons.linear_scale, Size(280, 40)),
  _ComponentSpec('lyrics_panel', 'Lyrics', Icons.lyrics_outlined, Size(280, 110)),
  _ComponentSpec(
      'extras_row', 'Extras (EQ / Visualizer)', Icons.tune, Size(280, 44)),
  _ComponentSpec(
      'sleep_timer_row', 'Sleep Timer', Icons.bedtime_outlined, Size(56, 44)),
  _ComponentSpec('crossfade_status', 'Crossfade Status', Icons.compare_arrows,
      Size(260, 24)),
  _ComponentSpec(
      'state_icon', 'Play/Pause Icon', Icons.play_circle_fill, Size(44, 44)),
];

class _PlacedComponent {
  final String componentId;
  Offset position;

  _PlacedComponent({required this.componentId, required this.position});
}

/// Lets a user build their own Now Playing arrangement by dragging
/// components onto a canvas, rather than only picking among the bundled
/// layouts or importing someone else's YAML file.
///
/// "Constrained" drag-drop: every placed component's position is clamped
/// to stay fully inside the canvas on every drag update — nothing can be
/// dragged off-screen or left partially hidden behind an edge. It is not
/// constrained against overlapping other components; keeping two things
/// from touching is a real layout-solver problem, and the user can already
/// see and correct an overlap visually while dragging.
///
/// Saving produces a `LayoutManifest`-shaped JSON document — JSON is a
/// valid YAML subset, so it installs through exactly the same
/// [LayoutManager.installFromText] -> [DeclarativeLayoutRenderer] path an
/// imported `.yaml` file does; nothing downstream needs to know this
/// layout was drawn rather than hand-written. Positions are saved in the
/// exact logical pixels this editor measured them at, so the result is
/// guaranteed correct on the device it was designed on — not
/// resolution-independent across wildly different screen sizes, the same
/// practical scope every other "design it on your phone, use it on your
/// phone" personalization feature in this app has.
class LayoutEditorPage extends StatefulWidget {
  final LayoutManager layoutManager;

  const LayoutEditorPage({super.key, required this.layoutManager});

  @override
  State<LayoutEditorPage> createState() => _LayoutEditorPageState();
}

class _LayoutEditorPageState extends State<LayoutEditorPage> {
  final List<_PlacedComponent> _placed = [];
  final TextEditingController _nameController =
      TextEditingController(text: 'My Layout');
  bool _saving = false;

  /// The canvas's measured size as of the last build — read by palette
  /// taps (which happen outside the canvas's own `LayoutBuilder`) to
  /// clamp a newly-added component's default position. A plain field,
  /// not `setState`-driven: it only needs to be current by the time the
  /// next tap reads it, not to trigger a rebuild itself.
  Size? _lastCanvasSize;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  static _ComponentSpec _specFor(String id) =>
      _availableComponents.firstWhere((c) => c.id == id);

  void _addComponent(_ComponentSpec spec, Size canvasSize) {
    final cascade = 16.0 * (_placed.length % 6);
    final maxX = math.max(0.0, canvasSize.width - spec.footprint.width);
    final maxY = math.max(0.0, canvasSize.height - spec.footprint.height);
    setState(() {
      _placed.add(_PlacedComponent(
        componentId: spec.id,
        position: Offset(cascade.clamp(0.0, maxX), cascade.clamp(0.0, maxY)),
      ));
    });
  }

  void _removeAt(int index) => setState(() => _placed.removeAt(index));

  void _dragUpdate(int index, Offset delta, Size canvasSize) {
    final item = _placed[index];
    final spec = _specFor(item.componentId);
    final maxX = math.max(0.0, canvasSize.width - spec.footprint.width);
    final maxY = math.max(0.0, canvasSize.height - spec.footprint.height);
    setState(() {
      item.position = Offset(
        (item.position.dx + delta.dx).clamp(0.0, maxX),
        (item.position.dy + delta.dy).clamp(0.0, maxY),
      );
    });
  }

  Future<void> _save() async {
    if (_placed.isEmpty) {
      _toast('Add at least one component first.');
      return;
    }
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _toast('Give your layout a name.');
      return;
    }

    setState(() => _saving = true);
    final id = 'custom_${DateTime.now().millisecondsSinceEpoch}';
    final manifest = {
      'id': id,
      'name': name,
      'description': 'A custom layout you designed.',
      'author': 'You',
      'version': '1.0.0',
      'defines_own_gestures': false,
      'root': {
        'type': 'stack',
        'children': [
          for (final item in _placed)
            {
              'type': 'positioned',
              'left': item.position.dx,
              'top': item.position.dy,
              'child': {
                'type': 'sized_box',
                'width': _specFor(item.componentId).footprint.width,
                'height': _specFor(item.componentId).footprint.height,
                'child': {
                  'type': 'component',
                  'component': item.componentId,
                },
              },
            },
        ],
      },
    };

    try {
      final layout =
          await widget.layoutManager.installFromText(jsonEncode(manifest));
      AppSettings.instance.playerLayoutId = layout.id;
      if (mounted) Navigator.of(context).pop(true);
    } on LayoutInstallException catch (e) {
      if (mounted) _toast(e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final placedIds = _placed.map((p) => p.componentId).toSet();
    final palette =
        _availableComponents.where((c) => !placedIds.contains(c.id)).toList();

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _nameController,
          decoration: const InputDecoration(
            border: InputBorder.none,
            hintText: 'Layout name',
          ),
          style: theme.textTheme.titleLarge,
        ),
        actions: [
          TextButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check),
            label: const Text('Save'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Drag components to arrange them. Tap a component below to '
              'add it; tap the × to remove one from the canvas.',
              style: theme.textTheme.bodySmall,
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final canvasSize = constraints.biggest;
                  // Plain field write, not setState: this runs during
                  // build, and the value is only read later from a
                  // palette tap's event handler, never used to drive
                  // this build itself.
                  _lastCanvasSize = canvasSize;
                  return Container(
                    key: const ValueKey('layout_editor_canvas'),
                    width: canvasSize.width,
                    height: canvasSize.height,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.3),
                      border: Border.all(color: theme.colorScheme.outline),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Stack(
                      clipBehavior: Clip.hardEdge,
                      children: [
                        for (var i = 0; i < _placed.length; i++)
                          Positioned(
                            key: ValueKey(
                                'placed_canvas_${_placed[i].componentId}'),
                            left: _placed[i].position.dx,
                            top: _placed[i].position.dy,
                            child: GestureDetector(
                              onPanUpdate: (details) =>
                                  _dragUpdate(i, details.delta, canvasSize),
                              child: _PlacedChip(
                                spec: _specFor(_placed[i].componentId),
                                onRemove: () => _removeAt(i),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 96,
            child: palette.isEmpty
                ? Center(
                    child: Text('All components placed.',
                        style: theme.textTheme.bodySmall),
                  )
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: palette.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final spec = palette[index];
                      return ActionChip(
                        avatar: Icon(spec.icon, size: 18),
                        label: Text(spec.label),
                        onPressed: () => _addComponent(
                          spec,
                          _lastCanvasSize ?? const Size(320, 500),
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _PlacedChip extends StatelessWidget {
  final _ComponentSpec spec;
  final VoidCallback onRemove;

  const _PlacedChip({required this.spec, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: spec.footprint.width,
      height: spec.footprint.height,
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.primary, width: 1.5),
      ),
      child: Stack(
        children: [
          Center(
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(spec.icon, color: theme.colorScheme.onPrimaryContainer),
                  Text(
                    spec.label,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.onPrimaryContainer),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: InkWell(
              onTap: onRemove,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.close,
                    size: 14, color: theme.colorScheme.onPrimary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
