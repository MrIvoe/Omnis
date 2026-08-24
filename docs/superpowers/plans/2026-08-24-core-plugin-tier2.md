# Core/Plugin Re-architecture — Tier 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract three currently-core UI subsystems — Home dashboard,
Moods, and Radio+Online — into bundled plugins that contribute their tab
via `PluginDestination` (built in Tier 0) instead of being hardcoded
`home_page.dart` destinations. A plugin-less install ends up with three
core tabs (Library, Playlist, Settings); each extracted feature's tab
appears only when its plugin is installed and enabled — "hide tabs with
no plugin for them" falls out of the existing mechanism for free, no new
infrastructure needed for that part.

**Architecture:** No changes to the `PluginDestination`/`homeDestinations`
mechanism itself — Tier 0's "core first, plugins appended after, id-keyed
selection with fallback to the first destination" design is kept exactly
as built. What Tier 0 didn't anticipate, resolved here as its own
foundational task before any extraction: since the app's very first
launch screen was hardcoded to `home_page.dart`'s literal first core id,
removing that id from the core list would silently move the default
launch experience to whatever's now first (`library`) with no way for a
user to pick something else. This plan adds a **default launch tab**
setting instead — defaults to Library, user-changeable to any currently
available destination (core or plugin-contributed), falling back
gracefully if the chosen tab's plugin is later disabled — using the exact
same id-lookup-with-fallback pattern `home_page.dart`'s tab-selection
logic already established in Tier 0.

**Tech Stack:** Flutter/Dart, the existing `ServiceRegistry`/
`PluginManager`/`PluginDestination` mechanism, `AppSettings`
(`SharedPreferences`-backed).

**Spec:** `docs/superpowers/specs/2026-08-22-core-plugin-rearchitecture-plan.md`
(Part 3's Tier 2 section, T2.1-T2.3 — T2.4, Settings sub-page migration,
is explicitly deferred past this plan; see "After This Plan").

## Global Constraints

- Every extracted plugin follows `Omnis-Plugins/lib/radio_plugin.dart`'s
  exact `ServiceRegistry` registration lifecycle: register whatever
  capability interface it provides in both `initialize()` and `enable()`,
  unregister in both `disable()` and `dispose()`. Verify this file's
  current content directly before each task that needs to match it — do
  not work from a paraphrase.
- A capability interface a UI call site needs from an extracted plugin
  (e.g. "play this named mood," "open the home customize sheet") is added
  to `packages/omnis_plugin_api/lib/service_interfaces.dart` and looked
  up via `pluginManager.services.get<T>()` — never a `GlobalKey` reach
  into a plugin-owned widget's `State`, since `home_page.dart` no longer
  constructs that widget once it's plugin-owned (it only holds a
  `WidgetBuilder` via `PluginDestination.pageBuilder`).
- `packages/omnis_plugin_api/lib/plugin_destination.dart`'s reserved-id
  list (`home`, `library`, `playlist`, `moods`, `online`, `settings`)
  must be updated as each id stops being core-owned — read this file's
  current doc comment before editing it, in each task that retires an id.
- This plan executes directly on `main` in both repos — no isolated
  worktree, no new ruling needed (same established consent as every prior
  plan this session).
- After every task: `flutter analyze` and `flutter test` must both pass
  clean in whichever repo(s) the task touches.
- Tasks 3-5 (the three extractions) each move real, substantial UI code
  from the Omnis repo into the Omnis-Plugins repo. Read the moved file's
  *current* full content before moving it — this plan cites line numbers
  and dependencies gathered during planning, but prior tasks in this same
  plan (and the extraction tasks' own earlier steps) will shift them.
- Cross-repo dependency pin bumps (a new `omnis_plugin_api` interface
  needs a new tag before `Omnis-Plugins` can depend on it) are batched
  into one final task at the end of this plan, not done per-task — the
  same lesson this session's two prior plans both had to learn the hard
  way (a tag cut before its own dependent commit lands is invisible
  locally under `pubspec_overrides.yaml` but breaks a clean checkout).

---

### Task 1: Default launch tab setting

**Files:**
- Modify: `lib/core/app_settings.dart` (new `defaultLaunchTabId` getter/setter)
- Modify: `lib/ui/home_page.dart:78` (initial `_selectedDestinationId`)
- Modify: a settings page — read `lib/ui/settings/appearance_settings_page.dart`,
  `lib/ui/settings/controls_settings_page.dart`, and `lib/ui/settings_page.dart`
  first to decide which already-existing category this belongs in (a
  general app-behavior preference, not strictly visual/appearance — verify
  which category's existing content this reads most naturally alongside
  before picking one; do not create a new top-level Settings category for
  one setting)
- Test: `test/app_settings_test.dart` (extend — check it exists first)
- Test: `test/home_page_plugin_destinations_test.dart` (extend)

**Interfaces:**
- Produces: `AppSettings.defaultLaunchTabId` (`String`, persisted,
  default `'library'`) — consumed by Task 1's own `home_page.dart` change
  and by nothing else in this plan, but this is the field Tasks 3-5's
  extractions rely on existing so removing `'home'`/`'moods'`/`'online'`
  from `_coreDestinationIds` doesn't silently break the launch default.

- [ ] **Step 1: Add the setting to `AppSettings`**

Read `lib/core/app_settings.dart` around its existing `playerLayoutId`
getter/setter (currently lines 76, 369-374) as the pattern to match
exactly — same `static const _xKey` + nullable-`SharedPreferences`-backed
getter-with-default + setter shape. Add:

```dart
  static const _defaultLaunchTabIdKey = 'app_default_launch_tab_id';
```

alongside the other `static const _xKey` declarations, and:

```dart
  /// Which destination id `HomePage` opens to on cold start. Defaults to
  /// `'library'` — the one destination guaranteed to exist regardless of
  /// which plugins are installed, unlike `'home'` before Tier 2, which
  /// assumed a Home-dashboard tab always existed. Resolved against
  /// whatever destinations actually exist at launch time with the same
  /// "fall back to the first one if this id no longer exists" logic
  /// `HomePage`'s own tab-selection already uses — a user who picked a
  /// plugin-contributed tab as their launch default and later disabled
  /// that plugin doesn't see a crash, just a fallback.
  String get defaultLaunchTabId =>
      _prefs?.getString(_defaultLaunchTabIdKey) ?? 'library';

  set defaultLaunchTabId(String value) {
    if (_prefs == null) return;
    _prefs!.setString(_defaultLaunchTabIdKey, value);
  }
```

Match whichever exact null-check/assignment idiom `playerLayoutId`'s
setter actually uses if it differs from the sketch above (re-read it,
don't assume) — some setters in this file call `notifyListeners()`
directly, others rely on a wrapping mechanism; use whichever this file's
existing string-setting setters actually do.

- [ ] **Step 2: Wire it into `HomePage`'s initial selection**

Change `home_page.dart:78` from:

```dart
  String _selectedDestinationId = _coreDestinationIds.first;
```

to:

```dart
  String _selectedDestinationId = AppSettings.instance.defaultLaunchTabId;
```

`AppSettings.instance` is already fully initialized before `HomePage` is
ever constructed (per `main.dart`'s `await AppSettings.instance.initialize()`
ahead of `runApp`), so this field initializer is safe — but confirm this
by reading `main.dart`'s current startup sequence yourself before relying
on it, matching this plan's discipline of verifying rather than assuming.

The existing fallback logic in `build()` (currently around lines 437-441:
`selectedIndex = destinationIds.indexOf(_selectedDestinationId)`, falling
back to `destinationIds[0]` if `-1`) already handles "the persisted
default no longer exists" — no change needed there; it was built in Tier
0 for exactly this class of problem (a vanished destination), and this
task's launch-time value is just one more source of a `_selectedDestinationId`
that might not currently exist.

- [ ] **Step 3: Add the Settings UI**

In whichever settings page you determined in the Files list fits best,
add a picker (a `DropdownButton`/`ListTile`-with-picker-dialog, matching
whatever pattern that page's other similar settings already use — e.g.
`playerLayoutId`'s own picker UI if it lives in the same page) listing
every *currently available* destination id and label. Read
`home_page.dart`'s `build()` method for how it currently builds its own
`destinationIds`/labels list (core ids + `pluginDestinations`) and reuse
that exact same logic/data source — this picker's options must reflect
live plugin state (a disabled plugin's tab should not appear as a
choosable launch default), not a hardcoded list. Reading
`AppSettings.instance.defaultLaunchTabId` for the current value and
writing back via the setter on selection.

- [ ] **Step 4: Tests**

`app_settings_test.dart`: a round-trip test for `defaultLaunchTabId`
(default value, set-then-get) matching this file's existing per-setting
test pattern. `home_page_plugin_destinations_test.dart`: a test setting
`AppSettings.instance.defaultLaunchTabId` to a non-default value before
constructing `HomePage`, confirming the app opens to that tab — and a
second test confirming that if the persisted value names a destination
that doesn't currently exist (e.g. a disabled plugin's id), the app falls
back to the first available destination rather than crashing (this
should already work via the existing Tier 0 fallback logic — this test
locks that guarantee in for the new call site specifically).

- [ ] **Step 5: Verify and commit**

Run `flutter analyze` and `flutter test` in Omnis. Commit.

---

### Task 2: Fix the sidebar drawer's hardcoded tab-index bug

**Files:**
- Modify: `lib/ui/widgets/global_sidebar_drawer.dart:107` (the
  `widget.onSelectDestination(2)` call, and its surrounding
  `onSelectDestination` callback signature/type if changed)
- Test: whichever test file covers `GlobalSidebarDrawer` — grep for it

**Interfaces:** None new — this is a latent-bug fix independent of
Tier 2's extraction tasks, but must land before Task 3 (Home extraction)
changes `_coreDestinationIds`' order, since that's the change that turns
this from a latent bug into an active one (removing `'home'` from the
core id list shifts every subsequent core id's index down by one,
including whatever index `'playlist'` currently resolves to).

**The bug**: `global_sidebar_drawer.dart:107` calls
`widget.onSelectDestination(2)` — a bare literal assuming "Playlist" is
always at tab index 2. `home_page.dart` itself was fully converted to
id-keyed selection in Tier 0's final review fix wave; this one call site
in a different file was missed by that sweep.

- [ ] **Step 1: Read the current call site and its context**

Read `global_sidebar_drawer.dart` in full (particularly around line 107
and wherever `onSelectDestination`'s type is declared/passed in from
`home_page.dart`) to understand exactly what triggers this call (the
report found it's a "jump to Playlist" action reachable from the sidebar
drawer — confirm this description matches what you find).

- [ ] **Step 2: Convert to id-based resolution**

The cleanest fix, consistent with how `home_page.dart` itself resolves
ids to indices (`destinationIds.indexOf(id)`), is to change
`GlobalSidebarDrawer`'s `onSelectDestination` callback type from
`ValueChanged<int>` to something that can express "select by id" — check
whether `home_page.dart` already passes `destinationIds` (the full
ordered id list) into `GlobalSidebarDrawer`'s constructor for its other
existing id-keyed reaches (the report found `widget.moodsKey`/
`widget.playlistKey` are already passed in directly, suggesting
`destinationIds` may already be available to this widget too — verify
this by reading the constructor). If `destinationIds` is already
available, replace the literal `2` with
`widget.onSelectDestination(widget.destinationIds.indexOf('playlist'))`
(falling back sensibly — e.g. to `0` — if `indexOf` returns `-1`, mirroring
`home_page.dart`'s own fallback pattern, though 'playlist' should always
exist since it's a permanently-core id per this plan's scope). If
`destinationIds` is not already available, add it as a new required
constructor parameter, threaded through from `home_page.dart`'s existing
`GlobalSidebarDrawer(...)` construction call.

- [ ] **Step 3: Tests**

Add a test confirming tapping this sidebar action selects the Playlist
tab correctly, ideally in a fixture where a plugin destination is
registered *before* the core `'playlist'` id in the rendered list — wait,
per this plan's own architecture, plugin destinations always render
*after* core ones (Tier 0's contract), so the real regression case this
bug fix guards against is a *future* core-id-list reordering (like Task
3 removing `'home'`), not a plugin-destination scenario. Write the test
to register a fixture plugin contributing at least one destination and
confirm the sidebar's "jump to Playlist" action still resolves to the
Playlist tab correctly regardless of how many plugin tabs are appended
after it — this is the test that would have caught the original bug once
Task 3 lands, if written against the pre-Task-3 core id list order.

- [ ] **Step 4: Verify and commit**

Run `flutter analyze` and `flutter test`. Commit.

---

### Task 3: Extract Home dashboard into a bundled plugin

**Files:**
- Create (Omnis-Plugins repo): `lib/home_dashboard_plugin.dart` (new
  `MusicPlugin` wrapping the extracted page)
- Move (Omnis repo → Omnis-Plugins repo): `lib/ui/home_dashboard_page.dart`
  → `Omnis-Plugins/lib/home_dashboard_page.dart` (or a subdirectory,
  matching this repo's existing convention — check whether other bundled
  plugins' large page-owning files sit directly under `lib/` or in a
  named subfolder before choosing)
- Move (Omnis repo → Omnis-Plugins repo): `lib/core/home_layout_store.dart`
  → `Omnis-Plugins/lib/home_layout_store.dart`
- Modify: `packages/omnis_plugin_api/lib/service_interfaces.dart` (new
  `IHomeCustomizer` interface)
- Modify: `packages/omnis_plugin_api/lib/plugin_destination.dart`
  (retire `'home'` from the reserved-id doc comment)
- Modify: `lib/ui/home_page.dart` (remove the hardcoded Home tab, the
  `_homeDashboardKey` `GlobalKey` reach, `'home'` from
  `_coreDestinationIds`)
- Modify: `Omnis-Plugins/lib/bundled_plugins.dart` (register the new
  plugin)
- Test: move/adapt `test/home_dashboard_page_test.dart` to the
  Omnis-Plugins repo's `test/`; add plugin-lifecycle tests

**Interfaces:**
- Consumes: `HomeDashboardPageState.openCustomizeSheet()` (existing
  method, currently `home_dashboard_page.dart:167-174`) — becomes the
  implementation behind the new interface below.
- Produces: `IHomeCustomizer` (new, in `service_interfaces.dart`):

```dart
/// Opens the Home dashboard's "customize" bottom sheet (pick which
/// sections show, in what order) — reached from the command palette's
/// "Customize home" action. Registered by whichever plugin owns the Home
/// dashboard tab; before Tier 2, `home_page.dart` reached this directly
/// via a `GlobalKey<HomeDashboardPageState>` into a widget it constructed
/// itself, which stopped being possible once the dashboard became a
/// plugin-owned page `home_page.dart` only holds a `WidgetBuilder` for.
abstract class IHomeCustomizer {
  /// Opens the customize sheet. A no-op if the dashboard isn't currently
  /// visible/mounted — matches the previous `GlobalKey?.currentState?.`
  /// null-safe-no-op behavior exactly, so a stale command-palette action
  /// (dashboard plugin disabled after the palette opened) degrades
  /// silently rather than throwing.
  void openCustomizeSheet();
}
```

- [ ] **Step 1: Read the full current `home_dashboard_page.dart` and `home_layout_store.dart`**

Read both files completely — 485 and 165 lines respectively per planning
research, but re-confirm current sizes. Note every import that currently
resolves within the Omnis repo (`package:omnis/...`) that will need to
become either a package import from `omnis_plugin_api` (if it's a shared
contract type already exported there) or a `package:omnis_plugins/...`
sibling-file import (if it's moving with this file) or stay an
already-established cross-repo reach (if it's a core singleton a
bundled plugin can already reach, like `locator<MainCore>()`).

- [ ] **Step 2: Add `IHomeCustomizer` to `service_interfaces.dart`**

Add the interface exactly as specified above.

- [ ] **Step 3: Move `home_layout_store.dart` to Omnis-Plugins**

This is the dashboard's customization-persistence layer
(`HomeLayoutStore.instance`, `applyHomeLayout`, `homeSectionCatalog`,
`HomeSectionPreference`). Move it verbatim into the Omnis-Plugins repo,
adjusting only its imports (the same "verbatim move, fix imports" pattern
Tier 1 used for `smart_playlist_rule.dart`/`track_tags.dart`). Confirm
whether it depends on anything Omnis-repo-only (if it uses
`SharedPreferences` directly, that's already available to a bundled
plugin package with no change needed; if it reaches `AppSettings.instance`
directly, per this codebase's established "a plugin should use its own
`PluginStorage`, not reach into `AppSettings`" principle — documented in
`docs/PLUGIN_GUIDE.md` — read that guidance and adapt `HomeLayoutStore` to
use `PluginStorage` instead if it currently touches `AppSettings`
directly; if it already uses its own persistence and never touches
`AppSettings`, no change needed there).

- [ ] **Step 4: Move `home_dashboard_page.dart` and convert it into a bundled plugin**

Create `Omnis-Plugins/lib/home_dashboard_plugin.dart`: a `MusicPlugin`
subclass (follow `radio_plugin.dart`'s exact shape — `id`, `name`,
`description`, `version`, `author`, `initialize()`/`enable()`/`disable()`/
`dispose()` registering/unregistering `IHomeCustomizer`) whose
`homeDestinations()` override returns:

```dart
  @override
  List<PluginDestination> homeDestinations() => [
        PluginDestination(
          id: 'home',
          icon: OmnisIconCatalog.home.resolve(),
          label: 'Home',
          pageBuilder: (context) => HomeDashboardPage(
            engine: locator<AudioEngine>(),
            pluginManager: locator<PluginManager>(),
          ),
        ),
      ];
```

(Keeping the id `'home'` even though it's no longer in the *reserved*
core-id list — reusing the existing id string is harmless and avoids an
unnecessary breaking change to anyone who might reference it; only the
reservation doc comment in `plugin_destination.dart` changes, not the
string itself.) Confirm `OmnisIconCatalog`/`locator`/`AudioEngine`/
`PluginManager` are all genuinely reachable from a bundled plugin file the
same way `radio_plugin.dart` or another already-converted plugin reaches
them — read one such plugin's actual imports to confirm the exact import
paths, don't guess.

Move `home_dashboard_page.dart` itself into the Omnis-Plugins repo
(same directory convention decided in Step 1's investigation). It
currently implements `HomeDashboardPageState.openCustomizeSheet()` — make
the new plugin class implement `IHomeCustomizer` and delegate
`openCustomizeSheet()` to whatever the currently-mounted page instance is.
Since a plugin's `pageBuilder` constructs a fresh widget each time
`home_page.dart`'s `IndexedStack` needs it (not something the plugin class
itself holds a reference to), the plugin needs its own way to reach the
live `HomeDashboardPageState` — the established pattern for this
"plugin needs to reach into its own currently-mounted page" problem is a
`GlobalKey` *owned by the plugin itself* (not by `home_page.dart`), held
as a field on the plugin class and passed to the `HomeDashboardPage`
constructor inside `homeDestinations()`'s `pageBuilder`. This keeps the
`GlobalKey` reach entirely inside the plugin's own code — `home_page.dart`
never sees it, only the `IHomeCustomizer.openCustomizeSheet()` interface
call reaches across the boundary. Implement `openCustomizeSheet()` as:

```dart
  final _dashboardKey = GlobalKey<HomeDashboardPageState>();

  @override
  void openCustomizeSheet() {
    _dashboardKey.currentState?.openCustomizeSheet();
  }
```

and reference `_dashboardKey` as the `key:` in the `pageBuilder`'s
`HomeDashboardPage(key: _dashboardKey, ...)` construction.

- [ ] **Step 5: Update `home_page.dart`**

Remove: `'home'` from `_coreDestinationIds`; the `_homeDashboardKey` field
and its `GlobalKey<HomeDashboardPageState>` type; the hardcoded
`HomeDashboardPage(key: _homeDashboardKey, ...)` entry from the `pages`
list; the hardcoded Home entry from the `destinations`
icon/label list; the `import 'package:omnis/ui/home_dashboard_page.dart';`
(now moved). Change the `'customize_home'` command-palette action
(currently `home_page.dart:277-280`) from
`_homeDashboardKey.currentState?.openCustomizeSheet()` to
`pluginManager.services.get<IHomeCustomizer>()?.openCustomizeSheet()`.

- [ ] **Step 6: Register the plugin**

Add `() => HomeDashboardPlugin()` to `Omnis-Plugins/lib/bundled_plugins.dart`'s
factory list (`createBundledPlugins()`), matching the existing entries'
exact shape (each wrapped in the file's own try/catch pattern — this is
automatic since it's a shared loop, not per-entry).

- [ ] **Step 7: Tests**

Move/adapt `test/home_dashboard_page_test.dart` into the Omnis-Plugins
repo's `test/` directory, fixing imports for the new location. Add a
plugin-lifecycle test (`HomeDashboardPlugin` registers/unregisters
`IHomeCustomizer` on initialize/enable/disable/dispose, matching the
established pattern from `radio_plugin_test.dart`/`ringtone_plugin_test.dart`
in prior plans this session). In the Omnis repo, add/extend a
`home_page.dart` test confirming: with the Home plugin disabled, no
`'home'` tab renders and the app doesn't crash; with it enabled, the
command palette's "Customize home" action correctly reaches
`openCustomizeSheet()` through the new interface path.

- [ ] **Step 8: Verify and commit**

Run `flutter analyze` and `flutter test` in both repos. Commit each
repo's changes separately.

---

### Task 4: Extract the Moods cluster into a bundled plugin

**Files:**
- Create (Omnis-Plugins repo): `lib/moods_plugin.dart`
- Move (Omnis repo → Omnis-Plugins repo): the Moods UI code currently
  inline in `lib/ui/home_page.dart` (per planning research, lines
  556-969 — re-read the current file to get the true current range,
  since Tasks 1-3 shift it) into its own file, e.g.
  `Omnis-Plugins/lib/moods_page.dart`
- Move: `lib/ui/mood_builder_dialog.dart`, `lib/core/custom_mood.dart`,
  `lib/ui/forgotten_music_page.dart`, `lib/core/forgotten_tracks.dart` —
  all four, since planning research confirmed these form one cluster
  (Forgotten Music is reached from inside the Moods page, matching the
  spec's own Tier-3 sequencing note)
- Modify: `packages/omnis_plugin_api/lib/service_interfaces.dart` (new
  `IMoodPlayer` interface)
- Modify: `packages/omnis_plugin_api/lib/plugin_destination.dart`
  (retire `'moods'` from the reserved-id doc comment)
- Modify: `lib/ui/home_page.dart` (remove the inline Moods classes, the
  `_moodsKey` reach, `'moods'` from `_coreDestinationIds`)
- Modify: `lib/ui/widgets/global_sidebar_drawer.dart` (its own
  `moodsKey`-based reaches — 2 call sites per planning research)
- Modify: `Omnis-Plugins/lib/bundled_plugins.dart`
- Test: new/moved test files for the relocated code

**Interfaces:**
- Consumes: `MoodsPageState.playMood(String mood)` and
  `MoodsPageState.playCustomMood(CustomMood custom)` (existing methods).
- Produces: `IMoodPlayer` (new, in `service_interfaces.dart`):

```dart
/// Plays a named mood/custom mood directly — reached from the command
/// palette's "search everywhere" mood results and the pop-out sidebar's
/// "MY MOODS" section. Registered by whichever plugin owns the Moods
/// tab; the same `GlobalKey`-into-a-plugin-owned-widget problem
/// `IHomeCustomizer` solves for the Home dashboard.
abstract class IMoodPlayer {
  /// Plays the built-in preset mood named [mood]. A no-op if the Moods
  /// page isn't currently mounted or [mood] doesn't match a known
  /// preset — matches the previous null-safe `GlobalKey` behavior.
  void playMood(String mood);

  /// Plays a user-created custom mood.
  void playCustomMood(CustomMood custom);
}
```

(`CustomMood` is already defined in `lib/core/custom_mood.dart`, which
this task moves into `omnis_plugin_api` or Omnis-Plugins — determine
which in Step 1 below, since `IMoodPlayer`'s signature needs it importable
from wherever `service_interfaces.dart` lives.)

- [ ] **Step 1: Read the full current Moods cluster**

Read `home_page.dart`'s current Moods section (`MoodsPage`,
`MoodsPageState`, and every private helper/widget between them) in full,
plus `mood_builder_dialog.dart`, `custom_mood.dart`, `forgotten_music_page.dart`,
`forgotten_tracks.dart` completely. Determine where `CustomMood` (from
`custom_mood.dart`) needs to live: if `IMoodPlayer.playCustomMood`'s
signature requires it, and `service_interfaces.dart` lives in
`omnis_plugin_api`, then `CustomMood` (or at least its plain-data shape)
needs to be reachable from that package — following the exact "move a
plugin-owned value type into `omnis_plugin_api` when a capability
interface needs to return/accept it" pattern Tier 1 established twice
(`track_tags.dart`, `smart_playlist_rule.dart`). Read `custom_mood.dart`'s
actual dependencies first to confirm it's a clean, dependency-free-beyond-
`omnis_plugin_api` move like those two were, and note any deviation if it
isn't.

- [ ] **Step 2: Move `custom_mood.dart`, `forgotten_tracks.dart` as needed, add `IMoodPlayer`**

Move `custom_mood.dart` to `packages/omnis_plugin_api/lib/custom_mood.dart`
if Step 1 confirms it's needed there (clean, `omnis_plugin_api`-only
dependencies); otherwise move it directly into `Omnis-Plugins/lib/` and
have `IMoodPlayer.playCustomMood` accept a narrower type instead (a
plain id/name string, if that's sufficient — check the real call sites in
`global_sidebar_drawer.dart` to see what's actually needed. Move
`forgotten_tracks.dart` into `Omnis-Plugins/lib/` (it appears to be a
Moods-cluster-only dependency per planning research — confirm no other
file outside this cluster imports it before moving it wholesale). Add
`IMoodPlayer` to `service_interfaces.dart`.

- [ ] **Step 3: Move the Moods UI into its own file and convert to a plugin**

Extract `MoodsPage`/`MoodsPageState` out of `home_page.dart` into
`Omnis-Plugins/lib/moods_page.dart`, and move `mood_builder_dialog.dart`
and `forgotten_music_page.dart` alongside it into Omnis-Plugins. Create
`Omnis-Plugins/lib/moods_plugin.dart` following the exact same shape as
Task 3's `HomeDashboardPlugin` — a plugin-owned `GlobalKey<MoodsPageState>`
field, `homeDestinations()` returning one `PluginDestination` with
`id: 'moods'`, and `IMoodPlayer`'s two methods delegating to
`_moodsKey.currentState?.playMood(...)`/`playCustomMood(...)`.

- [ ] **Step 4: Update `home_page.dart`**

Remove the now-relocated `MoodsPage`/`MoodsPageState` classes entirely;
remove `'moods'` from `_coreDestinationIds`; remove the `_moodsKey` field
and its hardcoded `MoodsPage(key: _moodsKey, ...)` entry; remove the Moods
icon/label from `destinations`. Change the command palette's
`onSelectMood` callback (currently `home_page.dart:326-329`) from
`_moodsKey.currentState?.playMood(mood)` to
`pluginManager.services.get<IMoodPlayer>()?.playMood(mood)`.

- [ ] **Step 5: Update `global_sidebar_drawer.dart`**

Convert its own `widget.moodsKey.currentState?.playCustomMood(custom)`
and `widget.moodsKey.currentState?.playMood(name)` call sites (planning
research: lines 121, 123) to the same
`pluginManager.services.get<IMoodPlayer>()?.playCustomMood(custom)`/
`playMood(name)` pattern — this widget will need a `PluginManager`
reference if it doesn't already have one (check its current constructor
parameters; `home_page.dart` already has one to pass in). Remove the
`moodsKey` constructor parameter entirely once nothing inside this widget
needs a raw `GlobalKey<MoodsPageState>` anymore.

- [ ] **Step 6: Register the plugin, retire the reserved id**

Add `() => MoodsPlugin()` to `bundled_plugins.dart`. Update
`plugin_destination.dart`'s reserved-id doc comment to drop `'moods'`.

- [ ] **Step 7: Tests**

Move/adapt every test file covering the relocated code
(`home_page.dart`'s existing Moods-related tests, plus any dedicated
`mood_builder_dialog_test.dart`/`forgotten_music_page_test.dart` if they
exist — grep for them first) into the Omnis-Plugins repo. Add a
plugin-lifecycle test for `MoodsPlugin` matching the established pattern.
In the Omnis repo, extend `home_page.dart`'s and `global_sidebar_drawer.dart`'s
tests to confirm the `IMoodPlayer` interface path works with the plugin
enabled and degrades to a no-op (not a crash) with it disabled.

- [ ] **Step 8: Verify and commit**

Run `flutter analyze` and `flutter test` in both repos. Commit each
repo's changes separately.

---

### Task 5: Extract Radio+Online into a bundled plugin; delete dead `RadioPage`

**Files:**
- Delete: `lib/ui/radio_page.dart`'s standalone `RadioPage` class (keep
  `RadioBody` — read the file first to confirm exactly which classes are
  in this file and which, if any beyond `RadioPage` itself, are genuinely
  unused outside tests)
- Delete: `test/radio_page_test.dart`'s tests that only exercise the
  deleted `RadioPage` wrapper (not `RadioBody`, which stays — read the
  file to separate the two before deleting anything)
- Create (Omnis-Plugins repo): `lib/online_plugin.dart`
- Move (Omnis repo → Omnis-Plugins repo): `lib/ui/online_page.dart`
  (with `RadioBody` from `radio_page.dart` — decide in Step 1 whether to
  merge `RadioBody` into the same moved file or keep it as its own
  sibling file, based on how tightly coupled they currently are), and
  `lib/core/custom_radio_station_store.dart`
- Modify: `packages/omnis_plugin_api/lib/plugin_destination.dart`
  (retire `'online'`)
- Modify: `lib/ui/home_page.dart` (remove the hardcoded Online tab,
  `'online'` from `_coreDestinationIds`)
- Modify: `Omnis-Plugins/lib/bundled_plugins.dart`
- Test: moved/adapted test files

**Interfaces:** None new — `IRadioProvider`, `IFavoritesProvider`, and
`IOnlineSearchProvider` already fully cover this page's internal needs
per Tier 0/Tier 1 (confirmed by planning research: zero remaining
concrete-type reaches in either file). This task is purely about
relocating the destination-owning code and wiring `homeDestinations()` —
no command-palette/`GlobalKey` reach exists into this page today (planning
research found none), so there's no capability-interface gap to fill.

- [ ] **Step 1: Read the current `radio_page.dart` and `online_page.dart` in full**

Confirm the planning research's finding that `RadioPage` (the standalone
`Scaffold` wrapper) has zero production references — grep
`grep -rn "RadioPage(" lib/` yourself to confirm before deleting anything
(the earlier research found references only inside `test/radio_page_test.dart`,
11 call sites) — and decide whether `RadioBody` should move into
`online_page.dart` directly or stay a separate file that moves alongside
it, based on how self-contained `RadioBody` already is as its own class.

- [ ] **Step 2: Delete `RadioPage`**

Remove the `RadioPage` class from `radio_page.dart`, keeping `RadioBody`
(move it per Step 1's decision). Update `test/radio_page_test.dart`:
remove every test that constructs `RadioPage` directly; keep/move
whatever tests exercise `RadioBody` directly, relocating them alongside
wherever `RadioBody` ends up. If literally nothing remains that needs a
standalone `radio_page.dart` file in the Omnis repo after this (i.e.
`RadioBody` moves entirely into Omnis-Plugins with `online_page.dart`),
delete the now-empty `radio_page.dart` file too.

- [ ] **Step 3: Move `online_page.dart` (+`RadioBody`) and `custom_radio_station_store.dart`, convert to a plugin**

Move both files into Omnis-Plugins per Step 1's decision on `RadioBody`'s
final location. Create `Omnis-Plugins/lib/online_plugin.dart` following
the same `MusicPlugin` shape as Tasks 3-4's plugins, with
`homeDestinations()` returning one `PluginDestination` with
`id: 'online'`, `pageBuilder: (context) => OnlinePage(engine:
locator<AudioEngine>(), pluginManager: locator<PluginManager>())` (no
`GlobalKey`/capability-interface registration needed for this plugin,
per this task's "Interfaces: None new" note — unless Step 1's re-read
finds a reach this plan's research missed, in which case treat it the
same way Tasks 3-4 handled their own reaches and note the deviation).

- [ ] **Step 4: Update `home_page.dart`**

Remove `'online'` from `_coreDestinationIds`; remove the hardcoded
`OnlinePage(...)` entry from `pages`; remove its icon/label from
`destinations`; remove the now-unused import.

- [ ] **Step 5: Register the plugin, retire the reserved id**

Add `() => OnlinePlugin()` to `bundled_plugins.dart`. Update
`plugin_destination.dart`'s reserved-id doc comment to drop `'online'`.

- [ ] **Step 6: Tests**

Move/adapt `test/online_page_test.dart` (and whatever remains of
`radio_page_test.dart` per Step 2) into Omnis-Plugins. Add a
plugin-lifecycle test for `OnlinePlugin` — even with no capability
interface to register, confirm `initialize()`/`enable()`/`disable()`/
`dispose()` all complete without error and `homeDestinations()` returns
the expected single destination when enabled, empty when disabled.

- [ ] **Step 7: Verify and commit**

Run `flutter analyze` and `flutter test` in both repos. Commit each
repo's changes separately.

---

### Task 6: Cross-repo dependency pin bump

**Files:**
- Modify: `Omnis/pubspec.yaml` (both the `omnis_plugins:` ref and the
  self-referential `omnis_plugin_api:` ref — this repo has two separate
  declarations of the same dependency, a fact Tier 1's own pin-bump task
  discovered is easy to miss)
- Modify: `Omnis-Plugins/pubspec.yaml` (`omnis_plugin_api:` ref)

**Interfaces:** None — version pins only, no code changes.

- [ ] **Step 1: Bump Omnis-Plugins' own `omnis_plugin_api` pin first**

Cut a new `plugin-api-vX.Y.Z` tag on the Omnis repo at its current HEAD
(after Tasks 1-5 have all landed there — this task runs last).
Bump `Omnis-Plugins/pubspec.yaml`'s `omnis_plugin_api:` ref to that tag,
commit.

- [ ] **Step 2: Cut Omnis-Plugins' own release tag**

Only after Step 1's commit is Omnis-Plugins' HEAD — cut a new `vA.B.C`
tag there, push it.

- [ ] **Step 3: Bump Omnis's own pins**

Bump `Omnis/pubspec.yaml`'s `omnis_plugins:` ref to the Step 2 tag, and
its separate self-referential `omnis_plugin_api:` ref to the Step 1 tag
(both need to agree — this is the exact pin Tier 1's fix wave found easy
to miss). Commit.

- [ ] **Step 4: Verify with overrides removed**

In both repos, temporarily rename `pubspec_overrides.yaml` aside, run a
fresh `flutter pub get`/`analyze`/`test` (forcing real tag resolution
instead of the local sibling-checkout override), confirm clean, then
restore the override files and do one final normal-mode `analyze`/`test`
pass in both repos, also clean.

---

## After This Plan

Three of the six originally-reserved core destination ids (`home`,
`moods`, `online`) are now plugin-contributed; `library`, `playlist`,
`settings` remain permanently core. A plugin-less install opens to
Library by default (or whatever the user has since changed their launch
default to). T2.4 (moving Settings sub-pages behind `uiSlot('settings_page')`
injection) remains explicitly deferred, per the original spec's own
"sequenced after each feature's own extraction lands, not as one
big-bang task" guidance — the planning research for this plan found the
split isn't as clean as the spec assumed for several files
(`accessibility_settings_page.dart`, `keyboard_settings_page.dart`,
`playback_settings_page.dart`, `appearance_settings_page.dart` each mix
core and plugin-candidate content), so T2.4 should be scoped as its own
follow-up investigation once this plan's three extractions are verified
working end-to-end, not assumed solvable as a simple file-by-file split.

Tier 3 (the independent, no-tab-mechanism-dependency cluster — A/B
loop+DJ tools, tag/organization, similarity, statistics, and the
higher-risk `MainCore`-owned-timer extractions: queue continuation,
playback scheduling, backup) and Tier 4 (the downloadable-plugin
declarative page DSL) remain unplanned, per the original spec's own
scoping.
