# Device Adaptivity, Accessibility, Permissions & Visual Polish — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Harden Omnis's two shipping platforms (Android, Windows) to be
genuinely device-adaptive rather than assuming one input model everywhere:
hide keyboard/swipe UI that doesn't apply to a platform's typical input
model, fix a real currently-shipping bug where "orientation" is conflated
with "wide window" (forcing phone/car-mount behavior onto every normal
desktop window), close a real accessibility gap (drag-only reordering with
no keyboard path; a tap-target-shrinking hack that drops below Flutter's
48dp minimum), batch permission requests at first run instead of asking
lazily forever, and land the approved Tier 1 visual-polish fixes from the
design audit.

**Architecture:** One new capability layer (`PlatformCapabilities`), a
handful of bug fixes in code the two audits underlying this plan already
pinpointed by file:line, one new onboarding screen, and a batch of small,
independent visual fixes. No new platform folders, no new state-management
pattern — every task follows an existing convention already in this
codebase (see each task's own "Interfaces" section for which one).

**Tech Stack:** Flutter/Dart, `AppSettings` (existing `SharedPreferences`-
backed settings singleton), `permission_handler`, the existing
`PluginManager`/`PluginContext` plugin-capability system.

**Spec:** `docs/superpowers/specs/2026-08-23-platform-capabilities-and-permissions.md`

## Global Constraints

- `PlatformCapabilities` (Task 1) is a static, side-effect-free class —
  no `InheritedWidget`, no `ChangeNotifier`. Every other task consumes it
  as a plain static read, the same way `AppSettings.instance` is read
  elsewhere in this codebase.
- A capability check answers "does this platform's typical input model
  support X" — never re-derive a local `Platform.isX`/`kIsWeb` check for a
  UI-adaptivity decision once `PlatformCapabilities` exists. A check that
  answers "does this OS API exist at all" (hardware EQ being Android-only,
  Windows SMTC integration) is not a UI-adaptivity decision and stays a
  direct `Platform.isX` check — do not migrate those.
- "Fully hidden," not "defaulted off," for platform-inapplicable UI (the
  project owner's explicit choice): the widget/settings entry does not
  render at all, not merely default to an off state a user could still
  reach.
- Direct-manipulation drag (waveform scrub, drag-to-place in the layout
  editor, `Dismissible` swipe-to-delete) is never gated by this plan — a
  desktop mouse drags too. Only swipe-as-a-shortcut-for-a-button
  (skip-track swipe, nav-reveal swipe) and hardware-keyboard-only features
  are in scope for hiding.
- After every task: `flutter analyze` and `flutter test` must both pass
  clean in `Omnis` (this plan touches only the Omnis app repo — no
  Omnis-Plugins changes anywhere in this plan).
- This plan executes directly on `main`, no isolated worktree — same
  established consent as the two prior plans this session.
- Several tasks touch the same shared files (`now_playing_page.dart`,
  `player_widgets.dart`, `home_page.dart`) — dispatch strictly in the
  order below regardless of which tasks look independent on paper, the
  same "same file, sequence serially" discipline the Tier 1 plan used.

---

### Task 1: `PlatformCapabilities` service + platform-check consolidation

**Files:**
- Create: `lib/core/platform_capabilities.dart`
- Create: `lib/core/file_export_io.dart`
- Modify: `lib/core/output_device_controller.dart:134,138,168`
- Modify: `lib/ui/playlist_page.dart:181,204,227,253,276`
- Modify: `lib/ui/settings/backup_settings_page.dart:56`
- Test: `test/platform_capabilities_test.dart` (new)
- Test: `test/file_export_io_test.dart` (new)

**Interfaces:**
- Produces: `PlatformCapabilities.isTouchPrimary`, `.isDesktopPrimary`,
  `.isRotatable`, `.supportsRightClick`, `.supportsOutputDeviceSelection`
  — every later task in this plan consumes one or more of these.
- Produces: `FileExportIo.requiresManualWrite` — a single bool every
  `playlist_page.dart`/`backup_settings_page.dart` call site reads instead
  of re-deriving its own check.

- [ ] **Step 1: Create `PlatformCapabilities`**

```dart
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

/// Static, build-time-fixed platform-class flags — never re-evaluated
/// mid-session, since Flutter has no reliable signal for a capability
/// changing at runtime (a keyboard attached to a running Android device,
/// a touchscreen enabled on Windows) without platform-channel work this
/// class deliberately doesn't attempt. Consumed like `AppSettings.instance`
/// elsewhere in this codebase: a plain static read, never an
/// `InheritedWidget`/`ChangeNotifier` — nothing here changes mid-session.
///
/// Every flag answers "does this platform's *typical* input model support
/// X" — not a per-device hardware inventory. An Android tablet with a
/// keyboard case, or a Windows touch-laptop, is a real exception none of
/// these flags detect; that's an accepted trade-off for this pass's scope,
/// not an oversight (see the design spec's "Two platform classes, not a
/// device inventory" note).
class PlatformCapabilities {
  const PlatformCapabilities._();

  /// Android or iOS: touch is the primary input model, no hardware
  /// keyboard is normally attached.
  static bool get isTouchPrimary =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Windows, macOS, or Linux: keyboard+mouse is the primary input model,
  /// no touchscreen is normally present.
  static bool get isDesktopPrimary =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  /// Whether this platform's `Orientation` (derived from window
  /// width-vs-height, not a physical sensor) reflects an actual device
  /// rotation. `false` on desktop platforms, where a window simply being
  /// wider than tall is not "the device rotated to landscape" — the exact
  /// conflation that made the bottom-nav auto-hide and forced-Landscape
  /// Now Playing layout fire on every normal-shaped Windows window by
  /// default (see Task 2). `true` on touch-primary platforms, where
  /// `Orientation` genuinely does reflect a physical rotation.
  static bool get isRotatable => isTouchPrimary;

  /// Whether right-click is a natural alternative to long-press/touch
  /// gestures on this platform. Same value as [isDesktopPrimary] today —
  /// a separate named flag because the *reason* a call site checks this
  /// (offering a right-click context-menu alternative to a touch-only
  /// gesture) is conceptually distinct from "is this a desktop platform,"
  /// even though the two happen to coincide for every platform Omnis
  /// ships today.
  static bool get supportsRightClick => isDesktopPrimary;

  /// Whether the platform exposes a real "choose this specific output
  /// device" API — a genuine OS-capability fact (Android's
  /// `AudioDeviceInfo`/`AndroidAudioManager` surface), not an
  /// input-model/UI-adaptivity decision, but named here for discoverability
  /// alongside every other capability flag in this class. See
  /// `output_device_controller.dart` for the one real implementation this
  /// backs.
  static bool get supportsOutputDeviceSelection =>
      !kIsWeb && Platform.isAndroid;
}
```

- [ ] **Step 2: Migrate `output_device_controller.dart`'s naming**

Read `lib/core/output_device_controller.dart` in full first. Replace the
body of `bool get supportsDeviceSelection => Platform.isAndroid;` (line
134) with `bool get supportsDeviceSelection =>
PlatformCapabilities.supportsOutputDeviceSelection;`, and replace the two
`if (!Platform.isAndroid)` guards at lines 138 and 168 with
`if (!PlatformCapabilities.supportsOutputDeviceSelection)`. Add
`import 'package:omnis/core/platform_capabilities.dart';` at the top. This
is a pure rename — the underlying behavior (Android-only) is unchanged,
only the check now reads from the new shared class instead of a raw
`Platform.isAndroid` at this call site.

- [ ] **Step 3: Create `FileExportIo`**

`file_picker`'s `saveFile` already writes bytes to disk on Android/iOS,
but only returns a path the caller must write itself on desktop — six
call sites across two files re-derive `!kIsWeb && !Platform.isAndroid &&
!Platform.isIOS` to decide this. This is a `file_picker`-plugin-contract
fact, not a UI-adaptivity signal, so it does not belong on
`PlatformCapabilities` — it gets its own narrow file:

```dart
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

/// Whether the current platform's `file_picker.saveFile` call returns a
/// path the caller must write the bytes to itself (desktop), as opposed
/// to already having written them (Android/iOS, where `saveFile` takes
/// the bytes directly and the OS handles the write). A `file_picker`
/// plugin-contract fact — not a UI-adaptivity decision — so it lives here
/// rather than on `PlatformCapabilities`.
class FileExportIo {
  const FileExportIo._();

  static bool get requiresManualWrite =>
      !kIsWeb && !Platform.isAndroid && !Platform.isIOS;
}
```

- [ ] **Step 4: Convert the 6 call sites**

Read `lib/ui/playlist_page.dart` lines 175-290 and
`lib/ui/settings/backup_settings_page.dart` lines 45-70 in full first —
confirm each of the 6 `if (!kIsWeb && !Platform.isAndroid &&
!Platform.isIOS) { ... }` blocks does the same kind of thing (writes
bytes to the picked path manually) before converting. Replace each
condition with `if (FileExportIo.requiresManualWrite) { ... }`, adding
`import 'package:omnis/core/file_export_io.dart';` to both files. If any
of the 6 sites turns out to do something other than the manual-write
pattern once you read it, do not force it onto this helper — note the
deviation in your report instead.

- [ ] **Step 5: Tests**

`test/platform_capabilities_test.dart`: since every flag is a pure
function of `Platform.isX`/`kIsWeb` with no branching logic to unit-test
in isolation from the real platform the test runs on, write tests that
assert the *relationships* between flags hold regardless of which
platform CI runs on: `isTouchPrimary` and `isDesktopPrimary` are never
both `true`; `isRotatable == isTouchPrimary`; `supportsRightClick ==
isDesktopPrimary`. This is the same "assert the invariant, not a specific
platform's expected value" approach needed since this test suite runs on
whatever CI machine it's given.

`test/file_export_io_test.dart`: same approach —
`FileExportIo.requiresManualWrite` should be the logical negation of
`PlatformCapabilities.isTouchPrimary` for every platform Omnis ships
today (Android/iOS are touch-primary and don't require manual write;
Windows/macOS/Linux are desktop-primary and do) — assert that
relationship rather than a hardcoded expected boolean.

- [ ] **Step 6: Verify and commit**

Run `flutter analyze` and `flutter test`. Commit.

---

### Task 2: Fix the orientation/wide-window conflation bug (Critical)

**Files:**
- Modify: `lib/ui/home_page.dart:389-398`
- Modify: `lib/ui/now_playing_page.dart:318-336`
- Test: `test/home_page_plugin_destinations_test.dart` (add a case) or a
  new `test/home_page_autohide_test.dart` if the existing file's fixture
  setup doesn't fit — read the existing file first to decide
- Test: `test/now_playing_page_test.dart` (add a case — read the existing
  file first to find its widget-construction pattern)

**Interfaces:**
- Consumes: `PlatformCapabilities.isRotatable` (Task 1).

**The bug**: both call sites compute `MediaQuery.orientationOf(context)
== Orientation.landscape` and treat that as "the device physically
rotated." On desktop, `Orientation` is derived purely from window
width-vs-height — so a normally-proportioned (wider-than-tall) Windows
window reports `Orientation.landscape` essentially always. With both
`AppSettings.bottomNavAutoHide` (`app_settings.dart:528`) and
`AppSettings.autoLandscapeLayout` (`app_settings.dart:381-382`) defaulting
to `true`, this means, out of the box, with zero user action: the
persistent mini-player/nav bar auto-hides on every normal Windows window
(a phone/car-mount behavior), and Now Playing silently force-substitutes
the `Landscape` layout for Standard/Top Controls on every normal Windows
window too — which has its own real overflow risk fixed in Task 3.

- [ ] **Step 1: Fix `home_page.dart`**

Read the surrounding method in full first (currently around lines
344-398). Change:

```dart
final isLandscape =
    MediaQuery.orientationOf(context) == Orientation.landscape;
```

to:

```dart
final isLandscape = PlatformCapabilities.isRotatable &&
    MediaQuery.orientationOf(context) == Orientation.landscape;
```

Add `import 'package:omnis/core/platform_capabilities.dart';` to the top
of the file if not already present (check first). The rest of
`autoHideActive`'s computation (`settings.bottomNavAutoHide &&
(isLandscape || isCarMode)`) is unchanged — Car Mode's own auto-hide
behavior (a real, deliberate car-mount feature, not orientation-derived)
is untouched by this fix.

- [ ] **Step 2: Fix `now_playing_page.dart`**

Read `_resolveActiveLayout` in full first (currently lines 318-336).
Apply the identical guard:

```dart
final isLandscape = PlatformCapabilities.isRotatable &&
    MediaQuery.orientationOf(context) == Orientation.landscape;
```

Add the same import if not already present. The rest of the method
(checking `settings.autoLandscapeLayout` and `portraitOriented.contains
(selected.id)`) is unchanged.

- [ ] **Step 3: Tests**

Add a widget test asserting that on a wide-but-not-rotated build (which
is what every test harness already runs under, since
`PlatformCapabilities.isRotatable` is `false` on the `flutter test` host
platform), `autoHideActive` stays `false` and the resolved Now Playing
layout stays whatever the user's `playerLayoutId` setting says — i.e.,
the wide test-viewport default does NOT trigger the old
orientation-derived behavior any more. Read whichever of the two
candidate test files fits best (`home_page_plugin_destinations_test.dart`
already has real `HomePage`-bootstrapping infrastructure from the Tier 0
plan; `now_playing_page_test.dart` if one already exists with a working
`NowPlayingPage` construction pattern — check both before deciding which
to extend vs. create fresh).

- [ ] **Step 4: Verify and commit**

Run `flutter analyze` and `flutter test`. Commit.

---

### Task 3: Fix Landscape/Car Mode layout overflow risk

**Files:**
- Modify: `lib/ui/player_layouts/landscape_layout.dart`
- Modify: `lib/ui/player_layouts/car_mode_layout.dart`
- Test: whichever test file(s) already cover these two layouts — grep
  `grep -rln "LandscapeLayout\|CarModeLayout" test/` first; extend if one
  exists, create `test/landscape_layout_overflow_test.dart` /
  `test/car_mode_layout_overflow_test.dart` if none do

**Interfaces:** None new — this is a layout-robustness fix, no new
capability consumed.

**The bug**: `landscape_layout.dart:26-55` places a fixed-size
`PlayerAlbumArt(data: data, size: 160, ...)` as a direct child of a `Row`
inside an `Expanded` — only the neighboring text/lyrics column is wrapped
in a `SingleChildScrollView` (line 38), not the art itself. A `Row`
imposes no minimum-height constraint on its children, so if the available
height in the parent `Expanded` drops below roughly 160px + padding
(plausible on a short, freeform-resized Windows window — exactly the
scenario Task 2 makes reachable by default), the fixed-size art overflows
rather than shrinking or scrolling. `car_mode_layout.dart` has the
equivalent shape: a fixed `Container(width: 120)` rail (line 32) plus a
fixed `PlayerAlbumArt(size: 140)` (line 72), both direct `Row` children
with no scroll guard.

- [ ] **Step 1: Fix `landscape_layout.dart`**

Read the full file first. Wrap the `PlayerAlbumArt` in a widget that lets
it shrink rather than overflow when the available height is tight — the
simplest fix consistent with this layout's existing "side-by-side, no
scroll on the art side" design intent is a `ConstrainedBox`/`AspectRatio`
combination that caps the art's height to whatever the `Expanded`
actually has available, computed via a `LayoutBuilder` wrapping the whole
`Row`:

```dart
  @override
  Widget build(BuildContext context, PlayerLayoutData data) {
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Cap album art to whatever height is actually available
                // (minus a little breathing room) instead of a fixed 160
                // that can overflow a short, freeform-resized desktop
                // window — the exact scenario now reachable whenever
                // AppSettings.autoLandscapeLayout substitutes this layout
                // in on a wide-but-short window (see PlatformCapabilities
                // .isRotatable's own doc comment for why "wide" no longer
                // means "physically rotated" on desktop).
                final artSize =
                    (constraints.maxHeight - 16).clamp(80.0, 160.0);
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    PlayerAlbumArt(
                        data: data, size: artSize, iconSize: artSize * 0.45),
                    const SizedBox(width: 24),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            PluginSlotView(
                              pluginManager: data.pluginManager,
                              locationId: 'now_playing_overlay',
                            ),
                            PlayerTrackInfo(data: data, align: TextAlign.left),
                            const SizedBox(height: 12),
                            if (data.settings.showLyrics)
                              PlayerLyricsPanel(data: data),
                            const SizedBox(height: 12),
                            PlayerProgressBar(data: data),
                            PlayerCrossfadeStatus(data: data),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        // ... whatever follows the Expanded in the original file (the
        // bottom control bar) — read the current file to reproduce it
        // unchanged; this step only touches the Expanded's child.
      ],
    );
  }
```

Read the rest of the original file (whatever follows this `Expanded` in
the `Column` — the bottom transport bar, per the file's own class doc
"controls pinned to the bottom bar") and keep it exactly as-is; only the
`Expanded`'s child changes.

- [ ] **Step 2: Fix `car_mode_layout.dart`**

Read the full file first. Apply the identical `LayoutBuilder`-driven
height-clamping pattern to its own fixed-size `Container(width: 120)`
rail and `PlayerAlbumArt(size: 140)` — clamp both to the available height
the same way, keeping the rest of the layout's structure (whatever the
120px-wide rail actually contains — read the file to find out) unchanged.

- [ ] **Step 3: Tests**

For each layout, add a widget test that renders it inside a `SizedBox`
with a deliberately short height (e.g. 100px tall, wide enough that only
height is the constraint) and asserts no overflow error is thrown
(`tester.takeException()` returns `null`) — this is the direct
regression test for the bug this task fixes, and it would have failed
against the pre-fix code (verify this by temporarily reverting your fix
locally and confirming the test does fail, then reinstating the fix,
mirroring the discipline this session's earlier plans used for
regression-test verification).

- [ ] **Step 4: Verify and commit**

Run `flutter analyze` and `flutter test`. Commit.

---

### Task 4: `PlayerControlsRow` — replace the tap-target-shrinking hack with a real hierarchy

**Files:**
- Modify: `lib/ui/player_layouts/player_widgets.dart:317-428`
  (`PlayerControlsRow`)
- Test: whichever test file already covers `PlayerControlsRow` — grep
  `grep -rln "PlayerControlsRow" test/` first

**Interfaces:** None new.

**The problem**: `PlayerControlsRow`'s button row is wrapped in
`FittedBox(fit: BoxFit.scaleDown)` (line 364) specifically because the
full six-button set overflows by a few pixels on a ~360dp-wide phone —
`scaleDown` hides the overflow but uniformly shrinks every button below
Flutter's 48dp minimum touch-target size on exactly the narrow screens
where it activates. This is a real accessibility defect, not just a
visual inconsistency — flagged as documented, previously
explicitly-deferred technical debt (see the removed comment this task
replaces).

- [ ] **Step 1: Read the whole class first**

Read `lib/ui/player_layouts/player_widgets.dart`'s `PlayerControlsRow`
class in full (it's larger than the button-row method alone — find
`iconSize`, `playSize`, `shuffleRepeatSize`, `compact`, and the
`ButtonLayout` enum it switches on, all referenced by the row this task
rewrites) before changing anything, since the replacement must preserve
every existing parameter this widget already takes.

- [ ] **Step 2: Replace `FittedBox(scaleDown)` with `LayoutBuilder`-driven proportional sizing**

Follow the exact pattern `lib/ui/player_layouts/tv_mode_layout.dart:90-111`
already establishes and documents (read that method first) — compute
each button's size as a function of `constraints.maxWidth` inside a
`LayoutBuilder`, giving Play/Pause a deliberately larger, fixed-minimum
size and the secondary buttons (previous/next/seek/play-mode) a smaller,
proportionally-shrinking size that never drops below 48dp regardless of
how narrow the available width gets — reflowing (secondary buttons
shrink toward, but never below, 48dp; if that's still not enough to fit
every button in `ButtonLayout.standard`'s 6-button set at the narrowest
phone width this app supports, move the least-essential buttons — the
play-mode cycle button is the best candidate, since it already only
appears in `ButtonLayout.standard`) into an overflow affordance (a
`PopupMenuButton` folding play-mode into a menu) rather than continuing
to shrink below the accessibility floor. Preserve every existing behavior
this row has: the `AnimatedIcon` play/pause morph, the buffering spinner
substitution, the `Semantics`/tooltip labels on every button, and all
three `ButtonLayout` variants (`standard`/`minimal`/whatever the third is
— read the enum). Remove the class-doc comment explaining why
`FittedBox(scaleDown)` was used, since it's no longer accurate once this
step lands — write a new comment explaining the actual sizing approach
instead.

- [ ] **Step 3: Tests**

Add or extend a widget test rendering `PlayerControlsRow` inside a
360dp-wide constraint (the width the original overflow was measured
against, per the removed comment) and asserting: no overflow exception,
and every rendered `IconButton`'s effective tap target is at least 48×48
logical pixels (check via `tester.getSize` on each button's `RenderBox`,
comparing against `kMinInteractiveDimension` from
`package:flutter/material.dart`). This is the direct regression test for
the accessibility floor this task restores.

- [ ] **Step 4: Verify and commit**

Run `flutter analyze` and `flutter test`. Commit.

---

### Task 5: Hide keyboard-shortcuts UI on touch-primary; hide swipe-as-shortcut UI on desktop-primary

**Files:**
- Modify: `lib/ui/global_keyboard_shortcuts.dart`
- Modify: `lib/ui/settings/keyboard_settings_page.dart` (or wherever it's
  linked from — check `lib/ui/settings_page.dart`'s settings list)
- Modify: `lib/ui/settings/controls_settings_page.dart:70-105`
- Modify: `lib/ui/now_playing_page.dart` (`_wrapWithGestureMode`, and
  `_resolveActiveLayout`'s neighbor code — read the file to find the
  exact current line numbers, since Tasks 2's edits shift them)
- Modify: `lib/ui/player_layouts/full_art_gestures_layout.dart:50-62`
- Modify: `lib/ui/player_layouts/karaoke_gestures_layout.dart` (read the
  file first — same `onHorizontalDragEnd` pattern per the design spec)
- Modify: `lib/ui/home_page.dart` (nav-reveal `onVerticalDragEnd` — read
  the file to find current line numbers post-Task-2)

**Interfaces:**
- Consumes: `PlatformCapabilities.isTouchPrimary`,
  `PlatformCapabilities.isDesktopPrimary` (Task 1).

**On `isTouchPrimary` (Android/iOS): hide keyboard shortcuts entirely**

- [ ] **Step 1: Hide the Keyboard Shortcuts settings entry**

Find where the Keyboard Shortcuts settings page is linked from (grep
`grep -n "KeyboardSettingsPage" lib/ui/settings_page.dart` or wherever the
settings list lives) and wrap that list entry in
`if (!PlatformCapabilities.isTouchPrimary) ...[ ... ]` (a collection-if,
matching this codebase's existing pattern for conditional list entries —
see `home_page.dart`'s `for (final d in pluginDestinations) ...` as a
style reference) so it doesn't render at all on touch-primary platforms.

- [ ] **Step 2: Remove `GlobalKeyboardShortcuts`'s non-media-key wiring on touch-primary**

Read `lib/ui/global_keyboard_shortcuts.dart` in full. The class wraps
`HomePage`'s `Scaffold` in a `CallbackShortcuts`/`Focus` combination for
every binding (play/pause, next/previous, seek, volume, mute) plus always-
on hardware media-key handling (`LogicalKeyboardKey.mediaPlayPause` etc.,
currently lines 201-205) that must keep working on touch-primary
platforms too — some Android devices route real hardware media-key events
(Bluetooth headset controls, wired headset buttons) through exactly this
path. Restructure so the settings-driven keyboard-shortcut bindings
(`_enabled`-gated) are skipped when `PlatformCapabilities.isTouchPrimary`,
while the hardware media-key `LogicalKeyboardKey` bindings remain wired
regardless of platform. The cleanest split, given this class's own
documented focus-anchor complexity (its class doc explains three
real edge cases it already solves — read them before restructuring, don't
break what they fixed): keep the single `CallbackShortcuts` widget always
present (removing it entirely would also remove the media-key bindings),
but make the settings-driven binding entries in its `bindings` map
conditional on `!PlatformCapabilities.isTouchPrimary`, while the hardware
media-key entries stay unconditional.

**On `isDesktopPrimary` (Windows/macOS/Linux): hide swipe-as-a-shortcut**

- [ ] **Step 3: Hide the `GestureMode` dropdown and swipe-gestures toggle**

Read `lib/ui/settings/controls_settings_page.dart` lines 70-105 in full.
Wrap the `GestureMode` `DropdownButton` (currently lines 77-90) and the
`allowSwipeGestures` `SwitchListTile` (currently around line 101) in
`if (!PlatformCapabilities.isDesktopPrimary) ...[ ... ]`, same
collection-if pattern as Step 1.

- [ ] **Step 4: Make `_wrapWithGestureMode` a no-op on desktop-primary**

In `now_playing_page.dart`, find `_wrapWithGestureMode` (read the current
file — Task 2 may have shifted its line number). It already has an
early-return for `!settings.allowSwipeGestures`; add an equivalent
early-return for `PlatformCapabilities.isDesktopPrimary` (checked first,
before reading `settings.allowSwipeGestures`, since the setting itself is
now hidden on desktop per Step 3 and its persisted value shouldn't matter
there).

- [ ] **Step 5: Remove `onHorizontalDragEnd` from the two gesture-only layouts on desktop-primary**

In `full_art_gestures_layout.dart` (currently lines 50-62) and
`karaoke_gestures_layout.dart` (read the file first to find its
equivalent `GestureDetector`), make the `onHorizontalDragEnd` handler
conditional: pass `null` for it when
`PlatformCapabilities.isDesktopPrimary` is true (a `GestureDetector`
accepts `null` for any handler it isn't using), keeping `onTap` always
active (a mouse click is a real tap). Do not touch the `Semantics`/
`customSemanticsActions` block above either `GestureDetector` — those
must keep providing the Next/Previous screen-reader actions regardless of
platform, since a screen-reader user's access to those actions doesn't
depend on whether swipe gestures are hidden from sighted desktop users.

- [ ] **Step 6: Make the home-nav auto-hide-on-landscape reveal gesture unreachable by construction on desktop-primary**

In `home_page.dart`, the `autoHideActive` computation already gates on
`isLandscape` (fixed in Task 2 to require `PlatformCapabilities
.isRotatable`) `|| isCarMode`. Since `isRotatable` is already `false` on
`isDesktopPrimary` platforms per Task 1's definition, `autoHideActive`
can only become `true` on desktop via `isCarMode` — Car Mode is itself a
deliberately-selected player layout a desktop user could still pick, so
leave that path alone; this step requires no additional code change
beyond confirming (during Task 2/this task's own testing) that the
drag-reveal gesture is genuinely unreachable except via Car Mode on
desktop, and noting that confirmation in your report rather than adding a
redundant guard.

- [ ] **Step 7: Tests**

Add test coverage (extend existing test files for
`global_keyboard_shortcuts.dart`, `controls_settings_page.dart`,
`full_art_gestures_layout.dart`, `karaoke_gestures_layout.dart` — grep for
each to find them) asserting: the Keyboard Shortcuts settings entry does
not render, and `GlobalKeyboardShortcuts`'s settings-driven bindings don't
fire but hardware media keys still do — this specific combination is hard
to assert directly against the real `Platform.isX` the test host runs on
without a seam to fake it; if `PlatformCapabilities` has no way to be
overridden for a test, add the narrowest possible test seam (e.g. a
`@visibleForTesting` static setter that resets after each test) rather
than leaving this behavior untested — check whether `AppSettings` or any
other static-singleton-style class in this codebase already established a
test-override convention you should match before inventing a new one.

- [ ] **Step 8: Verify and commit**

Run `flutter analyze` and `flutter test`. Commit.

---

### Task 6: Desktop input parity — keyboard-accessible reorder fallback + right-click alternative to long-press

**Files:**
- Modify: `lib/ui/playlist_page.dart:1339,1518` (two
  `ReorderableListView.builder` sites)
- Modify: `lib/ui/home_dashboard_page.dart:368` (one `ReorderableListView`)
- Modify: `lib/ui/widgets/global_sidebar_drawer.dart:245` (one
  `ReorderableListView`)
- Modify: `lib/ui/widgets/queue_panel.dart:157` (one
  `ReorderableListView.builder`)
- Modify: `lib/ui/library_page.dart:2763,3106` (long-press-only
  multi-select entry points)
- Test: whichever test files already cover each of the above 6 call
  sites — grep for each file's existing test coverage first

**Interfaces:**
- Consumes: `PlatformCapabilities.supportsRightClick` (Task 1).

**The gap**: every reorderable list in the app relies entirely on
pointer-drag to reorder, with no keyboard-reachable alternative for a
sighted keyboard-only desktop user (Flutter's built-in
`CustomSemanticsAction` "Move up"/"Move down" only helps a screen-reader
user). Multi-select on grid tiles and track rows is entered via
`onLongPress` alone, with no `onSecondaryTap` (right-click) equivalent —
foreign to how a desktop user expects to select an item.

- [ ] **Step 1: Add a per-row overflow menu with Move Up/Move Down to each of the 4 reorderable lists**

Read each of the 4 files at the cited line first — they're not identical
in structure (some use `ReorderableListView`, some `.builder`; row
widgets differ). For each, add a trailing `PopupMenuButton` (or, if a
`PopupMenuButton`/overflow menu already exists on that row for other
actions, add "Move up"/"Move down" `PopupMenuItem`s to the existing one
rather than adding a second menu button) that calls the same reorder
callback the `ReorderableListView`'s own `onReorder` already uses, with
`oldIndex`/`newIndex` computed as "this item's current index" and
"current index ± 1" (clamped so "Move up" is absent/disabled on the first
item and "Move down" is absent/disabled on the last). Gate the menu
item's visibility on nothing platform-specific — a keyboard-reachable
reorder alternative is a genuine accessibility improvement worth having
on every platform, not just desktop (a touch user with limited dexterity
benefits too); do not hide it behind `PlatformCapabilities
.isDesktopPrimary`, since narrowing it to desktop-only would leave the
exact class of user this fixes (anyone who can't reliably long-press-drag)
unhelped on touch platforms.

- [ ] **Step 2: Add a right-click alternative to the two long-press multi-select entries**

In `library_page.dart`, read the surrounding widget for both cited lines
(`2763`, grid tile; `3106`, track row) in full. Add
`onSecondaryTap: PlatformCapabilities.supportsRightClick ?
() => _toggleSelectedGroup(section.tracks) : null` (grid tile, matching
whatever the real existing `onLongPress` calls) and the equivalent for
the track row's `_toggleSelected(track.id)`, gated on
`PlatformCapabilities.supportsRightClick` this time (unlike Step 1, this
one *should* be platform-gated — right-click is specifically a
desktop-input-parity feature, not a general accessibility improvement the
way a menu-based reorder fallback is, since a touch device has no concept
of "right-click" to parity with).

- [ ] **Step 3: Tests**

For Step 1: add a test per modified file confirming the new "Move
up"/"Move down" menu action calls the same reorder path a real drag
would (assert the resulting list order matches what dragging would have
produced), and that "Move up" is disabled/absent on the first item and
"Move down" on the last. For Step 2: add a test confirming
`onSecondaryTap` triggers the same selection-entry state a long-press
does — using whatever test-override seam Task 5 established for
`PlatformCapabilities` (or the same convention, if Task 5 already landed
one) to exercise the `supportsRightClick`-true path deterministically
regardless of the test host's real platform.

- [ ] **Step 4: Verify and commit**

Run `flutter analyze` and `flutter test`. Commit.

---

### Task 7: Width-responsive grid columns and dialog sizing

**Files:**
- Modify: `lib/ui/home_page.dart:833-844` (Moods grid)
- Modify: `lib/ui/tag_editor_dialog.dart:237-239`
- Modify: `lib/ui/calculated_tag_dialog.dart:76`
- Modify: `lib/ui/tag_find_replace_dialog.dart:68`
- Test: extend whichever test files already cover each of these 4 files

**Interfaces:** None new — pure `LayoutBuilder`/`MediaQuery`-driven
responsiveness, no capability flag needed (this is about available
width, not platform class).

- [ ] **Step 1: Make the Moods grid's column count width-aware**

Read `lib/ui/home_page.dart` around lines 825-845 in full. Replace the
hardcoded `crossAxisCount: 2` in the `SliverGridDelegateWithFixedCrossAxisCount`
with a value computed from available width — wrap the `GridView.builder`
in a `LayoutBuilder` and compute
`crossAxisCount = (constraints.maxWidth / 200).floor().clamp(2, 5)` (a
~200dp target tile width, floor-divided, clamped so it never drops below
today's 2-column minimum or grows unreasonably wide on a very large
desktop window — 200 is a starting point; adjust if the existing
`childAspectRatio: 0.95` tiles look cramped or too sparse at that width
during manual testing, and note in your report if you changed it).
Preserve the existing `mainAxisSpacing`/`crossAxisSpacing`/
`childAspectRatio` values unless the column-count change requires
adjusting `childAspectRatio` to keep tiles from looking stretched — check
visually (or via a widget test asserting rendered tile aspect ratio stays
close to the original) before deciding.

- [ ] **Step 2: Make the three fixed-width dialogs width-aware**

Read all three files at their cited lines. Each currently hardcodes a
`SizedBox(width: 420/480, ...)` inside its dialog content. Replace each
with a width derived from the actual screen size, capped at the existing
value as a maximum rather than a fixed value: e.g.
`width: MediaQuery.sizeOf(context).width.clamp(280, 480)` (480 as the
existing desktop-sized ceiling, 280 as a floor that still fits a narrow
phone without the dialog's own inset padding fighting it — verify this
floor doesn't itself cause internal overflow in each dialog's content by
running its existing widget tests at a narrow viewport). Apply the same
pattern to all three files, adjusting each one's specific width/height
constants to the same clamp shape rather than inventing three different
approaches.

- [ ] **Step 3: Tests**

For the Moods grid: a widget test rendering at 3-4 different viewport
widths (a phone width, a tablet width, a wide desktop width) asserting
the computed `crossAxisCount` increases as width increases and never
drops below 2. For the three dialogs: a widget test per dialog confirming
no overflow at both a narrow (phone) and wide (desktop) viewport, where
today's fixed-width version would either look wrong (desktop, using only
480 of e.g. 1600 available px) or already degrade acceptably (phone, via
`AlertDialog`'s own inset clamping) — the new tests should confirm the
computed width scales rather than staying pinned to the old default at
every viewport size.

- [ ] **Step 4: Verify and commit**

Run `flutter analyze` and `flutter test`. Commit.

---

### Task 8: Fix text-scale overflow risk in the mini-player bar and Home Dashboard cards

**Files:**
- Modify: `lib/ui/widgets/mini_player_bar.dart:110-173`
- Modify: `lib/ui/home_dashboard_page.dart:246-258` and its `_HomeCard`
  widget (read the file to find `_HomeCard`'s own definition)
- Test: extend existing test coverage for both — grep first

**Interfaces:** None new.

**The risk**: both widgets fix a container height (`mini_player_bar.dart`'s
`SizedBox(height: 56)`; `home_dashboard_page.dart`'s `SizedBox(height: 190)`
per-section row) around text that grows with `AppSettings.textScaleFactor`
(clamped to `[0.85, 1.5]`). At the clamp's maximum, two lines of scaled
text plus their line-height are likely to exceed each fixed envelope —
the mini-player bar is *always visible*, making it the single
highest-visibility instance of this risk in the app.

- [ ] **Step 1: Fix `mini_player_bar.dart`**

Read the full file first. Replace the fixed `SizedBox(height: 56, ...)`
(currently wrapping the title/artist/queue-button/play-button row) with
one that grows with content instead of clipping it — remove the fixed
height and let the `Row`'s natural height (driven by the `Column` of two
`Text` widgets) determine the bar's height, adding a `ConstrainedBox` with
`minHeight: 56` instead of a fixed height so the bar never gets *shorter*
than today's default at 1.0× scale, but can grow at larger scale factors
without clipping. Confirm the `LinearProgressIndicator` beneath it (part
of the same `Column`, `mainAxisSize: MainAxisSize.min`) still renders
correctly once the row above it can grow — it should, since it's already
a sibling in the same `Column`, not inside the resized `SizedBox`, but
verify this by reading the full widget tree before and after your change.

- [ ] **Step 2: Fix `home_dashboard_page.dart`**

Read the full file first, including `_HomeCard`'s definition. Replace the
per-section `SizedBox(height: 190, ...)` with a height computed from
content instead of a fixed constant — the simplest fix consistent with
this being a horizontally-scrolling `ListView` of fixed-width cards is to
keep the row's overall height fixed but let `_HomeCard`'s *internal*
text area flex rather than being implicitly capped by the outer 190px —
read `_HomeCard`'s actual layout (the 130×130 art tile + gap + two text
lines) and confirm whether the overflow risk is in `_HomeCard` clipping
internally or the outer `SizedBox` clipping `_HomeCard` as a whole; fix
whichever is the actual constraint after reading the real code (the
audit's finding was based on approximate height math, not a confirmed
render — verify before assuming which fix applies). If the outer
`SizedBox` is the actual constraint, consider whether it should scale
with `AppSettings.textScaleFactor` directly (e.g.
`height: 190 * (textScale > 1.0 ? 1.0 + (textScale - 1.0) * 0.4 : 1.0)`,
a damped scale so the row grows for accessibility without ballooning the
whole horizontal-scroll section) rather than becoming fully unbounded,
since an unbounded height inside a fixed-height section of the page could
itself look wrong.

- [ ] **Step 3: Tests**

For both widgets, add a test that pumps the widget tree with
`MediaQuery` overridden to the maximum `1.5` text scale factor (matching
`AppSettings`'s own clamp ceiling) and asserts no overflow exception is
thrown (`tester.takeException()` returns `null`) — verify this test
genuinely fails against the pre-fix code first (temporarily revert, run,
confirm failure, reinstate the fix), the same regression-proof discipline
used elsewhere in this plan.

- [ ] **Step 4: Verify and commit**

Run `flutter analyze` and `flutter test`. Commit.

---

### Task 9: Upfront permission priming

**Files:**
- Modify: `lib/core/permissions.dart`
- Modify: `lib/ui/onboarding/onboarding_page.dart`
- Modify: `lib/core/plugin_context.dart` (Visualizer's microphone request
  needs a matching `PluginContext` method — see Step 2)
- Modify: `Omnis-Plugins/lib/visualizer_plugin.dart` (route its direct
  `permission_handler` call through the new `PluginContext` method
  instead — **note: this is the only file this whole plan touches in the
  Omnis-Plugins repo**; commit it there separately from every other
  commit in this plan, which all land in the Omnis repo only)
- Modify: `test/permissions_test.dart`
- Test: `test/onboarding_page_test.dart` (extend — check it exists first)

**Interfaces:**
- Consumes: `PluginManager.plugins` (`List<ManagedPlugin>`, each with
  `.id`/`.enabled` — already exists, `lib/core/plugin_manager.dart:253`).
- Produces: `OmnisPermissions.ensureUpfrontPermissions(PluginManager)` —
  the new batching entry point every step below builds toward.
- Produces: `PluginContext.requestMicrophonePermission()` — a fourth
  capability-request method alongside the three that already exist
  (`requestStorageWritePermission`/`requestBluetoothPermission`/
  `requestLocationPermission`, `plugin_context.dart:227-237`), added so
  the Visualizer's permission request goes through the same uniform path
  the batching logic in this task needs.

- [ ] **Step 1: Add `requestMicrophonePermission` to the plugin capability surface**

In `lib/core/permissions.dart`, add a fourth method to `OmnisPermissions`,
matching the existing four methods' shape exactly (try/catch,
non-throwing, returns whether granted):

```dart
  /// Requests microphone access, for a plugin that taps system audio via
  /// an API the OS gates behind this permission even when it isn't
  /// actually recording from the physical mic (e.g. Android's Visualizer
  /// API, which VisualizerPlugin uses).
  static Future<bool> requestMicrophone() async {
    try {
      final status = await Permission.microphone.request();
      return status.isGranted;
    } catch (_) {
      return false;
    }
  }
```

In `lib/core/plugin_context.dart`, add the matching capability-surface
method alongside the other three (currently lines 227-237):

```dart
  @override
  Future<bool> requestMicrophonePermission() =>
      OmnisPermissions.requestMicrophone();
```

Check `packages/omnis_plugin_api/lib/plugin_context.dart` (or wherever
`PluginContext`'s abstract interface is declared, as opposed to its one
concrete implementation in the app) for whether this needs a matching
abstract method declaration there too — if `PluginContext` is an
interface every plugin's `context` parameter is typed against, the new
method must be declared there first, or the concrete implementation's
`@override` won't compile. Read that file before writing this step's
final code.

- [ ] **Step 2: Route the Visualizer plugin's permission request through it**

In `Omnis-Plugins/lib/visualizer_plugin.dart`, read the file in full
around its current `Permission.microphone` request (line 116 area).
Replace the direct `permission_handler` call with
`context?.requestMicrophonePermission()`, removing the plugin's own
`import 'package:permission_handler/permission_handler.dart';` if nothing
else in the file needs it (grep to confirm). This is the one change in
this whole plan that lands in the Omnis-Plugins repo — commit it there,
separately, and note in your report that it depends on Step 1's
`omnis_plugin_api`/`PluginContext` change being present (via the existing
local `pubspec_overrides.yaml` sibling-checkout setup, same as every
cross-repo task in the prior two plans this session).

- [ ] **Step 3: Add the batching entry point**

In `lib/core/permissions.dart`, add:

```dart
  /// Requests everything the Core needs plus whatever [enabledPluginIds]
  /// need, in one batch — called once, at first run, after the plugin
  /// manager has completed its first pass over which plugins are enabled
  /// by default. A plugin enabled *later* still requests its own
  /// permission contextually via `PluginContext`, unchanged — this method
  /// only covers what's already enabled at the moment it's called, which
  /// is what keeps "ask upfront" compatible with "no plugins installed
  /// means nothing to ask for": a fresh install with every optional
  /// plugin left at its default (some enabled, some not) only sees
  /// prompts for what's actually active, not a hypothetical maximum.
  static Future<void> ensureUpfrontPermissions(
      Set<String> enabledPluginIds) async {
    await ensureCorePermissions();
    if (enabledPluginIds.contains('tag_editor')) {
      await requestStorageWrite();
    }
    if (enabledPluginIds.contains('bluetooth_playback')) {
      await requestBluetooth();
    }
    if (enabledPluginIds.contains('driving_mode')) {
      await requestLocation();
    }
    if (enabledPluginIds.contains('visualizer')) {
      await requestMicrophone();
    }
  }
```

Rewrite this file's class-level doc comment (currently lines 3-20) to
state the actual policy this method implements — not "ask everything
upfront" and not the old "contextual only," but: core permissions always,
plugin permissions batched once at first run scoped to whatever's enabled
then, with anything enabled later still asking contextually through
`PluginContext` exactly as before. Keep the existing reasoning about *why*
a blanket ask-everything approach is wrong (it still is — this method
doesn't do that) but correct the parts of the comment that currently
describe the plugin-permission methods as purely reactive/contextual,
since `ensureUpfrontPermissions` is a new, non-contextual caller of them.

- [ ] **Step 4: Wire it into onboarding**

Read `lib/ui/onboarding/onboarding_page.dart` in full. The existing
second screen already fires `OmnisPermissions.ensureCorePermissions` as
its `onEnter` (lines 61-66). Replace that single call with a call to
`ensureUpfrontPermissions`, needing the currently-enabled plugin id set —
this screen doesn't have direct access to `PluginManager` today (it's
constructed before `HomePage`/`MainCore` in the normal cold-start flow
per `main.dart`'s `home: settings.hasCompletedOnboarding ? HomePage() :
OnboardingPage()`). Two real options, pick whichever fits this
codebase's existing patterns better after reading `bootstrap.dart` again:
(a) call `ensureCoreReady()` from this screen's `onEnter` first (it's
already idempotent, so calling it slightly earlier than `HomePage` normally
would is safe) to get a real `MainCore`/`PluginManager` instance, read
`.pluginManager.plugins.where((p) => p.enabled).map((p) => p.id).toSet()`,
then call `ensureUpfrontPermissions` with that set; or (b) if
`ensureCoreReady()` at this point in the flow causes problems (check by
running the existing onboarding tests after trying this), fall back to a
hardcoded "whatever's enabled by default in `bundled_plugins.dart`" list
computed without needing a live `PluginManager` — read
`Omnis-Plugins/lib/bundled_plugins.dart` (or wherever the default
enabled/disabled state per plugin is declared) to see if that's
determinable statically. Prefer (a) if it works cleanly; it's the more
correct source of truth (an actual `enabled` check, not a hardcoded
mirror of defaults that could drift).

Also update the screen's copy (`l10n.onboardingPermissionsBody` and
whatever string resource backs it — check
`lib/l10n/app_en.arb`/wherever this app's localization strings live) to
explain what's being requested in plain language, built from the actual
plugin set rather than a single generic sentence — at minimum, name
storage/media access (core) and, conditionally, name whichever of
Bluetooth/location/microphone apply given what's actually enabled. If
this app's l10n system doesn't easily support a dynamically-built string
list, a simpler acceptable fallback is a short bullet list widget built
in Dart directly on the onboarding screen (icon + one-line explanation
per applicable permission) rather than trying to force this into the
`.arb` string-resource format — check how other dynamic content
(if any) is already handled in this app's UI before choosing.

- [ ] **Step 5: Update `test/permissions_test.dart`**

Read the existing file in full. Add tests for `requestMicrophone`
(mirroring the existing per-permission tests' try/catch/non-throwing
pattern) and for `ensureUpfrontPermissions` — specifically, tests proving
it only ever calls the plugin-specific request methods for ids actually
present in the set passed in (e.g., calling it with an empty set should
result in zero plugin-permission requests beyond the always-on core one;
calling it with only `{'tag_editor'}` should request storage-write and
nothing else). This is the test the final review will look at to confirm
the batch genuinely stays scoped to what's enabled, not everything.

- [ ] **Step 6: Verify and commit**

Run `flutter analyze` and `flutter test` in Omnis. Run them in
Omnis-Plugins too, for Step 2's change. Commit each repo's changes
separately.

---

### Task 10: Visual Tier 1 fixes (batch)

**Files:**
- Modify: `lib/ui/library_page.dart:3116`
- Modify: `lib/ui/online_page.dart:333`
- Modify: `lib/ui/radio_page.dart:393,436`
- Modify: `lib/ui/now_playing_page.dart` (app bar — read current line
  numbers, shifted by Tasks 2/5's edits)
- Modify: `lib/ui/player_layouts/full_art_gestures_layout.dart` (real
  album art — read current line numbers, shifted by Task 5's edit)
- Modify: `lib/ui/theme/omnis_theme.dart:99-142` (`OmnisTheme.build`)
- Modify: `lib/ui/player_layouts/player_widgets.dart` (`PlayerExtrasRow`
  — read current line numbers, shifted by Task 4's edit)
- Test: extend existing coverage for each file touched — grep first for
  each

**Interfaces:** None new — every fix here reads `Theme.of(context)`,
already-established convention throughout this codebase.

This task batches six small, independent, purely-visual fixes from the
design audit's Tier 1 list — each is contained to one file/widget, none
depend on each other, and all are low-risk. Dispatch this whole task to
an implementer experienced with Flutter visual/theming work.

- [ ] **Step 1: Replace the four hardcoded `Colors.deepPurple` "now playing" markers**

At `library_page.dart:3116`, `online_page.dart:333`, `radio_page.dart:393`,
and `radio_page.dart:436`, each currently reads
`const Icon(Icons.graphic_eq, color: Colors.deepPurple)`. Replace
`Colors.deepPurple` with `Theme.of(context).colorScheme.primary` at each
site — this can no longer be a `const` constructor once it reads
`Theme.of(context)`, so drop the `const` keyword too. Read each
surrounding method first to confirm `context` is in scope at each call
site (it should be, as a build-method-local widget helper in all four
cases).

- [ ] **Step 2: Give `NowPlayingPage` a transparent/overlay app bar**

Read `now_playing_page.dart`'s `build` method in full (the current
`Scaffold(appBar: AppBar(title: const Text('Now Playing')), ...)`).
Replace the `AppBar` with one that doesn't impose a generic opaque strip
over every layout: `backgroundColor: Colors.transparent`,
`elevation: 0`, drop the text title entirely (rely on the system back
button/gesture alone — check what leading widget `AppBar` supplies by
default when no `title` is given, and confirm a back affordance still
exists), and set `foregroundColor`/`iconTheme` to whatever each layout's
own overlay theme already establishes for legibility (read
`standard_layout.dart`'s `overlayTheme` construction, referenced in the
design audit, for the pattern other parts of this layout already use to
stay legible over arbitrary album art).

- [ ] **Step 3: Wire real album art into Full Art Gestures**

Read `full_art_gestures_layout.dart` in full (post-Task-5 edit). Replace
the `Icons.album` placeholder + `primaryContainer`→`surface` gradient
`DecoratedBox` with real artwork: `Positioned.fill(child: TrackArtwork
(track: data.track, fit: BoxFit.cover))` (matching `StandardLayout`'s own
`TrackArtwork` usage pattern — read that file for the exact constructor
call/import it uses), plus a scrim (a semi-transparent gradient overlay,
so any `PluginSlotView` content positioned on top per the existing
`Positioned(top: 12, ...)` block stays legible over arbitrary art) rather
than removing the gradient entirely.

- [ ] **Step 4: Extend `OmnisTheme.build` to cover dialogs, sheets, snackbars, and chips**

Read `lib/ui/theme/omnis_theme.dart`'s `build` method in full (currently
lines ~60-144). Add `dialogTheme`, `bottomSheetTheme`, `snackBarTheme`,
and `chipTheme` entries to the `base.copyWith(...)` call, deriving shape
from the same `radius` local variable the existing `cardTheme`/
`inputDecorationTheme`/button themes already use — `DialogTheme(shape:
RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)))`,
`BottomSheetThemeData(shape: RoundedRectangleBorder(borderRadius:
BorderRadius.only(topLeft: Radius.circular(radius), topRight:
Radius.circular(radius))))` (top-corners-only, matching how a bottom
sheet actually renders), `SnackBarThemeData(shape:
RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius * 0.5)))`,
`ChipThemeData(shape: RoundedRectangleBorder(borderRadius:
BorderRadius.circular(radius * 0.6)))` — matching the existing
multiplier conventions (`radius`, `radius*0.5`, `radius*0.6`) already
established for other widget types in this same method, rather than
inventing new ratios.

- [ ] **Step 5: Fix `PlayerExtrasRow`'s mixed button styles and missing wrap guard**

Read `player_widgets.dart`'s `PlayerExtrasRow` in full (post-Task-4 edit,
line numbers will have shifted). Standardize the three buttons (Queue,
Equalizer, Visualizer) on one visual treatment — `OutlinedButton.icon` for
all three is the simplest change consistent with the audit's
recommendation, since two of the three already use it. Wrap the `Row` in
a `Wrap` widget (`spacing`/`runSpacing` matching whatever gap the current
`Row` uses between children) so up to four buttons (Queue, Equalizer,
Visualizer, plus AB-repeat if that plugin's slot is also present) reflow
to a second line on a narrow width instead of requiring `FittedBox` or
overflowing.

- [ ] **Step 6: Tests**

For Step 1: a widget test setting a non-default theme accent color and
asserting the "now playing" marker icon renders with that color, not a
hardcoded purple, at each of the (up to) 4 call sites reachable from
existing test fixtures. For Steps 2-3: visual/structural assertions
(app bar has no title text and transparent background; Full Art Gestures
renders a `TrackArtwork` widget, not an `Icons.album` fallback) rather
than pixel-level golden tests, matching this codebase's existing testing
style (grep a few existing widget tests in `test/` to confirm this
project doesn't already use golden-file testing before deciding style).
For Step 4: a test confirming `Theme.of(context).dialogTheme`/
`bottomSheetTheme`/`snackBarTheme`/`chipTheme` all derive their shape from
a themed radius rather than falling back to Material defaults. For Step
5: a test at a narrow width confirming the extras row wraps to multiple
lines rather than overflowing with all four possible buttons visible.

- [ ] **Step 7: Verify and commit**

Run `flutter analyze` and `flutter test`. Commit.

---

## After This Plan

The Tier 2/3 visual-design items (empty-state redesigns, full icon-catalog
coverage beyond the curated ~25-glyph subset, onboarding visual identity,
basic cross-screen transitions, and the two explicitly-deferred systemic
items — elevation/per-component shape tokens, and unifying the theme and
layout manifest systems per the product spec's original "theme = UI
composition, not just color" definition) remain unplanned, per the project
owner's own scoping decision. A separate theme/layout *plugin* system
(skins, custom layouts, and custom icons deliverable as plugins rather
than only as in-app-editable manifests) is a distinct, larger architectural
direction the project owner has also asked for — brainstormed and spec'd
separately, not folded into this plan, since it extends the same
bundled-vs-downloadable plugin boundary this session's Core/plugin
re-architecture work already established and deserves the same design
rigor.
