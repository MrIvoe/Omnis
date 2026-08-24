# Theme/Layout/Icon Plugin System — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a plugin — bundled or downloadable — contribute a theme, a
Now Playing layout, and/or custom icon artwork, using the exact
validation/rendering machinery that already exists for a human-authored
theme/layout via the in-app editor and import flow. Prove the mechanism
end-to-end with one real bundled "skin" plugin, the same way Tier 0
proved `PluginDestination` with a real `RadioPlugin` conversion rather
than shipping an untested abstraction.

**Architecture:** Two new capabilities (`theme`, `layout`) following the
codebase's existing `providedCapabilityHooks`/`ServiceRegistry` pattern
exactly — the same shape `ratings`/`thumbs`/`favorites` already use for
downloadable plugins, and the same `initialize()`/`enable()`/`disable()`/
`dispose()` registration symmetry `RadioPlugin` already establishes for
bundled ones. `ThemeManager`/`LayoutManager` gain one new source
(`ServiceRegistry.getAll<T>()`) alongside their existing installed-file
list — no change to `ThemeManifest.parse`/`LayoutManifest.parse` or the
declarative renderer's vocabulary. Icon delivery is two genuinely
different mechanisms for two genuinely different plugin kinds: bundled
plugins use Flutter's native package-asset system (already works, zero
new infrastructure); downloadable plugins get a new, narrowly-scoped
file-delivery path reusing this codebase's existing zip-slip-guard path
validation idiom, restricted to raster formats for this pass (SVG is
explicitly out of scope — the dependency isn't even present yet).

**Tech Stack:** Flutter/Dart, `dart_eval` sandbox (`PluginRuntime.callHook`),
`ServiceRegistry`, the existing `ThemeManifest`/`LayoutManifest`
declarative formats.

**Spec:** `docs/superpowers/specs/2026-08-24-theme-layout-icon-plugin-system.md`

## Global Constraints

- Every plugin-provided theme/layout goes through the exact same
  `ThemeManifest.parse`/`LayoutManifest.parse` a human-authored one
  already goes through — this plan adds a new *source*, never a new
  schema or a new trust boundary for manifest *content*.
- A downloadable plugin's guest hook (`provideTheme`/`provideLayout`)
  returns a plain `Map` — the sandboxed adapter's job is exactly "call
  the hook, type-check the result, degrade to absent on any mismatch or
  exception," matching every existing `Sandboxed*Provider`'s shape. Never
  add sandbox-specific parsing logic that diverges from `ThemeManifest`/
  `LayoutManifest.parse`'s own rules.
- Icon file loading for downloadable plugins happens only in host code,
  never inside a sandboxed guest call — an icon file is inert data the
  host reads directly, the same trust model as every other file the host
  already reads off a plugin's installed directory (its manifest, its
  entrypoint).
- Reuse this codebase's existing path-validation idiom exactly
  (`p.isAbsolute(rel) || rel.split(RegExp(r'[\\/]')).contains('..')`,
  `p.normalize` never `p.canonicalize` — see `PluginInstaller`'s
  zip-slip guard) rather than inventing a new one.
- SVG icon support is out of scope for this plan — `flutter_svg` is not
  a dependency in either repo today, and vetting it (confirming no
  XML-external-entity resolution) is real, separate work. Downloadable
  plugin icons in this plan are PNG/WebP only. Bundled plugins are
  unaffected by this restriction (their assets are compiled in by a
  developer, not fetched at runtime, so any format Flutter already
  supports works today).
- `play`/`pause` are **not** part of the reserved icon-key set this plan
  covers — they render via `AnimatedIcon`/`AnimatedIcons.play_pause`, a
  glyph-morph primitive with no outlined/rounded/sharp style-switch
  counterpart and no plugin-override path in this plan. The reserved key
  set for this plan is exactly `OmnisIconCatalog`'s existing 22 icons.
- After every task: `flutter analyze` and `flutter test` must both pass
  clean in whichever repo(s) the task touches.
- This plan executes directly on `main` in both repos — no isolated
  worktree, same established consent as every prior plan this session.
  **Push after every commit, not just commit locally** — a prior task in
  a related plan this session left a commit unpushed by accident; every
  dispatch in this plan repeats that instruction explicitly.
- Cross-repo dependency pin bumps are batched into one final task, not
  done per-task — the lesson two prior plans this session already
  learned the hard way.

---

### Task 1: `IThemeProvider`/`ILayoutProvider` capabilities

**Files:**
- Modify: `packages/omnis_plugin_api/lib/service_interfaces.dart` (two
  new interfaces)
- Modify: `lib/core/plugin_sandbox_services.dart` (`providedCapabilityHooks`
  map, two new `Sandboxed*Provider` adapter classes)
- Modify: `lib/core/plugin_manager.dart` (`_registerProvidedServices`'s
  `switch (capability)`, `_capabilityType`'s parallel switch)
- Test: `test/plugin_sandbox_services_test.dart` or wherever existing
  `Sandboxed*Provider` adapters are tested — grep for
  `SandboxedRatingsProvider`/`SandboxedFavoritesProvider` first
- Test: `test/plugin_system_test.dart` (registration lifecycle, if this
  is where `providedCapabilityHooks`/`_registerProvidedServices` are
  already covered — grep first)

**Interfaces:**
- Produces: `IThemeProvider { Map<String, dynamic>? provideTheme(); }`,
  `ILayoutProvider { Map<String, dynamic>? provideLayout(); }` — a bundled
  plugin implements these directly; a downloadable plugin's sandboxed
  adapter calls the equivalent guest hook. Both return the raw manifest
  shape `ThemeManifest.parse`/`LayoutManifest.parse` already accept
  (a `Map`), not a parsed `ThemeManifest`/`LayoutManifest` object itself —
  parsing happens once, in Task 2, at the point the manifest is consumed,
  not here.

- [ ] **Step 1: Add the two interfaces**

Read the existing `service_interfaces.dart` file's tone/doc-comment style
(any recent addition, e.g. `IRingtoneProvider`, works as a model) before
writing these:

```dart
/// Contributes a theme, as the same `Map` shape `ThemeManifest.parse`
/// already accepts from a human-authored theme file — this interface
/// exists so a *plugin* can be that source too, not just the in-app
/// Theme Editor / an imported URL. Returns `null` for "nothing to
/// contribute right now" (never throws); the caller treats a `null` or
/// a `Map` that fails `ThemeManifest.parse` identically — both mean
/// this provider currently has nothing usable.
abstract class IThemeProvider {
  Map<String, dynamic>? provideTheme();
}

/// The layout twin of [IThemeProvider] — contributes a Now Playing
/// layout as the same `Map` shape `LayoutManifest.parse` already
/// accepts. Same `null`-means-nothing, never-throws contract.
abstract class ILayoutProvider {
  Map<String, dynamic>? provideLayout();
}
```

- [ ] **Step 2: Add the downloadable-plugin capability wiring**

Read `lib/core/plugin_sandbox_services.dart`'s `providedCapabilityHooks`
map and one existing adapter (`SandboxedRatingsProvider`, per planning
research at lines 314-349) in full before writing these, to match the
exact try/callHook/type-check/fallback shape:

```dart
  'theme': ['provideTheme'],
  'layout': ['provideLayout'],
```

added to `providedCapabilityHooks` alongside the existing entries. Then:

```dart
class SandboxedThemeProvider implements IThemeProvider {
  final PluginRuntime runtime;
  const SandboxedThemeProvider(this.runtime);

  @override
  Map<String, dynamic>? provideTheme() {
    try {
      final result = runtime.callHook('provideTheme', []);
      if (result is Map) return Map<String, dynamic>.from(result);
    } catch (_) {
      // Falls through to null below — matches every other adapter's
      // "malformed or throwing guest hook contributes nothing" contract.
    }
    return null;
  }
}

class SandboxedLayoutProvider implements ILayoutProvider {
  final PluginRuntime runtime;
  const SandboxedLayoutProvider(this.runtime);

  @override
  Map<String, dynamic>? provideLayout() {
    try {
      final result = runtime.callHook('provideLayout', []);
      if (result is Map) return Map<String, dynamic>.from(result);
    } catch (_) {
      // Same fallback reasoning as SandboxedThemeProvider.
    }
    return null;
  }
}
```

Confirm `runtime.callHook`'s real signature (positional args list shape)
against another existing adapter before finalizing — the sketch above
assumes a zero-argument hook call, matching `provideLyrics`'s neighbor
hooks that take arguments only when the capability genuinely needs
per-call context; a theme/layout provider needs none.

- [ ] **Step 3: Wire the two new capabilities into `plugin_manager.dart`**

Read `_registerProvidedServices`'s `switch (capability)` and
`_capabilityType`'s parallel switch (planning research: lines 436-482,
499-509) in full first. Add matching cases for `'theme'` →
`SandboxedThemeProvider`/`IThemeProvider` and `'layout'` →
`SandboxedLayoutProvider`/`ILayoutProvider`, following the exact
structure every existing capability case already uses (construct the
adapter, `services.register(InterfaceType, adapter)`, store in
`plugin.providedServices[InterfaceType]`).

- [ ] **Step 4: Tests**

Add a test manifest+guest-hook fixture (matching `Omnis-Plugins/favorites/`'s
existing `omnis_plugin.yaml`+`plugin.dart` fixture pattern, or an inline
sandboxed-runtime test fixture if that's how existing capability tests in
this repo are structured — check both patterns before choosing) proving:
a plugin declaring `provides: [theme]` with a working `provideTheme()`
guest function gets registered as `IThemeProvider` on `enable`/`initialize`
and unregistered on `disable`/`dispose`; a plugin declaring the capability
without actually implementing the hook is silently skipped (never
registered), matching the existing `requiredHooks.every(runtime.hasHook)`
guard's behavior for every other capability. Mirror this for `layout`.

- [ ] **Step 5: Verify and commit**

Run `flutter analyze` and `flutter test`. Commit, then push.

---

### Task 2: Wire `ThemeManager`/`LayoutManager` to consult registered providers

**Files:**
- Modify: `lib/ui/theme/declarative/theme_manager.dart`
- Modify: `lib/ui/player_layouts/layout_manager.dart`
- Test: extend existing test files for both managers

**Interfaces:**
- Consumes: `IThemeProvider`/`ILayoutProvider` via
  `PluginManager.services.getAll<T>()` (the same
  `ServiceRegistry.getAll<T>()` multi-registration shape `IQueueBuilder`
  already establishes — more than one skin plugin can be installed at
  once, and the user picks among all of them in the existing picker UI,
  not just whichever registered most recently).

- [ ] **Step 1: Read both managers' current "list everything available" logic in full**

`ThemeManager` (planning research: owns `List<ThemeManifest> _installed`,
a `changes` broadcast stream, `resolve(id)` returning `null` on miss) and
`LayoutManager` (`allLayouts` = bundled + `_installed`, `resolve(id)`
falling back to `allLayouts.first`). Read both completely, including
whatever the Theme Editor / Layout picker UI actually calls to enumerate
choices (`ThemeManager.installed`/equivalent getter, `LayoutManager.allLayouts`)
so this task's addition slots into the real enumeration path, not a
parallel one the UI doesn't consult.

- [ ] **Step 2: Add a plugin-sourced theme list to `ThemeManager`**

Add a method/getter that calls
`pluginManager.services.getAll<IThemeProvider>()`, calls `provideTheme()`
on each, and for every non-null `Map` result calls
`ThemeManifest.parse(jsonEncode(map), sourceUrl: 'plugin:<pluginId>')`
(or whatever exact re-serialization `ThemeManifest.parse`'s real
signature needs — it's documented as taking `String text`, so a `Map`
needs encoding to YAML/JSON text first; confirm `parse`'s exact
expectations by reading it again rather than assuming `jsonEncode` round-trips
cleanly through `loadYaml` — YAML and JSON are usually
interchangeable for this kind of plain-map content, but verify). Skip
(don't add to the list) any provider whose manifest fails to parse — the
existing "malformed source contributes nothing" contract, one level up.
Merge this list with the existing `_installed` list wherever the UI
enumerates choices, keyed by `id` so a plugin-provided theme with the
same `id` as an already-installed manual one is handled sensibly (prefer
one source consistently — document whichever you choose and why, e.g.
"installed/manual wins over plugin-provided on an id collision, since a
user's own explicit install action is a stronger signal of intent than a
plugin's default").

`ThemeManager.changes` should also fire when `PluginManager.changes` fires
(a plugin enabled/disabled might add/remove a theme choice) — subscribe
to `pluginManager.changes` in whatever `ThemeManager`'s own
initialization/bootstrap does, forwarding to its own `changes` stream so
the Theme Editor's picker UI updates live, the same "subscribe, don't
poll" pattern this session's other plans already established for
`PluginManager.changes` consumers.

- [ ] **Step 3: Add the equivalent plugin-sourced layout list to `LayoutManager`**

Same shape: `pluginManager.services.getAll<ILayoutProvider>()`,
`provideLayout()` per provider, `LayoutManifest.parse` each non-null
result, merge into `allLayouts` alongside bundled + `_installed`. Apply
`LayoutManager`'s own existing reserved-id rejection (the stronger
contract planning research found layouts already have, that themes
don't) to plugin-provided layouts too — a plugin-provided layout whose id
collides with a bundled `createPlayerLayouts()` id should be rejected the
same way a manually-installed one already is.

- [ ] **Step 4: Tests**

For both managers: register a fake `IThemeProvider`/`ILayoutProvider`
(a plain test-only implementation, not a real sandboxed plugin) returning
a valid manifest map, confirm it appears in the enumerated list; confirm
one returning `null` is silently excluded; confirm one returning a
malformed map (missing required fields) is silently excluded; confirm
disabling the providing plugin (or unregistering the service directly in
the test) removes it from the live list via the `changes` stream.

- [ ] **Step 5: Verify and commit**

Run `flutter analyze` and `flutter test`. Commit, then push.

---

### Task 3: Icon manifest schema + downloadable-plugin icon delivery

**Files:**
- Modify: `lib/core/plugin_manifest.dart` (`icons:` field)
- Modify: `lib/ui/theme/omnis_icon_catalog.dart` or a new sibling file
  (host-side icon-file loading + resolution-order wiring)
- Test: `test/plugin_manifest_test.dart` (extend — check it exists)
- Test: new test file for the icon-loading/validation logic

**Interfaces:**
- Produces: a resolution function, e.g.
  `IconProvider? pluginIconFor(String key)` or an extension of
  `ThemedIcon.resolve()`'s existing call sites — the exact integration
  point is this task's own design decision (see Step 4), but the
  contract is: given a reserved icon key (one of `OmnisIconCatalog`'s
  existing 22), return a plugin-provided image if one is installed,
  enabled, and passes validation; otherwise `null`, meaning "use the
  built-in glyph," never a thrown error.

- [ ] **Step 1: Add the `icons:` manifest field**

Read `lib/core/plugin_manifest.dart`'s `PluginManifest.parse` (planning
research: lines 81-105) in full first, matching its exact
never-throw/defensive-default style for every existing field. Add:

```dart
  /// Reserved-icon-key → relative-file-path overrides this plugin
  /// provides, e.g. `{'home': 'icons/home.png'}`. Keys not in
  /// `OmnisIconCatalog`'s fixed vocabulary are silently ignored — a
  /// plugin cannot invent a new icon slot the app has no render site
  /// for. Values are resolved relative to this plugin's own installed
  /// directory and validated (path containment, extension allow-list,
  /// size cap) at load time, never at parse time — parsing only reads
  /// the declared mapping; Step 3 below does the actual file
  /// validation/loading.
  final Map<String, String> icons;
```

Parse it defensively: only accept a `YamlMap`/`Map` value, coerce every
key/value pair to `String`, default to `{}` on any type mismatch — the
same "malformed field degrades to empty/default, never fails the whole
manifest parse" contract every other field in this file already follows.

- [ ] **Step 2: Confirm the reserved icon-key set at implementation time**

Read `lib/ui/theme/omnis_icon_catalog.dart`'s current full icon list (22
per planning research — `home, libraryMusic, playlistPlay, mood,
cloudQueue, settings, skipPrevious, skipNext, shuffle, repeat, repeatOne,
replay10, forward10, replay30, forward30, musicNote, album, person, tag,
folder, gridView, viewList`) and use it as the literal reserved-key
allow-list for `icons:` map validation — a manifest entry for a key not
in this exact list is silently dropped (not an error), matching the
field's own doc comment above. `play`/`pause` are explicitly excluded per
this plan's Global Constraints.

- [ ] **Step 3: Implement host-side icon-file loading with validation**

Read `PluginInstaller`'s zip-slip guard (planning research: the
`p.isAbsolute`/`..`-segment/`p.normalize`-prefix-check idiom) and its
simpler entrypoint-validation sibling in full before writing this — reuse
the exact idiom, don't invent a new one. For each `icons:` entry that
survives Step 2's key-allow-list filter:

```dart
  1. Reject if the relative path is absolute or contains a `..` segment
     (the same check `plugin_installer.dart`'s entrypoint validation
     already does — copy its exact regex/logic).
  2. Resolve against the plugin's own installed directory
     (`ManagedPlugin.directory`, already available per plugin — planning
     research confirmed this field exists today) and confirm the
     resolved, normalized path's directory is the plugin's own directory
     or a subdirectory of it (matching the zip-slip guard's
     `candidateDir == targetRoot || candidateDir.startsWith(...)` check).
  3. Reject if the file extension (case-insensitive) is not `.png` or
     `.webp` — no SVG in this plan, per Global Constraints.
  4. Reject if the file's size exceeds a fixed cap (200KB, matching the
     design spec) — check via `File.lengthSync()` before ever decoding
     the image, not after.
  5. Only if all four checks pass, return an `Image.file(File(resolvedPath))`
     (or the raw resolved path, if the actual integration point from
     Step 4 needs a path rather than a constructed widget — decide based
     on what `ThemedIcon`/its call sites actually need).
```

Any rejection at any step falls back to `null` (meaning "use the built-in
glyph") — never throws, matching this whole plan's "malformed plugin
content degrades silently" theme.

- [ ] **Step 4: Wire icon resolution into the actual render path**

Read every real call site of `OmnisIconCatalog.xxx.resolve()` (planning
research: `home_page.dart:411-416`, `library_page.dart:2549-2564`) to
decide the least invasive integration point. `ThemedIcon.resolve()`
currently returns an `IconData` (a `Icons.xxx`-style glyph reference,
usable directly by an `Icon(...)` widget) — a plugin-provided *image*
file cannot be represented as `IconData` (that type is specifically a
font-glyph reference, not an arbitrary image). This means call sites
using `Icon(OmnisIconCatalog.x.resolve())` need to become something that
can render either a glyph *or* an image depending on whether a plugin
override exists — e.g. a new small widget,
`OmnisIcon(OmnisIconCatalog.x, size: ...)`, that internally checks for a
plugin override first (via whatever resolution function Step 3 produced)
and falls back to `Icon(catalogEntry.resolve())` if none exists. This is
a real, if mechanical, refactor of every existing `Icon(OmnisIconCatalog...)`
call site (grep for the exact count before starting) — do this
conversion as part of this task rather than leaving old and new
resolution paths inconsistent across the app.

- [ ] **Step 5: Tests**

Test the validation logic directly and exhaustively (all four rejection
reasons independently triggered: absolute path, `..` traversal, wrong
extension, oversized file) using a temp directory fixture, confirming
each rejects to `null` rather than throwing. Test the reserved-key
allow-list filter (an `icons:` entry for an unrecognized key is dropped).
Test the new `OmnisIcon` widget (or whichever integration point Step 4
produced) renders the plugin-provided image when a valid override exists
and the built-in glyph when it doesn't.

- [ ] **Step 6: Verify and commit**

Run `flutter analyze` and `flutter test`. Commit, then push.

---

### Task 4: Bundled-plugin icon delivery

**Files:**
- Modify: `Omnis-Plugins/pubspec.yaml` (add `flutter: assets:` section,
  only if Task 5's proof-of-concept plugin needs a real asset file to
  ship — otherwise this task may have nothing to add here beyond the
  lookup-layer code, since package assets require no pubspec change
  until a real asset file exists)
- Modify: whichever file Task 3 Step 4 created for icon resolution (add
  a bundled-plugin lookup path alongside the downloadable-plugin one)

**Interfaces:**
- Produces: the bundled-plugin half of the same resolution contract Task
  3 built for downloadable plugins — a bundled plugin registers itself as
  an icon source (via `ServiceRegistry`, matching every other
  bundled-capability registration pattern in this codebase) providing
  `AssetImage('packages/omnis_plugins/<path>')` references for whichever
  reserved keys it overrides.

- [ ] **Step 1: Design the bundled-plugin icon-provider interface**

A bundled plugin needs a way to say "I provide these icon overrides" —
the simplest shape consistent with `IThemeProvider`/`ILayoutProvider`'s
pattern: add `Map<String, AssetImage> provideIcons()` to a new
`IIconProvider` interface in `service_interfaces.dart`, registered via
the standard `ServiceRegistry` lifecycle. Confirm `AssetImage` is a
reasonable return type here (it's a `Flutter` `ImageProvider`, directly
usable by whatever rendering `Image` widget Task 3's `OmnisIcon` ends up
using) rather than a raw path string, since a bundled plugin's asset
resolution (`packages/omnis_plugins/...`) is a Flutter-native concept a
downloadable plugin's file-path resolution isn't.

- [ ] **Step 2: Wire it into the resolution path from Task 3**

Extend whichever function/widget Task 3 Step 4 built to check
`pluginManager.services.getAll<IIconProvider>()` (bundled icon sources)
*and* the downloadable-plugin file-based path, in a defined order (a
reasonable default: check bundled providers first since they're
lower-risk/no-file-IO, then downloadable — document whichever order you
choose and why) before falling back to the built-in glyph.

- [ ] **Step 3: Tests**

A fake `IIconProvider` test double confirming registration → resolution
→ unregistration-on-disable, mirroring the pattern established for every
other `ServiceRegistry` capability test in this plan and prior ones.

- [ ] **Step 4: Verify and commit**

Run `flutter analyze` and `flutter test`. Commit, then push.

---

### Task 5: Proof-of-concept bundled skin plugin

**Files:**
- Create (Omnis-Plugins repo): a new small bundled plugin, e.g.
  `lib/example_skin_plugin.dart`, exercising `IThemeProvider`,
  `ILayoutProvider`, and `IIconProvider` together
- Modify: `Omnis-Plugins/lib/bundled_plugins.dart` (register it)
- Modify: `Omnis-Plugins/pubspec.yaml` (add the real asset file(s) this
  plugin ships, if Task 4 didn't already need to)
- Test: a plugin-lifecycle test for this new plugin

**Interfaces:** None new — this task is pure proof-of-concept, exercising
every interface Tasks 1-4 built.

This task exists for the same reason Tier 0 didn't ship
`PluginDestination` without converting a real plugin (`RadioPlugin`) to
prove it end-to-end — an abstraction with zero real consumers is
unverified by construction, regardless of how thorough its unit tests
are.

- [ ] **Step 1: Design one small, genuinely different theme + layout + icon**

Not a copy of an existing built-in preset — something visually distinct
enough that a manual smoke-test (running the app, enabling this plugin,
confirming the theme/layout/icon actually change) is a meaningful check,
not a no-op. Keep it simple: a distinct accent color + one different
Now Playing layout arrangement (reuse the declarative renderer's existing
component vocabulary — no new layout primitives) + one overridden icon
(e.g. `home`) with a real, simple raster asset checked into the plugin
package.

- [ ] **Step 2: Implement the plugin**

`ExampleSkinPlugin extends MusicPlugin implements IThemeProvider,
ILayoutProvider, IIconProvider`, following `RadioPlugin`'s exact
`initialize()`/`enable()`/`disable()`/`dispose()` registration symmetry
for all three interfaces at once (register/unregister all three together
in each lifecycle method, matching how a multi-interface plugin like
`RatingsPlugin` already registers `IRatingsProvider`+`IThumbsProvider`
together).

- [ ] **Step 3: Register it**

Add to `bundled_plugins.dart`'s factory list.

- [ ] **Step 4: Manual verification**

Run the app (Windows, this session's actual build target), enable this
plugin via the Plugins page, confirm: the theme picker now offers this
plugin's theme and selecting it visibly changes the app's colors; the
layout picker now offers this plugin's layout and selecting it visibly
changes the Now Playing screen; the overridden icon renders as the
plugin's custom image wherever that reserved key is used in the app.
Disable the plugin, confirm all three revert cleanly to built-in
defaults with no crash. Record this manual verification's outcome in
your report — this is the one step in this whole plan that isn't
satisfied by an automated test, and skipping it would leave the entire
plan's actual real-world behavior unverified.

- [ ] **Step 5: Automated tests**

A plugin-lifecycle test confirming all three interfaces register/
unregister correctly together, matching this plan's established pattern.

- [ ] **Step 6: Verify and commit**

Run `flutter analyze` and `flutter test` in both repos (this task touches
both — Omnis for anything Step 4's manual check surfaces as a bug in
Tasks 1-4's mechanism, Omnis-Plugins for the plugin itself). Commit each
repo's changes separately, then push both.

---

### Task 6: Cross-repo dependency pin bump

**Files:**
- Modify: `Omnis/pubspec.yaml` (both the `omnis_plugins:` ref and the
  separate self-referential `omnis_plugin_api:` ref)
- Modify: `Omnis-Plugins/pubspec.yaml` (`omnis_plugin_api:` ref)

**Interfaces:** None — version pins only.

- [ ] **Step 1: Bump Omnis-Plugins' own `omnis_plugin_api` pin first**

Cut a new `plugin-api-vX.Y.Z` tag on Omnis at its current HEAD (after
Tasks 1-5 have landed there). Bump `Omnis-Plugins/pubspec.yaml`'s
`omnis_plugin_api:` ref to it, commit, push.

- [ ] **Step 2: Cut Omnis-Plugins' own release tag**

At that pin-bump commit (not before it), cut a new `vA.B.C` tag, push.

- [ ] **Step 3: Bump Omnis's own pins**

Bump both `Omnis/pubspec.yaml` refs (`omnis_plugins:` to the Step 2 tag,
the self-referential `omnis_plugin_api:` to the Step 1 tag) together,
commit, push.

- [ ] **Step 4: Verify with overrides removed**

In both repos, temporarily rename `pubspec_overrides.yaml` aside, run a
fresh `flutter pub get`/`analyze`/`test`, confirm clean against the real
published tags, restore the override files, do one final normal-mode
pass, also clean.

---

## After This Plan

A plugin can now contribute a full visual skin — theme, layout, and icon
artwork — through either distribution channel. The declarative
theme/layout vocabularies themselves are unchanged (still the same
closed sets of color roles, sub-components, and background styles);
growing those vocabularies is separate, future work. SVG icon support
for downloadable plugins remains explicitly deferred until `flutter_svg`
(or an equivalent) is added and its XML-parsing safety is confirmed
directly, not assumed. `IIconProvider`'s bundled-only-for-now scope could
be extended to cover more than the current 22 reserved keys (the design
spec's audit-driven observation that the app's icon restyling today only
reaches a curated subset, not the whole app) as its own later pass.
