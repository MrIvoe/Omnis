# Core/Plugin Re-architecture — Tier 0 (Blocking Foundation) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give bundled plugins a way to register a whole new top-level
tab in the app's navigation (not just inject into an existing slot),
make `home_page.dart`'s hardcoded tab list absorb those contributions
safely, and prove the "stop reaching a plugin by concrete type, use an
interface instead" conversion pattern on the simplest remaining case
(Radio) so Tier 1's other five conversions can copy it directly.

**Architecture:** `MusicPlugin` gains an optional `homeDestinations()`
method returning `PluginDestination` objects (icon/label/id/page
builder). `PluginManager` aggregates these across enabled bundled
plugins the same way it already aggregates `uiSlot()` results.
`home_page.dart` appends the aggregated list after its six fixed
tabs and clamps `_selectedIndex` so a plugin disabled mid-session can
never leave the index pointing past the end of a shrunk list. Radio's
conversion follows the exact template the Favorites conversion already
proved this session: add a capability interface, implement it on the
bundled plugin, switch the UI call sites to look it up by interface.

**Tech Stack:** Flutter/Dart, existing `PluginManager`/`ServiceRegistry`
mechanisms — no new dependencies.

**Spec:** `docs/superpowers/specs/2026-08-22-core-plugin-rearchitecture-plan.md`
(Part 2 for the tab mechanism design, Tier 0 for this plan's scope)

## Global Constraints

- Downloadable (sandboxed) plugins CANNOT contribute a `homeDestinations()`
  entry in this phase — the sandbox has no way to return a real
  `Widget`. `homeDestinations()` is bundled-plugin-only; do not attempt
  to bridge it into `dart_eval`.
- Core's six fixed destinations (Home, Library, Playlist, Moods,
  Online, Settings) never change position or count in this plan —
  plugin destinations are always appended after them. This is what
  keeps every existing literal `_selectedIndex = N` assignment for a
  *core* destination correct without being rewritten.
- Every new/changed public method must run through the existing
  `_sandbox.runSync`/`_sandbox.run` crash-isolation pattern — a
  plugin's `homeDestinations()` throwing must never crash the app,
  exactly like every other `MusicPlugin` hook today.
- `flutter analyze` must stay clean (0 issues) in both `c:\Users\MrIvo\Github\Omnis`
  and `c:\Users\MrIvo\Github\Omnis-Plugins` after every task.
- Run the full test suite (`flutter test`, no path filter) in whichever
  repo a task touches before committing — not just the new test file.

---

### Task 1: Add the `PluginDestination` type and `homeDestinations()` hook to the plugin contract

**Files:**
- Create: `c:\Users\MrIvo\Github\Omnis\packages\omnis_plugin_api\lib\plugin_destination.dart`
- Modify: `c:\Users\MrIvo\Github\Omnis\packages\omnis_plugin_api\lib\plugin_interface.dart`
- Test: `c:\Users\MrIvo\Github\Omnis\packages\omnis_plugin_api\test\plugin_destination_test.dart` (create the `test/` directory if it doesn't already exist in this package)

**Interfaces:**
- Produces: `class PluginDestination` with fields `String id`, `IconData icon`, `String label`, `WidgetBuilder pageBuilder`, `int order` (default `0`) — used by Task 2 (`PluginManager.homeDestinations` getter) and Task 3 (`home_page.dart`).
- Produces: `MusicPlugin.homeDestinations()` — an instance method, default implementation returns `const []`, overridable by any bundled plugin.

- [ ] **Step 1: Check whether `packages/omnis_plugin_api` already has a `test/` directory**

Run: `ls c:\Users\MrIvo\Github\Omnis\packages\omnis_plugin_api\test 2>&1 || echo "NO_TEST_DIR"`

If it prints `NO_TEST_DIR`, check `pubspec.yaml` in that package for a
`flutter_test`/`test` dev_dependency before writing Step 2 — if
missing, add `test: ^1.24.0` under `dev_dependencies:` in
`c:\Users\MrIvo\Github\Omnis\packages\omnis_plugin_api\pubspec.yaml`
(this package has no Flutter widget dependencies, so plain `package:test`,
not `flutter_test`, is correct here — `PluginDestination` only needs
`IconData`/`WidgetBuilder` from `package:flutter/widgets.dart`, which
this package can depend on directly the same way `hardware_eq_band.dart`
or other UI-adjacent contracts in this package already do — verify by
running `grep -rn "package:flutter" c:\Users\MrIvo\Github\Omnis\packages\omnis_plugin_api\lib\`
first; if nothing currently imports Flutter from this package, add
`flutter: sdk: flutter` under `dependencies:` instead of introducing a
version-pinned Flutter package dependency).

- [ ] **Step 2: Write the failing test**

```dart
// c:\Users\MrIvo\Github\Omnis\packages\omnis_plugin_api\test\plugin_destination_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnis_plugin_api/plugin_destination.dart';

void main() {
  test('PluginDestination holds the fields home_page.dart needs to '
      'render a plugin-contributed tab', () {
    Widget builder(BuildContext context) => const Placeholder();

    const destination = PluginDestination(
      id: 'my_plugin_tab',
      icon: Icons.star,
      label: 'My Tab',
      pageBuilder: builder,
    );

    expect(destination.id, 'my_plugin_tab');
    expect(destination.icon, Icons.star);
    expect(destination.label, 'My Tab');
    expect(destination.pageBuilder, builder);
    expect(destination.order, 0, reason: 'default order is 0');
  });

  test('order can be set explicitly for sorting relative to other '
      'plugin destinations', () {
    Widget builder(BuildContext context) => const Placeholder();
    const destination = PluginDestination(
      id: 'x',
      icon: Icons.star,
      label: 'X',
      pageBuilder: builder,
      order: 5,
    );
    expect(destination.order, 5);
  });
}
```

(If Step 1 determined this package has no `flutter_test` dependency
because it's never had a widget-touching test before, add
`flutter_test: sdk: flutter` under `dev_dependencies:` in this
package's `pubspec.yaml` alongside the `flutter` runtime dependency —
both are needed together since `flutter_test`'s `testWidgets`/`test`
APIs and `IconData` both come from the Flutter SDK, not pub.dev.)

- [ ] **Step 3: Run the test to verify it fails**

Run: `cd c:\Users\MrIvo\Github\Omnis\packages\omnis_plugin_api && flutter test test/plugin_destination_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:omnis_plugin_api/plugin_destination.dart'`

- [ ] **Step 4: Write the implementation**

```dart
// c:\Users\MrIvo\Github\Omnis\packages\omnis_plugin_api\lib\plugin_destination.dart
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
  /// core destination's reserved ids: `home`, `library`, `playlist`,
  /// `moods`, `online`, `settings`) is the contributing plugin's bug to
  /// avoid, not something this type validates.
  final String id;

  /// The icon shown in the navigation rail/bar for this destination.
  final IconData icon;

  /// The label shown alongside [icon].
  final String label;

  /// Builds the persistent page shown when this destination is
  /// selected. Called once per `IndexedStack` entry, the same as every
  /// existing core tab's page widget — the returned widget's own
  /// `State` (if any) survives tab switches for as long as the
  /// contributing plugin stays enabled.
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
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd c:\Users\MrIvo\Github\Omnis\packages\omnis_plugin_api && flutter test test/plugin_destination_test.dart`
Expected: PASS (2 tests)

- [ ] **Step 6: Add `homeDestinations()` to `MusicPlugin`**

Open `c:\Users\MrIvo\Github\Omnis\packages\omnis_plugin_api\lib\plugin_interface.dart`.
Add the import at the top:

```dart
import 'package:omnis_plugin_api/plugin_destination.dart';
```

Add this method to the `MusicPlugin` class body, immediately after the
existing `uiSlot` method (after line 100, before `/// Called when the
plugin is shut down.` at line 102):

```dart
  /// Optional. A plugin that wants a persistent top-level tab (not
  /// just an injected slot) returns one or more [PluginDestination]s
  /// here. Default: none — most plugins have nothing to add at this
  /// level and stay purely `uiSlot`-based.
  ///
  /// Called once per `PluginManager.homeDestinations` read (today:
  /// every time `home_page.dart` rebuilds), sandboxed the same as
  /// every other hook — a throwing override degrades to "this plugin
  /// contributes no destinations this time," never a crash.
  List<PluginDestination> homeDestinations() => const [];
```

- [ ] **Step 7: Run `flutter analyze` on the package**

Run: `cd c:\Users\MrIvo\Github\Omnis\packages\omnis_plugin_api && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 8: Run the full package test suite**

Run: `cd c:\Users\MrIvo\Github\Omnis\packages\omnis_plugin_api && flutter test`
Expected: all tests pass, including the 2 new ones.

- [ ] **Step 9: Commit**

```bash
cd c:\Users\MrIvo\Github\Omnis
git add packages/omnis_plugin_api/lib/plugin_destination.dart packages/omnis_plugin_api/lib/plugin_interface.dart packages/omnis_plugin_api/test/plugin_destination_test.dart packages/omnis_plugin_api/pubspec.yaml
git commit -m "$(cat <<'EOF'
Add PluginDestination and MusicPlugin.homeDestinations()

The contract half of letting a bundled plugin register a whole new
top-level tab instead of only injecting into an existing uiSlot
location. Bundled-plugin-only for now — a downloadable plugin has no
way to produce a real WidgetBuilder under dart_eval.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Aggregate `homeDestinations()` across enabled plugins in `PluginManager`

**Files:**
- Modify: `c:\Users\MrIvo\Github\Omnis\lib\core\plugin_manager.dart`
- Test: `c:\Users\MrIvo\Github\Omnis\test\plugin_manager_home_destinations_test.dart` (create)

**Interfaces:**
- Consumes: `MusicPlugin.homeDestinations()` (Task 1), `_sandbox.runSync({required pluginId, required pluginName, required hook, required T? Function() operation})` (existing, returns `null` on a sandboxed failure — see `register()`'s use of it at `plugin_manager.dart:277` for the exact call shape), `_enabled()` (existing, returns `Iterable<ManagedPlugin>` of currently-enabled plugins, defined at `plugin_manager.dart:1251`).
- Produces: `PluginManager.homeDestinations` — a `List<PluginDestination>` getter, sorted by `order` ascending, empty when no enabled plugin contributes any. Used by Task 3.

- [ ] **Step 1: Write the failing test**

```dart
// c:\Users\MrIvo\Github\Omnis\test\plugin_manager_home_destinations_test.dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/plugin_interface.dart';
import 'package:omnis/core/plugin_manager.dart';
import 'package:omnis/plugin_api/plugin_destination.dart';

Widget _placeholderBuilder(BuildContext context) => const Placeholder();

class _NoDestinationsPlugin extends MusicPlugin {
  @override
  String get id => 'no_destinations';
  @override
  String get name => 'No Destinations';
  @override
  String get description => 'test plugin';
  @override
  String get version => '1.0.0';
  @override
  String get author => 'test';
  @override
  Future<void> initialize() async {}
  @override
  Future<void> onTrackStart(BaseTrack track) async {}
  @override
  Future<void> onLibraryScan(String file) async {}
  @override
  dynamic uiSlot(String locationID) => null;
  @override
  Future<void> dispose() async {}
}

class _OneDestinationPlugin extends MusicPlugin {
  @override
  String get id => 'one_destination';
  @override
  String get name => 'One Destination';
  @override
  String get description => 'test plugin';
  @override
  String get version => '1.0.0';
  @override
  String get author => 'test';
  @override
  Future<void> initialize() async {}
  @override
  Future<void> onTrackStart(BaseTrack track) async {}
  @override
  Future<void> onLibraryScan(String file) async {}
  @override
  dynamic uiSlot(String locationID) => null;
  @override
  Future<void> dispose() async {}

  @override
  List<PluginDestination> homeDestinations() => [
        PluginDestination(
          id: 'one_destination_tab',
          icon: Icons.star,
          label: 'One',
          pageBuilder: _placeholderBuilder,
        ),
      ];
}

class _ThrowingDestinationsPlugin extends MusicPlugin {
  @override
  String get id => 'throwing_destinations';
  @override
  String get name => 'Throwing Destinations';
  @override
  String get description => 'test plugin';
  @override
  String get version => '1.0.0';
  @override
  String get author => 'test';
  @override
  Future<void> initialize() async {}
  @override
  Future<void> onTrackStart(BaseTrack track) async {}
  @override
  Future<void> onLibraryScan(String file) async {}
  @override
  dynamic uiSlot(String locationID) => null;
  @override
  Future<void> dispose() async {}

  @override
  List<PluginDestination> homeDestinations() =>
      throw StateError('boom');
}

void main() {
  test('homeDestinations is empty when no registered plugin contributes any',
      () {
    final manager = PluginManager();
    manager.register(_NoDestinationsPlugin());

    expect(manager.homeDestinations, isEmpty);
  });

  test('homeDestinations collects a contributed destination from an '
      'enabled plugin', () {
    final manager = PluginManager();
    manager.register(_OneDestinationPlugin());

    expect(manager.homeDestinations, hasLength(1));
    expect(manager.homeDestinations.first.id, 'one_destination_tab');
  });

  test('homeDestinations excludes a disabled plugin\'s destinations', () {
    final manager = PluginManager();
    manager.register(_OneDestinationPlugin());
    manager.setEnabled('one_destination', false);

    expect(manager.homeDestinations, isEmpty);
  });

  test('a plugin whose homeDestinations() throws contributes nothing, '
      'without taking down the aggregate call', () {
    final manager = PluginManager();
    manager.register(_ThrowingDestinationsPlugin());
    manager.register(_OneDestinationPlugin());

    expect(manager.homeDestinations, hasLength(1));
    expect(manager.homeDestinations.first.id, 'one_destination_tab');
  });

  test('destinations are sorted by order ascending', () {
    final manager = PluginManager();
    manager.register(_OneDestinationPlugin());
    // Second plugin contributes a lower-order destination that should
    // sort first among plugin destinations.
    manager.register(_LowOrderDestinationPlugin());

    final ids = manager.homeDestinations.map((d) => d.id).toList();
    expect(ids, ['low_order_tab', 'one_destination_tab']);
  });
}

class _LowOrderDestinationPlugin extends MusicPlugin {
  @override
  String get id => 'low_order';
  @override
  String get name => 'Low Order';
  @override
  String get description => 'test plugin';
  @override
  String get version => '1.0.0';
  @override
  String get author => 'test';
  @override
  Future<void> initialize() async {}
  @override
  Future<void> onTrackStart(BaseTrack track) async {}
  @override
  Future<void> onLibraryScan(String file) async {}
  @override
  dynamic uiSlot(String locationID) => null;
  @override
  Future<void> dispose() async {}

  @override
  List<PluginDestination> homeDestinations() => [
        PluginDestination(
          id: 'low_order_tab',
          icon: Icons.star,
          label: 'Low',
          pageBuilder: _placeholderBuilder,
          order: -1,
        ),
      ];
}
```

Before writing this, run `grep -n "void setEnabled\|Future<void> setEnabled" c:\Users\MrIvo\Github\Omnis\lib\core\plugin_manager.dart`
to confirm the exact existing method name/signature for disabling a
plugin by id — if it differs from `setEnabled(String id, bool enabled)`,
adjust the third test above to call whatever the real method is (do
not guess; this method already exists since the Plugins page already
has an enable/disable toggle — find it before writing the test).

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd c:\Users\MrIvo\Github\Omnis && flutter test test/plugin_manager_home_destinations_test.dart`
Expected: FAIL — `The getter 'homeDestinations' isn't defined for the type 'PluginManager'`

- [ ] **Step 3: Add the aggregating getter**

Open `c:\Users\MrIvo\Github\Omnis\lib\core\plugin_manager.dart`. Add
this import near the top with the other `plugin_api`/`omnis_plugin_api`
imports:

```dart
import 'package:omnis_plugin_api/plugin_destination.dart';
```

Add this method immediately after the `uiSlot` method (after the
closing brace at line 1028, before the doc comment for
`uiSlotForPlugin` at line 1031):

```dart
  /// Collect top-level tabs contributed by enabled bundled plugins,
  /// sorted by `PluginDestination.order` ascending — `home_page.dart`
  /// appends these after its own six fixed destinations. Downloadable
  /// (external) plugins never contribute here; only `inProcess`
  /// (bundled) plugins can produce a real `WidgetBuilder`.
  List<PluginDestination> get homeDestinations {
    final result = <PluginDestination>[];
    for (final plugin in _enabled()) {
      if (plugin.inProcess == null) continue;
      final destinations = _sandbox.runSync(
        pluginId: plugin.id,
        pluginName: plugin.name,
        hook: 'homeDestinations',
        operation: () => plugin.inProcess!.homeDestinations(),
      );
      if (destinations != null) result.addAll(destinations);
    }
    result.sort((a, b) => a.order.compareTo(b.order));
    return result;
  }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd c:\Users\MrIvo\Github\Omnis && flutter test test/plugin_manager_home_destinations_test.dart`
Expected: PASS (5 tests). If the "excludes a disabled plugin" test
fails because `setEnabled` isn't the real method name, fix the test to
call the real one found in Step 1 of this task and rerun.

- [ ] **Step 5: Run `flutter analyze`**

Run: `cd c:\Users\MrIvo\Github\Omnis && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Run the full test suite**

Run: `cd c:\Users\MrIvo\Github\Omnis && flutter test`
Expected: all tests pass (no regressions in existing `plugin_manager`-touching tests).

- [ ] **Step 7: Commit**

```bash
cd c:\Users\MrIvo\Github\Omnis
git add lib/core/plugin_manager.dart test/plugin_manager_home_destinations_test.dart
git commit -m "$(cat <<'EOF'
Aggregate PluginDestination across enabled bundled plugins

PluginManager.homeDestinations mirrors the existing uiSlot() aggregation
pattern exactly: sandboxed per-plugin, a throwing override contributes
nothing rather than crashing the aggregate call, and a disabled plugin
is excluded. Sorted by order ascending for home_page.dart (Task 3) to
append after its fixed destinations.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Make `home_page.dart` render plugin-contributed destinations, with safe index clamping

**Files:**
- Modify: `c:\Users\MrIvo\Github\Omnis\lib\ui\home_page.dart`
- Test: `c:\Users\MrIvo\Github\Omnis\test\home_page_plugin_destinations_test.dart` (create)

**Interfaces:**
- Consumes: `PluginManager.homeDestinations` (Task 2), existing `HomeDestinationInfo(IconData icon, String label)` constructor from `lib/ui/home_navigation.dart` (unchanged).
- Produces: nothing new for later tasks — this is a leaf UI change. Tier 1/2 tasks will call `core.pluginManager.homeDestinations` themselves where needed, not through anything added here.

- [ ] **Step 1: Read the current destinations/pages construction to confirm line numbers haven't shifted**

Run: `grep -n "final pages = <Widget>\[\|final destinations = \[\|IndexedStack(index: _selectedIndex" c:\Users\MrIvo\Github\Omnis\lib\ui\home_page.dart`

Confirm the three matches are still near lines 265, 320, and 339
respectively (within a few lines is fine; if they've moved
substantially, re-read the surrounding 80 lines before proceeding —
don't blindly trust the line numbers below if the file has changed
since this plan was written).

- [ ] **Step 2: Write the failing test**

```dart
// c:\Users\MrIvo\Github\Omnis\test\home_page_plugin_destinations_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/bootstrap.dart';
import 'package:omnis/core/plugin_interface.dart';
import 'package:omnis/ui/home_page.dart';
import 'package:omnis/plugin_api/plugin_destination.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String tempDir;
  _FakePathProvider(this.tempDir);
  @override
  Future<String?> getApplicationDocumentsPath() async => tempDir;
  @override
  Future<String?> getApplicationSupportPath() async => tempDir;
}

class _TabContributingPlugin extends MusicPlugin {
  @override
  String get id => 'tab_plugin';
  @override
  String get name => 'Tab Plugin';
  @override
  String get description => 'test plugin';
  @override
  String get version => '1.0.0';
  @override
  String get author => 'test';
  @override
  Future<void> initialize() async {}
  @override
  Future<void> onTrackStart(BaseTrack track) async {}
  @override
  Future<void> onLibraryScan(String file) async {}
  @override
  dynamic uiSlot(String locationID) => null;
  @override
  Future<void> dispose() async {}

  @override
  List<PluginDestination> homeDestinations() => [
        PluginDestination(
          id: 'tab_plugin_tab',
          icon: Icons.extension,
          label: 'Extra Tab',
          pageBuilder: (context) =>
              const Center(child: Text('Extra Tab Content')),
        ),
      ];
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PathProviderPlatform.instance =
        _FakePathProvider(Directory.systemTemp.path);
  });

  testWidgets(
      'a plugin-contributed destination appears in the nav after the '
      'six core destinations and its page renders when tapped',
      (tester) async {
    final core = await ensureCoreReady();
    core.pluginManager.register(_TabContributingPlugin());

    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    // Let HomePage's async _bootstrapCore complete.
    await tester.pumpAndSettle();

    expect(find.text('Extra Tab'), findsOneWidget);

    await tester.tap(find.text('Extra Tab'));
    await tester.pumpAndSettle();

    expect(find.text('Extra Tab Content'), findsOneWidget);
  });
}
```

Before running this, check whether an existing `test/home_page_test.dart`
(or similarly-named file) already establishes the correct bootstrap
pattern for testing `HomePage` (it depends on `ensureCoreReady()`,
`AppSettings`, possibly more fakes than shown above) — run:
`grep -rln "HomePage()" c:\Users\MrIvo\Github\Omnis\test\*.dart` and
open whichever file it finds. Copy that file's exact `setUp`/fake-platform
scaffolding instead of the abbreviated version above if it differs —
this plan's version is a best-effort reconstruction, not confirmed
against the real bootstrap requirements, precisely because `HomePage`
has real async startup dependencies (`_bootstrapCore`) that a fresh
plan can't fully predict without reading that existing test first.

- [ ] **Step 3: Run the test to verify it fails**

Run: `cd c:\Users\MrIvo\Github\Omnis && flutter test test/home_page_plugin_destinations_test.dart`
Expected: FAIL — `Extra Tab` not found (the plugin's destination isn't rendered yet).

- [ ] **Step 4: Add the import**

Open `c:\Users\MrIvo\Github\Omnis\lib\ui\home_page.dart`. Add near the
other `omnis/plugin_api`/`omnis_plugin_api` imports:

```dart
import 'package:omnis/plugin_api/plugin_destination.dart';
```

- [ ] **Step 5: Extend the `pages`/`destinations` construction to append plugin destinations**

Replace the block from `final pages = <Widget>[` through the closing
`];` of the `destinations` list (originally lines 265-327) with:

```dart
    final pluginDestinations = core.pluginManager.homeDestinations;

    final pages = <Widget>[
      HomeDashboardPage(
          key: _homeDashboardKey,
          engine: core.audioEngine,
          pluginManager: core.pluginManager),
      LibraryPage(engine: core.audioEngine, pluginManager: core.pluginManager),
      PlaylistPage(
          key: _playlistKey,
          engine: core.audioEngine,
          pluginManager: core.pluginManager),
      MoodsPage(
        key: _moodsKey,
        engine: core.audioEngine,
        pluginManager: core.pluginManager,
        onPlaybackStarted: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const NowPlayingPage()),
        ),
      ),
      OnlinePage(engine: core.audioEngine, pluginManager: core.pluginManager),
      SettingsPage(
          engine: core.audioEngine,
          pluginManager: core.pluginManager,
          sandbox: core.sandbox,
          layoutManager: locator<LayoutManager>(),
          themeManager: locator<ThemeManager>()),
      for (final d in pluginDestinations) Builder(builder: d.pageBuilder),
    ];

    // Six fixed core destinations, unchanged in identity/order/behavior,
    // plus whatever bundled plugins contribute via homeDestinations() —
    // always appended after core, never interleaved, so every existing
    // literal `_selectedIndex = N` assignment for a *core* destination
    // elsewhere in this file stays correct without needing to change.
    final destinations = [
      HomeDestinationInfo(OmnisIconCatalog.home.resolve(), 'Home'),
      HomeDestinationInfo(OmnisIconCatalog.libraryMusic.resolve(), 'Library'),
      HomeDestinationInfo(OmnisIconCatalog.playlistPlay.resolve(), 'Playlist'),
      HomeDestinationInfo(OmnisIconCatalog.mood.resolve(), 'Moods'),
      HomeDestinationInfo(OmnisIconCatalog.cloudQueue.resolve(), 'Online'),
      HomeDestinationInfo(OmnisIconCatalog.settings.resolve(), 'Settings'),
      for (final d in pluginDestinations)
        HomeDestinationInfo(d.icon, d.label),
    ];

    // A plugin contributing a destination can be disabled/uninstalled
    // mid-session, shrinking this list — clamp before it's used to
    // index into `pages`/`destinations` below, so a stale
    // _selectedIndex from a vanished plugin tab never crashes
    // IndexedStack. Falls back to Home (index 0), not the last valid
    // index, since "the destination you were on disappeared" should
    // read as "back to the start," not "landed on some other tab."
    if (_selectedIndex >= destinations.length) {
      _selectedIndex = 0;
    }
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `cd c:\Users\MrIvo\Github\Omnis && flutter test test/home_page_plugin_destinations_test.dart`
Expected: PASS. If it fails on the bootstrap/fake-platform setup rather
than the actual tab-rendering assertion, fix the test scaffolding using
whatever pattern the existing `HomePage`-testing file (found in Step 2)
uses, then rerun — do not change the Step 5 implementation to work
around a test-setup problem.

- [ ] **Step 7: Add a second test for the clamping behavior**

Append to the same test file:

```dart
  testWidgets(
      'if _selectedIndex points past a shrunk destination list after a '
      'plugin is disabled, HomePage falls back to Home instead of '
      'crashing IndexedStack', (tester) async {
    final core = await ensureCoreReady();
    core.pluginManager.register(_TabContributingPlugin());

    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Extra Tab'));
    await tester.pumpAndSettle();
    expect(find.text('Extra Tab Content'), findsOneWidget);

    // Simulate the plugin disappearing mid-session — this is the exact
    // shrinking-list scenario the clamp in home_page.dart guards.
    core.pluginManager.setEnabled('tab_plugin', false);
    await tester.pumpAndSettle();

    expect(find.text('Extra Tab Content'), findsNothing);
    expect(tester.takeException(), isNull);
  });
```

Use whatever the real disable method is (confirmed in Task 2, Step 1)
if it isn't `setEnabled`.

- [ ] **Step 8: Run the test to verify it passes**

Run: `cd c:\Users\MrIvo\Github\Omnis && flutter test test/home_page_plugin_destinations_test.dart`
Expected: PASS (2 tests), and specifically no exception thrown
(`tester.takeException()` is `null`).

- [ ] **Step 9: Run `flutter analyze`**

Run: `cd c:\Users\MrIvo\Github\Omnis && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 10: Run the full test suite**

Run: `cd c:\Users\MrIvo\Github\Omnis && flutter test`
Expected: all tests pass — in particular, every existing test that
exercises `HomePage`'s six core tabs (tapping Library/Playlist/Moods/
Online/Settings, the command palette's `open_settings`/`customize_home`/
mood/playlist navigation) must still pass unchanged, proving the core
literal indices (0, 2, 3, 5) are genuinely untouched by this change.

- [ ] **Step 11: Manual smoke test**

Run: `cd c:\Users\MrIvo\Github\Omnis && flutter run -d windows` (or
whatever device is available). With no plugin contributing a
destination, confirm the app looks and behaves identically to before
this task (six tabs, same order, same icons). This step has no
automated pass/fail — visually confirm and note it in the task's
completion notes.

- [ ] **Step 12: Commit**

```bash
cd c:\Users\MrIvo\Github\Omnis
git add lib/ui/home_page.dart test/home_page_plugin_destinations_test.dart
git commit -m "$(cat <<'EOF'
Render plugin-contributed destinations after the six core tabs

home_page.dart's destinations/pages lists now append
PluginManager.homeDestinations after the fixed core six, with
_selectedIndex clamped back to Home if a plugin tab disappears
mid-session (disabled/uninstalled) and would otherwise leave the index
pointing past a shrunk IndexedStack. Core destination indices (0, 2,
3, 5, used by _paletteActions/_openCommandPalette) are deliberately
untouched — plugin destinations only ever append, never interleave.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Add `IRadioProvider` and convert `RadioPlugin` to register against it

**Files:**
- Modify: `c:\Users\MrIvo\Github\Omnis\packages\omnis_plugin_api\lib\service_interfaces.dart`
- Modify: `c:\Users\MrIvo\Github\Omnis-Plugins\lib\radio_plugin.dart`
- Test: `c:\Users\MrIvo\Github\Omnis-Plugins\test\radio_plugin_test.dart` (extend the existing file — do not create a new one; run `ls c:\Users\MrIvo\Github\Omnis-Plugins\test\radio_plugin_test.dart` first to confirm it exists, and read it before editing so new tests match its existing style)

**Interfaces:**
- Produces: `abstract class IRadioProvider { Future<List<BaseTrack>> topStations({int limit}); Future<List<BaseTrack>> searchStations(String query, {int limit}); }` in `omnis_plugin_api` — consumed by Task 5.
- Consumes: `RadioPlugin.topStations({int limit = 30})` and `RadioPlugin.searchStations(String query, {int limit = 30})` (existing, confirmed at `Omnis-Plugins/lib/radio_plugin.dart:39,54` — unchanged signatures, just now also declared to satisfy `IRadioProvider`).

- [ ] **Step 1: Read the existing `RadioPlugin` class in full**

Run: `grep -n "class RadioPlugin\|@override\|Future<void> initialize\|Future<void> enable\|Future<void> disable\|Future<void> dispose" c:\Users\MrIvo\Github\Omnis-Plugins\lib\radio_plugin.dart`

Confirm there is currently no `enable()`/`disable()` override (this
plan assumes there isn't, per this session's earlier read — verify
before editing, since if one now exists it needs the registration
logic merged into it rather than a fresh override added).

- [ ] **Step 2: Write the failing test — the new interface exists and `RadioPlugin` implements it**

Read the existing `c:\Users\MrIvo\Github\Omnis-Plugins\test\radio_plugin_test.dart`
in full first — it constructs `RadioPlugin(client: MockClient(...))`
directly (see its `searchStations`/`topStations` groups) and has no
existing fake `PluginContext`, since none of its current tests touch
service registration. Add the fixture and tests below as a new
top-level class plus a new `group('IRadioProvider', () { ... })` inside
`main()`, alongside the file's existing `group('searchStations', ...)`/
`group('topStations', ...)` — do not duplicate those existing groups'
own coverage.

Add these imports to the top of the file, alongside the existing ones:

```dart
import 'package:omnis_plugin_api/plugin_context.dart';
import 'package:omnis_plugin_api/service_interfaces.dart';
import 'package:omnis_plugin_api/service_registry.dart';
```

Add this fixture class before `void main() {` — it mirrors
`favorites_plugin_test.dart`'s `_FakeContext` exactly (same repo, same
established pattern: stub only `services`, `noSuchMethod` throws for
anything else so an accidental untested dependency fails loudly
instead of silently returning null):

```dart
/// Only `services` is stubbed — the only context member RadioPlugin's
/// lifecycle touches, same "stub only what's used" shape
/// favorites_plugin_test.dart's `_FakeContext` already establishes.
class _FakeContext implements PluginContext {
  final ServiceRegistry servicesRegistry = ServiceRegistry();

  @override
  ServiceRegistry get services => servicesRegistry;

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName} not stubbed');
}
```

Add this group inside `main() { ... }`, alongside the file's existing
`group(...)` calls:

```dart
  group('IRadioProvider', () {
    RadioPlugin buildPlugin() => RadioPlugin(
          client: MockClient((req) async => http.Response('[]', 200)),
        );

    test('initialize registers IRadioProvider; dispose unregisters it',
        () async {
      final plugin = buildPlugin();
      final ctx = _FakeContext();
      plugin.attach(ctx);

      expect(ctx.servicesRegistry.has<IRadioProvider>(), isFalse);
      await plugin.initialize();
      expect(ctx.servicesRegistry.has<IRadioProvider>(), isTrue);
      expect(ctx.servicesRegistry.get<IRadioProvider>(), same(plugin));

      await plugin.dispose();
      expect(ctx.servicesRegistry.has<IRadioProvider>(), isFalse);
    });

    test('disable unregisters; enable re-registers', () async {
      final plugin = buildPlugin();
      final ctx = _FakeContext();
      plugin.attach(ctx);

      await plugin.enable();
      expect(ctx.servicesRegistry.has<IRadioProvider>(), isTrue);

      await plugin.disable();
      expect(ctx.servicesRegistry.has<IRadioProvider>(), isFalse);

      await plugin.enable();
      expect(ctx.servicesRegistry.has<IRadioProvider>(), isTrue);
    });
  });
```

`MockClient`/`http.Response` are already imported by this file's
existing `dart:convert`/`package:http`/`package:http/testing.dart`
imports — no new import needed for those.

- [ ] **Step 3: Run the test to verify it fails**

Run: `cd c:\Users\MrIvo\Github\Omnis-Plugins && flutter test test/radio_plugin_test.dart`
Expected: FAIL — `IRadioProvider` doesn't exist yet.

- [ ] **Step 4: Add `IRadioProvider` to `service_interfaces.dart`**

Open `c:\Users\MrIvo\Github\Omnis\packages\omnis_plugin_api\lib\service_interfaces.dart`.
Add near the end of the file, after the existing `IOnlineSearchProvider`
definition:

```dart
/// Browses/searches Internet radio stations. Implemented by
/// `RadioPlugin`. A separate interface from [IOnlineSearchProvider]
/// deliberately — that one is scoped to self-hosted media-server
/// search (Ampache/Koel/OpenSubsonic/Jellyfin/Plex/Emby), all of which
/// share one "search this server's existing catalog" shape with no
/// concept of "top/popular results with no query," which radio
/// stations genuinely have and self-hosted servers don't.
abstract class IRadioProvider {
  /// The most popular stations, with no search query — Internet
  /// Radio's landing-page content. Returns an empty list, never
  /// throws, on any failure (network error, upstream directory down).
  Future<List<BaseTrack>> topStations({int limit = 30});

  /// Searches stations matching [query]. Returns an empty list, never
  /// throws, on any failure.
  Future<List<BaseTrack>> searchStations(String query, {int limit = 30});
}
```

- [ ] **Step 5: Make `RadioPlugin` implement it and register/unregister**

Open `c:\Users\MrIvo\Github\Omnis-Plugins\lib\radio_plugin.dart`. Add
the import:

```dart
import 'package:omnis_plugin_api/service_interfaces.dart';
```

Change the class declaration from `class RadioPlugin extends MusicPlugin`
to:

```dart
class RadioPlugin extends MusicPlugin implements IRadioProvider {
```

Replace the existing `Future<void> initialize() async {}` (confirmed
at line 172) with:

```dart
  @override
  Future<void> initialize() async {
    context?.services.register(IRadioProvider, this);
  }

  @override
  Future<void> enable() async {
    context?.services.register(IRadioProvider, this);
  }

  @override
  Future<void> disable() async {
    context?.services.unregister(IRadioProvider, this);
  }
```

Replace the existing `Future<void> dispose() async {}` (confirmed at
line 184) with:

```dart
  @override
  Future<void> dispose() async {
    context?.services.unregister(IRadioProvider, this);
  }
```

Add `@override` immediately above the existing `topStations` and
`searchStations` method declarations (their bodies/signatures don't
change — they already match `IRadioProvider`'s shape exactly).

- [ ] **Step 6: Run the test to verify it passes**

Run: `cd c:\Users\MrIvo\Github\Omnis-Plugins && flutter test test/radio_plugin_test.dart`
Expected: PASS, including the two new tests and every pre-existing one
in this file (registration changes must not break `topStations`/
`searchStations`' own existing test coverage).

- [ ] **Step 7: Run `flutter analyze` on both repos**

Run: `cd c:\Users\MrIvo\Github\Omnis && flutter analyze`
Run: `cd c:\Users\MrIvo\Github\Omnis-Plugins && flutter analyze`
Expected: `No issues found!` in both.

- [ ] **Step 8: Run the full test suite in both repos**

Run: `cd c:\Users\MrIvo\Github\Omnis && flutter test`
Run: `cd c:\Users\MrIvo\Github\Omnis-Plugins && flutter test`
Expected: all pass in both.

- [ ] **Step 9: Commit in Omnis-Plugins first, then Omnis**

```bash
cd c:\Users\MrIvo\Github\Omnis-Plugins
git add lib/radio_plugin.dart test/radio_plugin_test.dart
git commit -m "$(cat <<'EOF'
Register RadioPlugin as IRadioProvider

The interface half of decoupling radio_page.dart from RadioPlugin by
concrete type (Task 5). Registers on initialize/enable, unregisters on
disable/dispose — the same lifecycle every other ServiceRegistry-backed
plugin already follows.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

```bash
cd c:\Users\MrIvo\Github\Omnis
git add packages/omnis_plugin_api/lib/service_interfaces.dart
git commit -m "$(cat <<'EOF'
Add IRadioProvider

New capability interface: top/search station browsing, implemented by
RadioPlugin (Omnis-Plugins). Lets radio_page.dart (Task 5) look Radio
up by interface instead of bundled<RadioPlugin>(), the same conversion
already proven for Favorites.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Convert `radio_page.dart` to look up `IRadioProvider` instead of `bundled<RadioPlugin>()`

**Files:**
- Modify: `c:\Users\MrIvo\Github\Omnis\lib\ui\radio_page.dart`
- Test: `c:\Users\MrIvo\Github\Omnis\test\radio_page_test.dart` (existing — modify, don't replace)

**Interfaces:**
- Consumes: `IRadioProvider` (Task 4), `PluginManager.services.get<T>()` (existing, already used elsewhere in this file for `IFavoritesProvider` at line 104 — copy that exact pattern).

- [ ] **Step 1: Update the existing test file's plugin registration to also register the interface**

Read `c:\Users\MrIvo\Github\Omnis\test\radio_page_test.dart` in full.
Every place it does `manager.register(RadioPlugin(client: client))`
followed by any assertion that depends on Radio actually being
reachable (station lists rendering, search working) needs the plugin
properly initialized so `IRadioProvider` gets registered — check
whether this file already calls `manager.attachContext(...)` +
`await manager.initializeAll()` (per this session's earlier
`radio_page_test.dart` fix for `FavoritesPlugin` — the same
`_wireContext` helper this file already has, confirmed present from
that earlier work) or only `manager.register(...)` bare. If
`_wireContext` already runs for every test in this file, no test
changes are needed here at all — the interface will already be
registered by the time each test's assertions run. If any test
constructs a `PluginManager`/`RadioPlugin` without going through
`_wireContext`, add that call before proceeding to Step 2.

- [ ] **Step 2: Run the existing radio_page tests to confirm current baseline**

Run: `cd c:\Users\MrIvo\Github\Omnis && flutter test test/radio_page_test.dart`
Expected: PASS (this establishes the pre-change baseline — if anything
already fails here, stop and investigate before proceeding; this task
must not be the one that "fixes" an unrelated pre-existing failure).

- [ ] **Step 3: Replace the first `_plugin` getter (in `_RadioPageState`)**

Open `c:\Users\MrIvo\Github\Omnis\lib\ui\radio_page.dart`. Replace
(confirmed at lines 43-44):

```dart
  RadioPlugin? get _plugin =>
      widget.pluginManager.bundled<RadioPlugin>(onlyEnabled: true);
```

with:

```dart
  IRadioProvider? get _plugin =>
      widget.pluginManager.services.get<IRadioProvider>();
```

- [ ] **Step 4: Replace the second `_plugin` getter (in `RadioBodyState`)**

Replace (confirmed at lines 100-101):

```dart
  RadioPlugin? get _plugin =>
      widget.pluginManager.bundled<RadioPlugin>(onlyEnabled: true);
```

with:

```dart
  IRadioProvider? get _plugin =>
      widget.pluginManager.services.get<IRadioProvider>();
```

- [ ] **Step 5: Update the import**

Find the import of `RadioPlugin`:

Run: `grep -n "^import" c:\Users\MrIvo\Github\Omnis\lib\ui\radio_page.dart`

If `package:omnis_plugins/radio_plugin.dart` is imported only for the
now-removed `RadioPlugin` type references (confirm no other use of
`RadioPlugin`/`CustomRadioStation`-from-that-file remains in this
file — `CustomRadioStation` lives in `custom_radio_station_store.dart`,
a separate import, so check specifically for bare `RadioPlugin` usage),
remove that import line and add:

```dart
import 'package:omnis/plugin_api/service_interfaces.dart';
```

(matching the exact import path this file already uses for
`IFavoritesProvider` at whatever line currently imports it — reuse
that same import if it already exists in this file rather than adding
a duplicate).

- [ ] **Step 6: Run `flutter analyze`**

Run: `cd c:\Users\MrIvo\Github\Omnis && flutter analyze`
Expected: `No issues found!` — this will surface immediately if any
other `RadioPlugin`-typed reference remains in the file that Steps 3-5
missed.

- [ ] **Step 7: Run the radio_page tests**

Run: `cd c:\Users\MrIvo\Github\Omnis && flutter test test/radio_page_test.dart`
Expected: PASS — identical results to the Step 2 baseline. If anything
newly fails, it means a test was relying on `bundled<RadioPlugin>()`
finding the plugin even when disabled-but-registered in a way
`services.get<IRadioProvider>()` doesn't replicate (e.g. a test that
registers `RadioPlugin` but never calls `initializeAll()`/
`attachContext()`, relying on `bundled<T>()`'s looser "found by type
regardless of service registration" behavior) — fix that specific
test's setup per Step 1's guidance, don't revert the production code.

- [ ] **Step 8: Run the full test suite**

Run: `cd c:\Users\MrIvo\Github\Omnis && flutter test`
Expected: all tests pass.

- [ ] **Step 9: Manual smoke test**

Run: `cd c:\Users\MrIvo\Github\Omnis && flutter run -d windows`. Open
the Radio tab, confirm top stations load, search works, and playing a
station works. This step has no automated pass/fail — confirm visually.

- [ ] **Step 10: Commit**

```bash
cd c:\Users\MrIvo\Github\Omnis
git add lib/ui/radio_page.dart test/radio_page_test.dart
git commit -m "$(cat <<'EOF'
Decouple radio_page.dart from RadioPlugin by concrete type

Both _plugin getters (_RadioPageState, RadioBodyState) now look up
IRadioProvider through the ServiceRegistry instead of
bundled<RadioPlugin>(onlyEnabled: true) — the same conversion pattern
already proven for Favorites, now confirmed to generalize to a second,
simpler case with no interface-write-side or persistence complications.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## After This Plan

Tier 0 is complete once all 5 tasks are committed and both repos'
`flutter analyze`/`flutter test` are clean. This unblocks:
- **Tier 1** (5 more concrete-type conversions in `library_page.dart`,
  `online_page.dart`, `playlist_page.dart`) — each follows Task 4/5's
  exact template.
- **Tier 2** (moving whole tabs like Home dashboard and Moods into
  plugins) — depends on Task 3's dynamic destination rendering.

See `docs/superpowers/specs/2026-08-22-core-plugin-rearchitecture-plan.md`
for the full remaining task list. Write Tier 1's plan as a separate
document once Tier 0 is verified working end-to-end, rather than
planning it blind before Task 1-5's real implementation experience is
in hand.
