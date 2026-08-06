import 'package:flutter/material.dart';
import 'package:omnis/ui/player_layouts/declarative/declarative_layout_renderer.dart';
import 'package:omnis/ui/player_layouts/declarative/layout_manifest.dart';
import 'package:omnis/ui/player_layouts/player_layout.dart';

/// Adapts a user-imported [LayoutManifest] into a [PlayerLayout] so
/// `NowPlayingPage` and the layout picker treat imported layouts exactly
/// like the six bundled ones — same interface, same `bundled<T>()`-style
/// resolution, no special-casing anywhere else in the app.
class DeclarativeLayout extends PlayerLayout {
  final LayoutManifest manifest;

  DeclarativeLayout(this.manifest);

  @override
  String get id => manifest.id;

  @override
  String get name => manifest.name;

  @override
  String get description => manifest.description;

  @override
  IconData get icon => Icons.extension_outlined;

  @override
  bool get definesOwnGestures => manifest.definesOwnGestures;

  @override
  Widget build(BuildContext context, PlayerLayoutData data) {
    return DeclarativeLayoutRenderer.renderRoot(context, data, manifest);
  }
}
