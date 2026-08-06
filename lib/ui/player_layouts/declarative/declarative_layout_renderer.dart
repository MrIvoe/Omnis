import 'package:flutter/material.dart';
import 'package:omnis/ui/player_layouts/declarative/layout_manifest.dart';
import 'package:omnis/ui/player_layouts/player_layout.dart';
import 'package:omnis/ui/player_layouts/player_widgets.dart';
import 'package:omnis/ui/plugin_slot_view.dart';

/// Interprets a [LayoutManifest]'s node tree into a real widget tree.
///
/// The node vocabulary is intentionally closed: `_renderNode` dispatches
/// on a fixed `switch` over known `type` strings, and any unrecognised
/// type (or malformed node) degrades to an empty box rather than
/// crashing. A user-authored layout cannot request anything outside this
/// vocabulary — there is no escape hatch to arbitrary widgets, network
/// access, or code execution.
class DeclarativeLayoutRenderer {
  const DeclarativeLayoutRenderer._();

  /// Renders [manifest] as a full-bleed layout, applying its background
  /// and gesture wrapping. Never throws to the caller — a manifest that
  /// fails to render (a bad property value producing a Flutter layout
  /// exception, for instance) shows an in-place error card instead of
  /// taking down Now Playing.
  static Widget renderRoot(
    BuildContext context,
    PlayerLayoutData data,
    LayoutManifest manifest,
  ) {
    Widget content;
    try {
      content = _renderNode(context, data, manifest.root);
    } catch (e) {
      return _errorCard(context, manifest, e);
    }

    final background = manifest.background;
    if (background != null) {
      content = DecoratedBox(
        decoration: _decorationFor(context, background),
        child: content,
      );
    }

    if (manifest.definesOwnGestures) {
      content = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: data.onPlayPause,
        onHorizontalDragEnd: (details) {
          switch (swipeSkipActionFor(details.primaryVelocity)) {
            case SwipeSkipAction.next:
              data.onNext();
            case SwipeSkipAction.previous:
              data.onPrevious();
            case null:
              break;
          }
        },
        child: content,
      );
    }

    return SizedBox.expand(child: content);
  }

  static Widget _errorCard(
    BuildContext context,
    LayoutManifest manifest,
    Object error,
  ) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.broken_image_outlined,
                size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text('"${manifest.name}" failed to render',
                textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('$error',
                textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  static Widget _renderNode(
    BuildContext context,
    PlayerLayoutData data,
    dynamic node,
  ) {
    if (node is! Map) return const SizedBox.shrink();
    switch (node['type']?.toString()) {
      case 'column':
        return Column(
          mainAxisAlignment: _mainAxisAlignment(node['main_axis_alignment']),
          crossAxisAlignment: _crossAxisAlignment(node['cross_axis_alignment']),
          mainAxisSize: _mainAxisSize(node['main_axis_size']),
          children: _children(context, data, node),
        );
      case 'row':
        return Row(
          mainAxisAlignment: _mainAxisAlignment(node['main_axis_alignment']),
          crossAxisAlignment: _crossAxisAlignment(node['cross_axis_alignment']),
          mainAxisSize: _mainAxisSize(node['main_axis_size']),
          children: _children(context, data, node),
        );
      case 'stack':
        return Stack(
          fit: node['fit'] == 'expand' ? StackFit.expand : StackFit.loose,
          children: _children(context, data, node),
        );
      case 'positioned':
        return Positioned(
          top: _num(node['top']),
          left: _num(node['left']),
          right: _num(node['right']),
          bottom: _num(node['bottom']),
          child: _child(context, data, node),
        );
      case 'center':
        return Center(child: _child(context, data, node));
      case 'expanded':
        return Expanded(
          flex: (node['flex'] as num?)?.toInt() ?? 1,
          child: _child(context, data, node),
        );
      case 'padding':
        return Padding(
          padding: _paddingFor(node),
          child: _child(context, data, node),
        );
      case 'sized_box':
        return SizedBox(
          width: _num(node['width']),
          height: _num(node['height']),
          child: node['child'] != null ? _child(context, data, node) : null,
        );
      case 'safe_area':
        return SafeArea(
          top: node['top'] != false,
          bottom: node['bottom'] != false,
          child: _child(context, data, node),
        );
      case 'scroll':
        return SingleChildScrollView(child: _child(context, data, node));
      case 'component':
        return _renderComponent(data, node);
      default:
        return const SizedBox.shrink();
    }
  }

  static List<Widget> _children(
    BuildContext context,
    PlayerLayoutData data,
    Map node,
  ) {
    final raw = node['children'];
    if (raw is! List) return const [];
    return [for (final child in raw) _renderNode(context, data, child)];
  }

  static Widget _child(BuildContext context, PlayerLayoutData data, Map node) {
    final child = node['child'];
    if (child == null) return const SizedBox.shrink();
    return _renderNode(context, data, child);
  }

  static double? _num(dynamic value) => value is num ? value.toDouble() : null;

  static EdgeInsets _paddingFor(Map node) {
    final all = node['all'];
    if (all is num) return EdgeInsets.all(all.toDouble());
    return EdgeInsets.only(
      left: _num(node['left']) ?? _num(node['horizontal']) ?? 0,
      right: _num(node['right']) ?? _num(node['horizontal']) ?? 0,
      top: _num(node['top']) ?? _num(node['vertical']) ?? 0,
      bottom: _num(node['bottom']) ?? _num(node['vertical']) ?? 0,
    );
  }

  static MainAxisAlignment _mainAxisAlignment(dynamic value) {
    switch (value) {
      case 'start':
        return MainAxisAlignment.start;
      case 'end':
        return MainAxisAlignment.end;
      case 'space_between':
        return MainAxisAlignment.spaceBetween;
      case 'space_around':
        return MainAxisAlignment.spaceAround;
      case 'space_evenly':
        return MainAxisAlignment.spaceEvenly;
      default:
        return MainAxisAlignment.center;
    }
  }

  static CrossAxisAlignment _crossAxisAlignment(dynamic value) {
    switch (value) {
      case 'start':
        return CrossAxisAlignment.start;
      case 'end':
        return CrossAxisAlignment.end;
      case 'stretch':
        return CrossAxisAlignment.stretch;
      default:
        return CrossAxisAlignment.center;
    }
  }

  static MainAxisSize _mainAxisSize(dynamic value) =>
      value == 'min' ? MainAxisSize.min : MainAxisSize.max;

  static BoxDecoration _decorationFor(BuildContext context, Map spec) {
    final scheme = Theme.of(context).colorScheme;
    if (spec['type'] == 'gradient') {
      final colors = (spec['colors'] as List? ?? const [])
          .map((c) => _colorFor(scheme, c.toString()))
          .toList();
      if (colors.length < 2) return const BoxDecoration();
      return BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: colors,
        ),
      );
    }
    return BoxDecoration(
      color: _colorFor(scheme, spec['value']?.toString() ?? 'surface'),
    );
  }

  /// Resolves a color role name (a fixed `ColorScheme` allowlist) or a
  /// `#RRGGBB`/`#AARRGGBB` literal. Anything unrecognised falls back to
  /// `surface` rather than throwing.
  static Color _colorFor(ColorScheme scheme, String name) {
    if (name.startsWith('#')) {
      final hex = name.substring(1);
      if (hex.length == 6 || hex.length == 8) {
        final value = int.tryParse(hex.length == 6 ? 'FF$hex' : hex, radix: 16);
        if (value != null) return Color(value);
      }
    }
    switch (name) {
      case 'primary':
        return scheme.primary;
      case 'onPrimary':
        return scheme.onPrimary;
      case 'primaryContainer':
        return scheme.primaryContainer;
      case 'onPrimaryContainer':
        return scheme.onPrimaryContainer;
      case 'secondary':
        return scheme.secondary;
      case 'secondaryContainer':
        return scheme.secondaryContainer;
      case 'surface':
        return scheme.surface;
      case 'onSurface':
        return scheme.onSurface;
      case 'surfaceContainerHighest':
        return scheme.surfaceContainerHighest;
      case 'scrim':
        return scheme.scrim;
      case 'error':
        return scheme.error;
      default:
        return scheme.surface;
    }
  }

  /// The closed set of Now Playing building blocks a layout can place —
  /// exactly the widgets every bundled layout also composes from
  /// (`player_widgets.dart`), plus the two `uiSlot` locations and a
  /// decorative state icon for gesture-only arrangements.
  static Widget _renderComponent(PlayerLayoutData data, Map node) {
    switch (node['component']?.toString()) {
      case 'album_art':
        return PlayerAlbumArt(
          data: data,
          size: _num(node['size']) ?? 220,
          iconSize: _num(node['icon_size']) ?? 96,
        );
      case 'track_info':
        return PlayerTrackInfo(
          data: data,
          align: node['align'] == 'left' ? TextAlign.left : TextAlign.center,
          large: node['large'] != false,
        );
      case 'controls_row':
        return PlayerControlsRow(data: data);
      case 'progress_bar':
        return PlayerProgressBar(
          data: data,
          interactive: node['interactive'] != false,
        );
      case 'lyrics_panel':
        return PlayerLyricsPanel(data: data);
      case 'extras_row':
        return PlayerExtrasRow(data: data);
      case 'sleep_timer_row':
        return PlayerSleepTimerRow(data: data);
      case 'crossfade_status':
        return PlayerCrossfadeStatus(data: data);
      case 'plugin_slot_overlay':
        return PluginSlotView(
          pluginManager: data.pluginManager,
          locationId: 'now_playing_overlay',
        );
      case 'plugin_slot_bottom':
        return PluginSlotView(
          pluginManager: data.pluginManager,
          locationId: 'now_playing_bottom',
          direction: Axis.vertical,
        );
      case 'state_icon':
        return Icon(
          data.buffering
              ? Icons.hourglass_top
              : (data.playing
                  ? Icons.pause_circle_outline
                  : Icons.play_circle_outline),
          size: _num(node['size']) ?? 40,
        );
      case 'spacer':
        return SizedBox(
          width: _num(node['width']),
          height: _num(node['height']) ?? 12,
        );
      default:
        return const SizedBox.shrink();
    }
  }
}
