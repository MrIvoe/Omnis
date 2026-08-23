# Platform Capabilities & Upfront Permissions — Design Spec

## Goal

Two related hardening changes to Omnis (Android + Windows today), both agreed
with the project owner:

1. **Platform-capability-aware UI**: features that only make sense on one
   input model (hardware-keyboard shortcuts, swipe-as-a-button-shortcut)
   should be fully hidden — not just defaulted off — on a platform class
   where they don't apply. Direct-manipulation drag (waveform scrubbing,
   drag-to-place, swipe-to-delete) stays everywhere, since a mouse drags
   too.
2. **Upfront, batched permission requesting**: instead of asking for each
   permission lazily the first time a feature needs it, ask once at first
   run for everything the *core* player and whatever plugins are *enabled
   by default* actually need — preceded by a short in-app explanation
   screen. A plugin enabled later still prompts contextually at that
   point, unchanged from today.

Both are scoped to the two platforms Omnis ships today (Android, Windows).
Neither adds new platform folders (iOS/macOS/Linux/Web) — the point is to
make the existing code genuinely capability-driven so a future platform
addition doesn't require re-litigating any of this.

## Current state (established by investigation, not assumption)

- **No existing capability abstraction.** ~10 scattered, sometimes
  duplicated `Platform.isX`/`kIsWeb` checks exist directly at call sites
  across `lib/core/audio_engine.dart`, `lib/core/media_scanner.dart`,
  `lib/core/main_core.dart`, `lib/core/output_device_controller.dart`,
  `lib/ui/widgets/track_artwork.dart`, and `lib/ui/playlist_page.dart`
  (the same "is this desktop" check — `!kIsWeb && !Platform.isAndroid &&
  !Platform.isIOS` — appears 5 times in that last file alone, plus once
  more in `lib/ui/settings/backup_settings_page.dart`).
- **Keyboard shortcuts** (`lib/ui/global_keyboard_shortcuts.dart`) and
  **swipe gestures** (`lib/ui/player_layouts/full_art_gestures_layout.dart`,
  `karaoke_gestures_layout.dart`, `lib/ui/now_playing_page.dart`'s
  `_wrapWithGestureMode`, `lib/ui/home_page.dart`'s nav-reveal drag) are
  each gated by exactly one `AppSettings` boolean
  (`keyboardShortcutsEnabled`, `allowSwipeGestures`/`gestureMode`), shown
  identically on every platform. Neither checks `Platform.isX` anywhere.
- **Direct-manipulation drag** (`lib/ui/widgets/waveform_seek_bar.dart`'s
  scrub, `lib/ui/player_layouts/declarative/layout_editor_page.dart`'s
  drag-to-place, `Dismissible` swipe-to-delete in `playlist_page.dart` and
  `lib/ui/widgets/queue_panel.dart`) is a different category: a desktop
  mouse can drag too, so this stays available on every platform under this
  spec — only the swipe-as-a-shortcut-for-a-button pattern is
  touch-exclusive.
- **Permissions today** are centralized in `lib/core/permissions.dart`
  (`OmnisPermissions`), but split between one always-on boot-time request
  and several lazy, plugin-triggered ones:
  - `ensureCorePermissions()` — `Permission.notification` only — called
    unconditionally on every launch from `MainCore.initialize()`
    (`lib/core/main_core.dart:151`, which runs via
    `lib/core/bootstrap.dart:15-37`'s `ensureCoreReady()`, invoked from
    `HomePage.initState`).
  - `requestStorageWrite()` (`Permission.manageExternalStorage`),
    `requestBluetooth()` (`Permission.bluetoothConnect`/`bluetoothScan`),
    `requestLocation()` (`Permission.locationWhenInUse`/`locationAlways`)
    are exposed only through `PluginContext.requestStorageWritePermission
    ()`/`requestBluetoothPermission()`/`requestLocationPermission()`
    (`lib/core/plugin_context.dart:227-237`) and called lazily by
    `Omnis-Plugins/lib/tag_editor_plugin.dart:252-261`,
    `bluetooth_playback_plugin.dart:123-124`, and
    `driving_mode_plugin.dart:128-136` respectively, only when that
    specific plugin is enabled/used.
  - `Omnis-Plugins/lib/visualizer_plugin.dart:116` requests
    `Permission.microphone` directly (imports `permission_handler`
    itself), only when the Visualizer plugin is activated.
  - Library-scan storage read (`READ_MEDIA_AUDIO`/`READ_EXTERNAL_STORAGE`)
    is requested by `on_audio_query`'s own `checkAndRequest()`
    (`lib/core/media_scanner.dart:77`), bypassing `OmnisPermissions`
    entirely — a separate mechanism this spec does not change.
  - `permissions.dart:3-20`'s own doc comment states an explicit,
    reasoned **anti-upfront-permissions** design ("asking for a permission
    a fresh install has no use for yet is exactly the kind of 'why does
    this app want that' moment that makes people distrust an app").
    This spec's permission change directly supersedes that framing — see
    "What changes and why it's still principled" below.
  - `android/app/src/main/AndroidManifest.xml` also declares `INTERNET` —
    a **normal, install-time-granted permission with no runtime prompt on
    Android at all**. This spec does not add any runtime request for it;
    there is nothing to ask for.
  - `WRITE_SETTINGS` (Ringtone plugin) has no runtime `permission_handler`
    request visible in the codebase today — out of scope for this spec,
    unchanged.

## Part 1: `PlatformCapabilities`

### Design

A new file, `lib/core/platform_capabilities.dart`, exposing a small,
side-effect-free static class — no `InheritedWidget`, no `ChangeNotifier`.
Capabilities are fixed for a given build/device (Flutter has no reliable
runtime signal for "a keyboard was just attached to this Android tablet"
without platform-channel work this spec doesn't attempt), so a static
class consumed the same way `AppSettings.instance` already is elsewhere is
the right weight — not a new state-management pattern.

```dart
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

/// Static, build-time-fixed platform-class flags — never re-evaluated
/// mid-session, since Flutter has no reliable signal for a capability
/// changing at runtime (a keyboard attached to a running Android device,
/// a touchscreen enabled on Windows) without platform-channel work this
/// class deliberately doesn't attempt. Consumed like `AppSettings.instance`
/// elsewhere in this codebase: a plain static read, not an `InheritedWidget`
/// or `ChangeNotifier` — there is nothing here to listen for changes to.
///
/// Two platform *classes*, not raw `Platform.isX` — every call site should
/// ask "does this device's input model support X" via these flags, never
/// re-derive its own `Platform.isAndroid`/`kIsWeb` check for a UI-adaptivity
/// decision. A handful of existing `Platform.isX` checks in this codebase
/// are genuine OS-API-level differences (e.g. hardware EQ being literally
/// Android-only) rather than input-model differences — those stay as
/// direct checks; only checks that exist to answer "should this UI feature
/// be shown" belong here. See each flag's own doc for which existing call
/// sites migrate.
class PlatformCapabilities {
  const PlatformCapabilities._();

  /// Android or iOS: assume touch is the primary input model, and assume
  /// no hardware keyboard is normally attached. A foldable/tablet with a
  /// keyboard case is a real exception this flag doesn't detect — accepted
  /// per this spec's "Two platform classes, not a device inventory" scope
  /// note below.
  static bool get isTouchPrimary =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Windows, macOS, or Linux: assume keyboard+mouse is the primary input
  /// model, and assume no touchscreen is normally present. A Windows
  /// touch-laptop is the real exception this flag doesn't detect — same
  /// acceptance as above.
  static bool get isDesktopPrimary =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
}
```

**Two platform classes, not a device inventory.** This deliberately does
not attempt per-device hardware detection (no "does this Android device
have a keyboard attached" check) — Flutter has no first-party API for
that, and building one is real, separate platform-channel work out of
this spec's scope. The two flags encode the platform's *typical* input
model. A user on a genuine exception (Android tablet with keyboard case,
Windows touch-laptop) loses access to a settings page rather than getting
a wrong default — judged an acceptable trade-off for the scope of this
pass; revisit only if it proves to be a real problem, per this session's
established norm for provisional judgment calls.

### What migrates onto it

**Fully hidden on `isTouchPrimary`** (currently gated only by an
always-visible `AppSettings` toggle):
- The "Keyboard Shortcuts" settings page/section entirely.
- `GlobalKeyboardShortcuts`'s wiring around `HomePage`'s `Scaffold` —
  not just disabled via its `_enabled` check, removed from the widget
  tree, since a `CallbackShortcuts`/`Focus` wrapper that never fires is
  still overhead. (Hardware media-key bindings — `mediaPlayPause` etc. —
  are a narrower case: these fire from real hardware buttons some
  Android devices do have (Bluetooth headset controls, wired headset
  buttons), so they stay active on `isTouchPrimary` even though the rest
  of `GlobalKeyboardShortcuts` doesn't apply. Implementation must keep
  media-key handling reachable independent of the settings-page/shortcut
  wiring being hidden.)

**Fully hidden on `isDesktopPrimary`**:
- The `GestureMode` dropdown (`swipe`/`taps`/`none`) in
  `lib/ui/settings/controls_settings_page.dart` — collapses to `taps`
  behavior only, since "none" and "taps" both already work without touch
  and "swipe" doesn't apply.
  `now_playing_page.dart`'s `_wrapWithGestureMode` early-returns the
  child unwrapped when `PlatformCapabilities.isDesktopPrimary`, matching
  its existing `!settings.allowSwipeGestures` early-return exactly.
- The swipe-to-skip gesture in `full_art_gestures_layout.dart` and
  `karaoke_gestures_layout.dart` — `onHorizontalDragEnd` removed from
  each layout's `GestureDetector`
  when `PlatformCapabilities.isDesktopPrimary` (the `onTap` play/pause
  stays, since a mouse click is a real tap). Each layout's existing
  `Semantics`/`customSemanticsActions` (added for screen-reader parity)
  must keep working regardless — this spec changes gesture *input*, not
  the accessible-action surface.
- `home_page.dart`'s `onVerticalDragEnd` nav-bar-reveal gesture — the
  auto-hide-nav-on-landscape/Car-Mode feature this drag reveals is itself
  a phone/tablet-oriented feature (see `home_page.dart`'s own doc comment
  on `autoHideActive`), so on `isDesktopPrimary` the nav bar simply never
  auto-hides in the first place (the `autoHideActive` computation should
  short-circuit to `false` when `isDesktopPrimary`, making the drag
  handler dead code by construction rather than needing its own
  separate guard).

**Stays everywhere, unchanged** (direct-manipulation drag, not
swipe-as-a-shortcut): `waveform_seek_bar.dart`'s scrub,
`layout_editor_page.dart`'s drag-to-place,
`Dismissible` swipe-to-delete in `playlist_page.dart`/`queue_panel.dart`.
None of these are touched by this spec.

**Consolidation, not just new hiding**: every one of the ~10 pre-existing
`Platform.isX`/`kIsWeb` checks in `audio_engine.dart`,
`media_scanner.dart`, `main_core.dart`, `output_device_controller.dart`,
`track_artwork.dart`, and `playlist_page.dart`'s 5 repeated desktop checks
should be evaluated case-by-case during implementation: a check that's
genuinely asking "should this UI feature be visible/active" (e.g.
`playlist_page.dart`'s repeated desktop-only direct-file-write path
before invoking a file picker) migrates to
`PlatformCapabilities.isDesktopPrimary`; a check that's asking "does this
OS API exist at all" (e.g. `output_device_controller.dart`'s
`supportsDeviceSelection => Platform.isAndroid`, hardware EQ being
Android-only) stays a direct `Platform.isX` check, since that's a real
OS-capability fact, not an input-model/UI-adaptivity decision this new
class is meant to centralize.

## Part 2: Upfront permission priming

### Design

**Scope of the upfront batch**: at first run, after the plugin manager has
completed its first pass over which bundled plugins are enabled by
default, request:
- Always: whatever `ensureCorePermissions()` already requests
  (notification) — unchanged, still core.
- Conditionally, one check per plugin capability: storage-write only if a
  plugin needing `requestStorageWritePermission()` is enabled (today:
  Tag Editor); Bluetooth only if a plugin needing
  `requestBluetoothPermission()` is enabled (today: Bluetooth Playback);
  location only if a plugin needing `requestLocationPermission()` is
  enabled (today: Driving Mode); microphone only if the Visualizer plugin
  specifically is enabled (its request bypasses `PluginContext` and calls
  `permission_handler` directly today — this spec's batching logic needs
  to special-case it or, more cleanly, route it through the same
  `PluginContext` capability-request pattern as the other three so the
  batching logic has one uniform way to ask "does this enabled plugin
  need this permission").

A plugin not enabled by default costs nothing at first run — matches
"no plugins installed = simple player" — and still prompts contextually
the first time it's enabled later, exactly as today. This is *narrower*
than literally "everything up front," and that narrowing is what keeps
this compatible with the plugin architecture's existing minimalism
principle.

**UI**: a new onboarding screen, inserted into the existing
`OnboardingPage` flow (`lib/ui/onboarding/onboarding_page.dart`), which
already has a per-screen `onEnter`-fires-once mechanism (`_OnboardingScreen`,
lines 14-26, `_maybeEnter` at 85-94) used today for the single
`ensureCorePermissions()` call on its second screen. This spec extends
that same mechanism: the screen lists, in plain language, what's about to
be requested and why (short, per-permission one-liners: "Files & Media —
so Omnis can find your music," and conditionally "Bluetooth — so
\[enabled plugin name\] can connect to your speaker/headphones," etc.,
built from whichever plugins are actually enabled), then fires the real
batched `permission_handler` calls when the user taps through.

**What changes in `permissions.dart`**: the file's own doc comment
(lines 3-20) currently argues against upfront batching in general. That
argument doesn't disappear — it's *why* the batch stays scoped to
core-plus-enabled-plugins rather than literally every permission any
plugin could ever want, and why plugins enabled after first run still ask
contextually, matching the platform guidance the comment cites. The
comment needs rewriting to state the actual, narrower policy this spec
implements, not just relaxed to allow anything. `test/permissions_test.dart`
will need corresponding updates once the batching entry point exists,
proving the batch only ever requests permissions for the plugin set it
was given, never more.

### What does not change

- Lazy, plugin-triggered requests for a plugin enabled *after* first run
  — unchanged. Enabling Bluetooth Playback for the first time in Settings
  still triggers `requestBluetoothPermission()` right then, exactly as
  today.
- Library-scan storage read via `on_audio_query`'s own
  `checkAndRequest()` — a separate mechanism this spec doesn't touch
  (folded into "storage/media" messaging on the priming screen for user
  clarity, but not re-routed through `OmnisPermissions`).
- `INTERNET` — no runtime request exists or is added; it's a manifest-only
  permission on Android.
- `WRITE_SETTINGS` (Ringtone) — out of scope, no runtime request exists
  today.

## Self-review

- **Placeholder scan**: no TBD/TODO; every behavior change names its
  exact file and current line numbers, gathered by direct investigation
  this session, not assumed.
- **Internal consistency**: Part 1's "stays everywhere" list and Part 2's
  "what does not change" list are both deliberate exclusions stated
  explicitly, not silently dropped scope.
- **Scope check**: both parts are Android+Windows only, no new platform
  folders, consistent with the project owner's explicit scope decision
  for this pass.
- **Ambiguity check**: the two accepted false-negative cases (Android+
  keyboard-case tablet, Windows touchscreen) are named and their
  trade-off stated explicitly rather than left implicit.
