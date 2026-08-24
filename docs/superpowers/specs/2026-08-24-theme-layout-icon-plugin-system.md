# Theme/Layout/Icon Plugin System — Design Spec

## Goal

Let a plugin — bundled or downloadable — contribute a complete visual
"skin" (color theme, Now Playing layout, and custom icon artwork)
instead of requiring every visual customization to be hand-built through
the in-app Theme Editor. Omnis's own default look ships in core, requires
no plugin, and stays exactly as good as it is today; skins are strictly
additive.

## Why this is achievable for downloadable plugins too — the key finding

Tier 0's spec drew a hard wall for `PluginDestination` (whole new tabs):
a downloadable, `dart_eval`-sandboxed plugin has no `package:flutter`
access, so it can never construct a real widget tree, full stop. That
wall does **not** apply here, because a theme and a layout are already
pure data in this codebase, not code:

- `ThemeManifest` (`lib/ui/theme/declarative/theme_manifest.dart`) is a
  closed-schema, JSON-parseable description (color roles, font choice,
  corner radius, motion speed, icon style) — already exactly what a
  guest `dart_eval` function can return as a `Map`, the identical shape
  `uiSlot`'s existing declarative UI results already use.
- `LayoutManifest` (`lib/ui/player_layouts/declarative/layout_manifest.dart`)
  is the same kind of closed-schema description for a Now Playing
  arrangement, rendered by `declarative_layout_renderer.dart`'s fixed
  vocabulary of ~15 named sub-components.

Both are already validated, parsed, and rendered by trusted host code
today — the only thing missing is a way for a *plugin* (not just a
human via the Theme Editor) to hand one over.

## Part 1: Theme and layout as a plugin capability

### Design

A new manifest-declared capability, `provides: [theme]` / `provides:
[layout]`, mirroring the existing `provides: [ratings]`/`provides:
[thumbs]` pattern downloadable plugins already use for service
capabilities (`PluginManager._registerProvidedServices`,
`providedCapabilityHooks`).

- A plugin declaring `provides: [theme]` exposes a fixed, reviewed guest
  hook (e.g. `provideTheme()`) returning a `Map` — the exact shape
  `ThemeManifest.parse` already validates. The host calls this hook the
  same way it already calls every other fixed-name guest hook
  (`callHook`), through the same sandbox-wrapped `runSync`/`run` path
  every other capability uses. A malformed or throwing plugin simply
  contributes nothing, exactly like every other capability's existing
  "sandboxed failure degrades to absent" contract.
- A plugin declaring `provides: [layout]` works identically, returning a
  `LayoutManifest`-shaped `Map` via `provideLayout()`.
- A **bundled** plugin implementing the equivalent Dart interfaces
  (`IThemeProvider`/`ILayoutProvider` in `service_interfaces.dart`) can
  do the same thing without the hook indirection, registered through
  `ServiceRegistry` exactly like every other bundled capability.
- Both interfaces support **more than one registered provider**, the
  same `ServiceRegistry.getAll<T>()` shape `IQueueBuilder` already
  establishes — installing three "skin packs" lets a user pick among
  all three in the existing Theme/Layout picker UI, not just the one
  most-recently-enabled plugin.
- **No new validation surface**: a plugin-provided manifest goes through
  the exact same `ThemeManifest.parse`/`LayoutManifest.parse` a
  human-authored one from the Theme Editor already goes through. A
  malicious or malformed plugin manifest fails parsing exactly like a
  malformed hand-edited one does today — this design adds a new
  *source* for a manifest, never a new manifest schema or a new trust
  boundary for schema content.

### What's still out of scope

A downloadable plugin still cannot ship arbitrary custom Flutter code —
a "layout" is still limited to the declarative renderer's closed
vocabulary of named sub-components (art, title, progress bar, button
row, ...), not an arbitrary widget tree. Expanding that vocabulary (more
sub-component types, more layout primitives) is real, separate,
incremental work independent of this spec — this spec is about *who can
supply* a manifest, not about growing what the manifest format can
express.

## Part 2: Icon artwork delivery

### Bundled plugins — no new infrastructure

Flutter packages can already declare their own assets
(`flutter: assets:` in the plugin package's own `pubspec.yaml`),
addressable as `packages/omnis_plugins/<path>` from anywhere in the app
once that package is a dependency — this already works today with zero
changes. What's missing is only a lookup layer: extending
`OmnisIconCatalog` so a bundled skin plugin can register itself as an
icon *source* (via the same `ServiceRegistry` pattern as Part 1), mapping
reserved icon keys to `AssetImage('packages/omnis_plugins/...')`
references instead of a built-in `Icons.xxx` constant.

### Downloadable plugins — file-based delivery, host-loaded

Downloadable plugins already install by downloading a folder to local
app storage (the existing `PluginManager.installFromPath` mechanism —
see how `sample_logger`/`favorites` are installed today). This spec
extends that folder format:

- A plugin's `omnis_plugin.yaml` manifest gains an optional `icons:`
  section: a map from a **closed set of reserved icon keys** (matching
  `OmnisIconCatalog`'s existing vocabulary — `play`, `pause`,
  `skip_next`, `skip_previous`, ...; the reserved key list is fixed and
  reviewed, a plugin cannot invent new keys the app doesn't already
  render somewhere) to a relative file path inside the plugin's own
  installed directory, e.g. `icons: { play: "icons/play.svg" }`.
- **The host loads these files directly — never sandboxed guest code.**
  This is the load-bearing security property: icon files are inert
  data, not executable guest code, so loading them is a plain
  host-side file read, not a sandbox-bridge call. Before loading, the
  host validates, in order:
  1. **Path containment**: the resolved absolute path must be strictly
     inside the plugin's own installed directory (reject any path
     containing `..` or resolving outside it via symlink) — the same
     path-traversal discipline any file-serving code needs.
  2. **Extension allow-list**: `.png`, `.webp`, `.svg` only. No other
     file type is ever loaded as an icon, regardless of what the
     manifest claims.
  3. **Size cap**: a fixed ceiling (e.g. 200KB) per icon file, rejected
     silently (falls back to the built-in glyph) if exceeded — prevents
     a plugin from smuggling in unreasonably large assets under an
     icon's guise.
  4. **SVG rendering**: via `flutter_svg`, a static vector rasterizer
     with no script-execution capability (unlike an embedded browser
     engine) — confirm during implementation that the specific
     `flutter_svg` version pinned does not resolve external XML
     entities (a known SVG/XML attack class unrelated to script
     execution) by checking its parser configuration directly, not by
     assumption. If that can't be confirmed cleanly, restrict the
     downloadable-plugin icon path to raster formats (PNG/WebP) only
     and defer SVG support for downloadable plugins specifically
     (bundled plugins are unaffected either way, since their assets are
     compiled in by the developer, not fetched at runtime).
- **Resolution order**: a plugin-provided icon (from whichever
  icon-providing plugin is enabled) takes precedence over the built-in
  style-switched Material glyph for that key; the built-in glyph is
  always the fallback when no plugin provides that key or the plugin's
  file fails validation — icons never go missing, only ever degrade to
  the existing default.

### What's still out of scope

This spec covers icon *artwork* only (static images swapped in for
specific reserved keys). It does not cover animated icons, a plugin
inventing entirely new icon keys the app has no render site for, or any
other asset type (fonts, sounds) — each of those would need its own,
separately-scoped extension of this same file-based-delivery pattern if
wanted later.

## Self-review

- **Placeholder scan**: no TBD/TODO. The one item explicitly deferred
  during implementation (confirming `flutter_svg`'s XML-entity
  behavior) is deferred with a concrete, actionable fallback (raster-only
  for downloadable plugins) if it can't be confirmed, not an open
  question left hanging.
- **Internal consistency**: Part 1 and Part 2 both reuse existing
  validation/rendering paths rather than inventing new ones — consistent
  with how every other capability in this codebase (ratings, thumbs,
  queue building) was added.
- **Scope check**: explicitly excludes growing the declarative
  layout/theme vocabulary itself, expanding beyond icon artwork to other
  asset types, and any path toward arbitrary custom Flutter code for
  downloadable plugins — all named as separate, future work, not
  silently implied as included.
- **Ambiguity check**: the SVG-safety question is the one place this
  spec doesn't hand the implementer a fully certain answer — it's
  structured as "confirm X directly; if you can't, do Y" rather than an
  assumption either way.
