import 'package:flutter/widgets.dart';

/// A whole top-level tab a bundled plugin contributes to the app's
/// navigation — as opposed to `MusicPlugin.uiSlot`, which injects into
/// a slot that already exists (a badge on Now Playing, an entry in the
/// sidebar). This is the mechanism for "install this plugin and get a
/// brand new tab with its own persistent page," the thing `uiSlot`'s
/// existing `nav_item` payload could only approximate as a pushed
/// route with no state preservation across tab switches.
///
/// Bundled plugins only — a downloadable (sandboxed) plugin has no way
/// to produce a real `WidgetBuilder`, since `dart_eval` never has
/// `package:flutter` available to it. See docs/PLUGIN_GUIDE.md for the
/// full explanation of that boundary.
class PluginDestination {
  /// Stable identifier for this destination — used to keep the
  /// currently-selected tab pointed at the same destination across
  /// rebuilds even as other plugins' destinations are added or removed
  /// around it. Must be unique across every plugin's contributed
  /// destinations; a collision with another plugin's id (or with a
  /// core destination's reserved ids: `library`, `playlist`,
  /// `settings`) is the contributing plugin's bug to avoid, not
  /// something this type validates. (`home` and `moods` were both
  /// reserved core ids before Tier 2 extracted the Home dashboard into
  /// `HomeDashboardPlugin` and the Moods cluster into `MoodsPlugin`, and
  /// `online` was a reserved core id before Tier 2 extracted the Online
  /// tab into `OnlinePlugin` — each keeps using its original string for
  /// its own destination id, but none of the three is a *reserved* id
  /// any plugin must avoid any more, just an ordinary plugin-chosen one.)
  final String id;

  /// The icon shown in the navigation rail/bar for this destination.
  final IconData icon;

  /// The label shown alongside [icon].
  final String label;

  /// Builds the persistent page shown when this destination is
  /// selected. Invoked on every rebuild of the containing
  /// `IndexedStack`, the same as every existing core tab's page widget;
  /// the returned widget's own `State` (if any) is preserved across
  /// those rebuilds via normal Flutter element reuse — not because this
  /// builder is only called once — and so survives tab switches for as
  /// long as the contributing plugin stays enabled.
  final WidgetBuilder pageBuilder;

  /// Relative ordering among plugin-contributed destinations only —
  /// core destinations always render first regardless of this value.
  /// Ties are broken by the contributing plugins' registration order
  /// in `bundled_plugins.dart`. Defaults to `0`, meaning "no particular
  /// preference" — most plugins should leave this alone.
  final int order;

  const PluginDestination({
    required this.id,
    required this.icon,
    required this.label,
    required this.pageBuilder,
    this.order = 0,
  });
}
