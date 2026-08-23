# Core/Plugin Re-architecture — Tier 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate the seven remaining `pluginManager.bundled<XPlugin>(onlyEnabled: true)` concrete-type reaches in `library_page.dart`, `online_page.dart`, and `playlist_page.dart`, converting each to look up a capability interface via `pluginManager.services.get<T>()` instead — the same conversion Tier 0 already proved twice (Favorites, Radio) with zero review findings on either.

**Architecture:** No new mechanism. Every task in this plan is an instance of the pattern already established in `packages/omnis_plugin_api/lib/service_interfaces.dart`: define (or extend) a capability interface there, make the bundled plugin `implements` it (already true for 5 of 7 — only `RingtonePlugin` and `TagEditorPlugin`'s broader surface need a genuinely new interface), then swap the UI call site's concrete-type getter for `widget.pluginManager.services.get<T>()`. Two tasks (T1.4, T1.6) also move a plugin-owned value type into `omnis_plugin_api` alongside the interface that returns it — the same reason `EnrichmentResult`/`AudioAnalysisResult`/`LyricLine` already live there: a capability interface needs a portable return type neither side of the boundary owns exclusively.

**Tech Stack:** Flutter/Dart, the existing `ServiceRegistry`/`PluginManager` capability-lookup mechanism (`lib/core/plugin_manager.dart`), `packages/omnis_plugin_api` (the dependency-free contracts package shared by both repos).

**Spec:** `docs/superpowers/specs/2026-08-22-core-plugin-rearchitecture-plan.md` (Part 1D names all seven reaches; Part 3's Tier 1 section is this plan's source task list, T1.1-T1.7).

## Global Constraints

- Every new/extended interface lives in `packages/omnis_plugin_api/lib/service_interfaces.dart` (or a sibling file in that package for a moved value type) — never in `lib/plugin_api/*.dart` (those are re-export shims only) and never defined directly in the Omnis app or Omnis-Plugins repo.
- A UI call site converts to `widget.pluginManager.services.get<IInterfaceName>()`, never `widget.pluginManager.bundled<ConcretePlugin>(onlyEnabled: true)` — the whole point of every task here.
- Any interface method added to an interface that already has another implementer besides the plugin this task targets must be implemented on *every* implementer, or the analyzer fails the build. Check `grep -rn "implements I<Name>" lib/` in the Omnis repo (Sandboxed adapters live in `lib/core/plugin_sandbox_services.dart`) before finalizing any interface's method list.
- A method added to an interface must exactly match an existing method already present on the bundled plugin implementing it (name, parameter types, return type) wherever the plugin already has the real implementation — these tasks are adding a contract *for a capability that already exists in working code*, not inventing new behavior.
- This plan executes directly on `main` in both repos, same as Tier 0 — no isolated worktree. (Ruling already made and recorded once in Tier 0's ledger; carries forward unchanged for Tier 1.)
- After every task: `flutter analyze` and `flutter test` must both pass clean in whichever repo(s) the task touched, using the repos' existing local `pubspec_overrides.yaml` sibling-checkout setup (already in place, gitignored, untouched by this plan) so cross-repo changes are visible to each other without cutting a tag per task. **Tag/pubspec-pin bumps for both repos happen once, in Task 8, after all seven conversions are complete and reviewed** — not per task. This mirrors Tier 0's own C1 lesson: a tag cut before its own dependent commit lands is a real, previously-shipped mistake (see `Omnis-Plugins/docs/VERSIONING.md`) — bundling every pin bump into one final task removes the chance to repeat it mid-plan.
- Follow the codebase's existing capability-interface style exactly: an interface class named `I<Noun>`, one dartdoc paragraph per method explaining the *contract* (what "not found"/failure returns, never throws), no implementation. Copy the tone of the existing interfaces in `service_interfaces.dart` rather than inventing new conventions.

---

### Task 1: `ILyricsProvider.hasLyrics` — convert `library_page.dart`'s Lyrics reach

**Files:**
- Modify: `Omnis/packages/omnis_plugin_api/lib/service_interfaces.dart` (add one method to `ILyricsProvider`, currently lines 29-36)
- Modify: `Omnis/lib/core/plugin_sandbox_services.dart` (`SandboxedLyricsProvider`, currently lines 76-112 — must implement the new method or the build breaks)
- Modify: `Omnis/lib/ui/library_page.dart` (lines 282, 285-286)
- Test: `Omnis-Plugins/test/lyrics_plugin_test.dart` (add one assertion)
- Test: `Omnis/test/plugin_system_test.dart` (add coverage for `SandboxedLyricsProvider.hasLyrics`)

**Interfaces:**
- Consumes: `LyricsPlugin.hasLyrics(BaseTrack track) -> bool` — already exists at `Omnis-Plugins/lib/lyrics_plugin.dart:207`, unchanged by this task.
- Produces: `ILyricsProvider.hasLyrics(BaseTrack track) -> bool`, callable via `pluginManager.services.get<ILyricsProvider>()?.hasLyrics(track)`.

- [ ] **Step 1: Add `hasLyrics` to `ILyricsProvider`**

In `service_interfaces.dart`, inside the existing `ILyricsProvider` class body (right after `currentLyricFor`'s closing brace, before the class's own closing brace):

```dart
  /// Whether [track] has any lyrics stored for it at all — a cheaper,
  /// synchronous existence check a caller uses to decide whether to show
  /// a "has lyrics" indicator, without needing the full text
  /// [currentLyricFor] returns. Matches `LyricsPlugin.hasLyrics`'s own
  /// convention: `false` for "nothing stored," never a thrown error.
  bool hasLyrics(BaseTrack track);
```

`LyricsPlugin` already declares `bool hasLyrics(BaseTrack track) => ...` at `lib/lyrics_plugin.dart:207` with this exact signature — no change needed on the plugin side; it already satisfies the interface the moment the method is declared here.

- [ ] **Step 2: Implement the new method on `SandboxedLyricsProvider`**

In `plugin_sandbox_services.dart`, add to the `SandboxedLyricsProvider` class (after `currentLyricFor`, before `syncedLyricsFor`):

```dart
  /// A sandboxed plugin has no dedicated "does this exist" hook — the
  /// only signal available is whether [currentLyricFor] returns
  /// something other than its own fallback message. Reusing that hook
  /// here (rather than adding a second guest-hook contract for a cheaper
  /// existence check) is a first cut, same as [syncedLyricsFor]'s own
  /// documented always-null shortcut immediately below — a dedicated
  /// `hasLyrics` guest hook is real, separate work if this ever needs to
  /// be cheaper than calling `provideLyrics` once.
  @override
  bool hasLyrics(BaseTrack track) {
    try {
      return currentLyricFor(track, Duration.zero) != _fallback;
    } catch (_) {
      return false;
    }
  }
```

- [ ] **Step 3: Convert the `library_page.dart` call site**

Replace (currently lines 285-286):

```dart
  LyricsPlugin? get _lyricsPlugin =>
      widget.pluginManager.bundled<LyricsPlugin>(onlyEnabled: true);
```

with:

```dart
  ILyricsProvider? get _lyricsProvider =>
      widget.pluginManager.services.get<ILyricsProvider>();
```

Then update the one call site at line 282, inside `_visibleTracks`'s `filterTracks(...)` call, from `hasLyrics: _lyricsPlugin?.hasLyrics,` to `hasLyrics: _lyricsProvider?.hasLyrics,`.

Remove the now-unused `import 'package:omnis_plugins/lyrics_plugin.dart';` from `library_page.dart` if nothing else in the file references `LyricsPlugin` by concrete type — grep the file for `LyricsPlugin` first to confirm.

- [ ] **Step 4: Add plugin-side test coverage**

In `Omnis-Plugins/test/lyrics_plugin_test.dart`, add (near any existing "implements" assertion in that file, or as a new top-level test if none exists):

```dart
test('LyricsPlugin satisfies ILyricsProvider', () {
  final plugin = LyricsPlugin();
  expect(plugin, isA<ILyricsProvider>());
});
```

Read the existing file first to match its setup pattern (constructor arguments, any required `attach`/`initialize` call) exactly — do not guess the constructor signature.

- [ ] **Step 5: Add sandboxed-adapter test coverage**

In `Omnis/test/plugin_system_test.dart`, find the existing `SandboxedLyricsProvider` test group (search for `SandboxedLyricsProvider`) and add a case exercising `hasLyrics`: one where the underlying `provideLyrics` hook returns real text (`hasLyrics` returns `true`), and one where it returns nothing/throws (`hasLyrics` returns `false`). Match the existing tests' fake-`PluginRuntime` setup in that file exactly.

- [ ] **Step 6: Verify and commit**

Run `flutter analyze` and `flutter test` in both `Omnis` and `Omnis-Plugins`. Commit each repo's changes separately with a message describing the `ILyricsProvider` conversion.

---

### Task 2: `IMetadataProvider.lookupArtwork` — convert `library_page.dart`'s artwork-lookup reach

**Files:**
- Modify: `Omnis/packages/omnis_plugin_api/lib/service_interfaces.dart` (add one method to `IMetadataProvider`, currently lines 200-210)
- Modify: `Omnis/lib/ui/library_page.dart` (lines 601-602, 636, 801 — **not** line 610, see note below)
- Test: `Omnis-Plugins/test/metadata_enrichment_plugin_test.dart` (add one assertion)

**Interfaces:**
- Consumes: `MetadataEnrichmentPlugin.lookupArtwork(BaseTrack track) -> Future<Uint8List?>` — already exists at `Omnis-Plugins/lib/metadata_enrichment_plugin.dart:163`, unchanged by this task.
- Produces: `IMetadataProvider.lookupArtwork(BaseTrack track) -> Future<Uint8List?>`.

**Important — do not fully eliminate `_enrichmentPlugin`.** The existing doc comment on `library_page.dart:596-600` already explains and justifies keeping one concrete-type reach: `hasAnyCredential` (used only at line 610, for a soft UI hint toast) is deliberately *not* part of `IMetadataProvider`, because it's a detail specific to this one provider's credential model that a hypothetical alternate provider wouldn't necessarily share. That reasoning is sound and this task does not change it — `MetadataEnrichmentPlugin? get _enrichmentPlugin` stays, scoped to exactly that one line. This task only moves the two *functional* `lookupArtwork` calls (which are not a UI-only hint — they're the actual artwork-fetching operation) onto the interface.

Grep no other implementer of `IMetadataProvider` exists yet besides `MetadataEnrichmentPlugin` (confirm with `grep -rn "implements IMetadataProvider" lib/` in both repos) — if that's still true when you run it, no sandboxed-adapter update is needed for this task.

- [ ] **Step 1: Add `lookupArtwork` to `IMetadataProvider`**

In `service_interfaces.dart`, add to `IMetadataProvider` (after `enrich`, before its closing brace) — note this file will need `import 'dart:typed_data';` added at the top if not already present (check first):

```dart
  /// Looks up cover art for [track] from this provider's source(s).
  /// Returns `null` — never throws — when nothing is found, the lookup
  /// fails, or this provider is unavailable, the same "fail soft"
  /// contract [enrich] already uses.
  Future<Uint8List?> lookupArtwork(BaseTrack track);
```

- [ ] **Step 2: Convert the two functional call sites**

At `library_page.dart:636` (inside `_lookupArtworkOnline`) and `:801` (inside `_lookupArtworkForAll`), replace:

```dart
    final enrichment = _enrichmentPlugin;
```

with:

```dart
    final enrichment = _metadataProvider;
```

Both call sites already only use `enrichment.lookupArtwork(track)` on the resulting value (confirmed by reading both methods in full) — no other member access needs to change. The existing `_metadataProvider` getter (`IMetadataProvider? get _metadataProvider => widget.pluginManager.services.get<IMetadataProvider>();`, already at line 586) needs no change itself.

Leave line 610 (`if (_enrichmentPlugin?.hasAnyCredential == false)`) and the `_enrichmentPlugin` getter itself (lines 601-602) exactly as they are.

- [ ] **Step 3: Add plugin-side test coverage**

In `Omnis-Plugins/test/metadata_enrichment_plugin_test.dart`, add:

```dart
test('MetadataEnrichmentPlugin satisfies IMetadataProvider', () {
  final plugin = MetadataEnrichmentPlugin();
  expect(plugin, isA<IMetadataProvider>());
});
```

Read the existing file first to match its constructor/setup pattern exactly (this plugin likely needs credential storage wired — copy whatever the file's other tests already do to construct one).

- [ ] **Step 4: Verify and commit**

Run `flutter analyze` and `flutter test` in both repos. Commit.

---

### Task 3: `IRatingsProvider`/`IThumbsProvider` write methods — convert `library_page.dart`'s Ratings reach

**Files:**
- Modify: `Omnis/packages/omnis_plugin_api/lib/service_interfaces.dart` (extend `IRatingsProvider` at lines 107-113 and `IThumbsProvider` at lines 166-170)
- Modify: `Omnis/lib/core/plugin_sandbox_services.dart` (`SandboxedRatingsProvider` lines 297-313, `SandboxedThumbsProvider` lines 315-334 — both need the new methods or the build breaks)
- Modify: `Omnis/lib/ui/library_page.dart` (lines 1551-1642 area — every `_ratingsPlugin` reach)
- Test: `Omnis-Plugins/test/ratings_plugin_test.dart` (add two assertions)
- Test: `Omnis/test/plugin_system_test.dart` (add coverage for the new sandboxed write methods)

**Interfaces:**
- Consumes: `RatingsPlugin.preciseRatingOf(String) -> double`, `RatingsPlugin.setPreciseRating(String, double) -> Future<void>`, `RatingsPlugin.setThumb(String, ThumbState) -> Future<void>` — all already exist at `Omnis-Plugins/lib/ratings_plugin.dart` (lines 152, 169, 125 respectively), unchanged by this task. `RatingsPlugin` already `implements IRatingsProvider, IThumbsProvider` (class declaration at that file's line 22-23) — adding these methods to the interfaces requires zero plugin-side code change; the plugin already has matching real implementations.
- Produces: `IRatingsProvider.preciseRatingOf`/`.setPreciseRating`, `IThumbsProvider.setThumb`.

- [ ] **Step 1: Extend `IRatingsProvider`**

In `service_interfaces.dart`, add to `IRatingsProvider` (after the existing `ratingOf`, before its closing brace):

```dart
  /// [trackId]'s rating on the same 0-5 scale as [ratingOf], but as a
  /// precise `double` rather than a rounded `int` — the picker UI reads
  /// this to show partial-star state; `0.0` if never rated, matching
  /// `RatingsPlugin.preciseRatingOf`'s own convention exactly.
  double preciseRatingOf(String trackId);

  /// Sets [trackId]'s rating to [rating] (0.0-5.0). The write side,
  /// mirroring [IFavoritesProvider.setFavorite]'s own reasoning: every UI
  /// call site that used to reach `RatingsPlugin` by concrete type now
  /// goes through this interface, which is what makes the provider
  /// swappable at all.
  Future<void> setPreciseRating(String trackId, double rating);
```

- [ ] **Step 2: Extend `IThumbsProvider`**

In `service_interfaces.dart`, add to `IThumbsProvider` (after `thumbOf`, before its closing brace):

```dart
  /// Sets [trackId]'s thumb state. Setting [ThumbState.none] clears it —
  /// matches `RatingsPlugin.setThumb`'s own convention exactly. The write
  /// side, same reasoning as [IRatingsProvider.setPreciseRating].
  Future<void> setThumb(String trackId, ThumbState state);
```

- [ ] **Step 3: Implement the new methods on `SandboxedRatingsProvider`/`SandboxedThumbsProvider`**

No `set*` guest-hook bridge exists yet for ratings/thumbs (confirmed: `plugin_sandbox_bridge.dart` has no rating/thumb bridge functions today, only the existing `ratingsRatingOf`/`thumbsThumbOf` read hooks these classes already call). Building real write-through bridge functions is separate, future sandbox-expansion work, not this plan's scope. Add documented no-op implementations, the same "first cut, degrade safely" pattern `SandboxedLyricsProvider.syncedLyricsFor` already establishes:

In `plugin_sandbox_services.dart`, add to `SandboxedRatingsProvider`:

```dart
  /// No dedicated guest hook exists for a *precise* rating read today —
  /// [ratingOf]'s existing `ratingsRatingOf` hook only ever returns a
  /// rounded int. Reusing it here (rather than losing precision
  /// silently) is honest about what's actually available: a sandboxed
  /// plugin's rating is only ever whole-star today.
  @override
  double preciseRatingOf(String trackId) => ratingOf(trackId).toDouble();

  /// Always a no-op — a first cut, same as [SandboxedLyricsProvider
  /// .syncedLyricsFor]'s documented always-null shortcut. No guest-hook
  /// bridge exists yet for *writing* a rating from a sandboxed plugin;
  /// building one (a `setRating`-style bridge function on
  /// `PluginSandboxBridge`, permission-gated the same way the existing
  /// queue/volume/state bridge functions are) is real, separate work.
  /// Silently doing nothing rather than throwing matches every other
  /// interface here's "never throws" contract.
  @override
  Future<void> setPreciseRating(String trackId, double rating) async {}
```

And to `SandboxedThumbsProvider`:

```dart
  /// Always a no-op — same reasoning and same future-work pointer as
  /// [SandboxedRatingsProvider.setPreciseRating].
  @override
  Future<void> setThumb(String trackId, ThumbState state) async {}
```

- [ ] **Step 4: Convert the `library_page.dart` call sites**

Replace the single concrete-type getter (currently lines 1551-1552):

```dart
  RatingsPlugin? get _ratingsPlugin =>
      widget.pluginManager.bundled<RatingsPlugin>(onlyEnabled: true);
```

with two interface-typed getters:

```dart
  IRatingsProvider? get _ratingsProvider =>
      widget.pluginManager.services.get<IRatingsProvider>();

  IThumbsProvider? get _thumbsProvider =>
      widget.pluginManager.services.get<IThumbsProvider>();
```

Then update every reference (read the surrounding method bodies as you go — each is a direct rename, no logic change):
- Line 1554 (`_ratingOf`): `_ratingsPlugin?.ratingOf(trackId)` → `_ratingsProvider?.ratingOf(trackId)`
- Line 1569-1570 (`_thumbOf`): `_ratingsPlugin?.thumbOf(trackId)` → `_thumbsProvider?.thumbOf(trackId)`
- Line 1576 (`_setThumb`, `final plugin = _ratingsPlugin;`) → `final plugin = _thumbsProvider;` (the rest of that method — `plugin.setThumb(...)` at line 1583 — needs no further change since `IThumbsProvider` now has `setThumb`)
- Line 1593 (`_rateTrack`, `final plugin = _ratingsPlugin;`) → `final plugin = _ratingsProvider;` (the rest of that method — `plugin.preciseRatingOf(...)` at line 1602, `plugin.setPreciseRating(...)` at line 1606 — needs no further change)
- Line 1621 (`_bulkRate`, `final plugin = _ratingsPlugin;`) → `final plugin = _ratingsProvider;` (the rest — `plugin.setPreciseRating(...)` at line 1637 — needs no further change)

Grep the whole file for `_ratingsPlugin` after these edits to confirm zero references remain, then remove the now-unused `import 'package:omnis_plugins/ratings_plugin.dart';` if nothing else in the file references `RatingsPlugin` by concrete type.

- [ ] **Step 5: Add plugin-side test coverage**

In `Omnis-Plugins/test/ratings_plugin_test.dart`, add:

```dart
test('RatingsPlugin satisfies IRatingsProvider and IThumbsProvider', () {
  final plugin = RatingsPlugin();
  expect(plugin, isA<IRatingsProvider>());
  expect(plugin, isA<IThumbsProvider>());
});
```

Read the existing file first to match its constructor/setup pattern exactly.

- [ ] **Step 6: Add sandboxed-adapter test coverage**

In `Omnis/test/plugin_system_test.dart`, find the existing `SandboxedRatingsProvider`/`SandboxedThumbsProvider` test groups and add: a case confirming `preciseRatingOf` returns the int `ratingOf` value as a double, and cases confirming `setPreciseRating`/`setThumb` complete without throwing (asserting the no-op contract, not a behavior change) even when called against a fake runtime with no matching guest hook.

- [ ] **Step 7: Verify and commit**

Run `flutter analyze` and `flutter test` in both repos. Commit.

---

### Task 4: `IRingtoneProvider` — new interface, convert `library_page.dart`'s Ringtone reach

**Files:**
- Modify: `Omnis/packages/omnis_plugin_api/lib/service_interfaces.dart` (new interface, append at end of file)
- Modify: `Omnis-Plugins/lib/ringtone_plugin.dart` (add `implements IRingtoneProvider` to the class declaration at line 33 — no method-body changes needed, it already has both members)
- Modify: `Omnis/lib/ui/library_page.dart` (lines 1522-1535)
- Test: `Omnis-Plugins/test/ringtone_plugin_test.dart` (add one assertion)

**Interfaces:**
- Consumes: `RingtonePlugin.setAsRingtone(BaseTrack track) -> Future<bool>` (`Omnis-Plugins/lib/ringtone_plugin.dart:48`) and `RingtonePlugin.lastError -> String?` (a mutable field, line 34) — both already exist, unchanged.
- Produces: `IRingtoneProvider.setAsRingtone`, `IRingtoneProvider.lastError`.

This is the simplest task in this plan: no existing implementer besides `RingtonePlugin`, and no other file references it — a from-scratch interface addition with a single call site to convert, matching the spec's own "small, from-scratch addition" note for T1.5.

- [ ] **Step 1: Add `IRingtoneProvider`**

Append to `service_interfaces.dart` (after `IRadioProvider`, at the end of the file):

```dart

/// Sets a track as the device ringtone. Implemented by `RingtonePlugin` —
/// registered under this interface, not the concrete type, the same
/// "ask for the capability, not the plugin" pattern every interface in
/// this file follows.
abstract class IRingtoneProvider {
  /// Attempts to set [track] as the device ringtone. Returns `true` on
  /// success. Never throws — see [lastError] for a user-facing reason on
  /// failure (unsupported platform, no local file, a platform-level
  /// error), matching `RingtonePlugin.setAsRingtone`'s own convention.
  Future<bool> setAsRingtone(BaseTrack track);

  /// A user-facing description of why the most recent [setAsRingtone]
  /// call failed, or `null` if the most recent call succeeded (or none
  /// has been made yet).
  String? get lastError;
}
```

- [ ] **Step 2: Declare the interface on `RingtonePlugin`**

In `Omnis-Plugins/lib/ringtone_plugin.dart`, change the class declaration at line 33 from:

```dart
class RingtonePlugin extends MusicPlugin {
```

to:

```dart
class RingtonePlugin extends MusicPlugin implements IRingtoneProvider {
```

Add `import 'package:omnis_plugin_api/service_interfaces.dart';` at the top of the file if not already present (check first — many bundled plugins already import it for other interfaces).

- [ ] **Step 3: Register the provided service**

Bundled plugins register their own `ServiceRegistry` capabilities directly (unlike a downloadable plugin's manifest-gated `provides:` path) — check how a comparable already-converted bundled plugin registers itself. Read `Omnis-Plugins/lib/radio_plugin.dart`'s `initialize()`/`enable()`/`disable()` overrides (added in Tier 0's Task 4/5) for the exact pattern: registering `this` under the interface type in `initialize()` and `enable()`, unregistering in `disable()`. Apply the identical pattern to `RingtonePlugin`, registering under `IRingtoneProvider`.

- [ ] **Step 4: Convert the `library_page.dart` call site**

Replace (currently lines 1522-1523):

```dart
  RingtonePlugin? get _ringtonePlugin =>
      widget.pluginManager.bundled<RingtonePlugin>(onlyEnabled: true);
```

with:

```dart
  IRingtoneProvider? get _ringtoneProvider =>
      widget.pluginManager.services.get<IRingtoneProvider>();
```

Update the one call site in `_setAsRingtone` (currently lines 1525-1535): `final plugin = _ringtonePlugin;` → `final plugin = _ringtoneProvider;`. The rest of that method (`plugin.setAsRingtone(track)`, `plugin.lastError`) needs no further change.

Remove the now-unused `import 'package:omnis_plugins/ringtone_plugin.dart';` from `library_page.dart` if nothing else in the file references `RingtonePlugin` by concrete type.

- [ ] **Step 5: Add plugin-side test coverage**

In `Omnis-Plugins/test/ringtone_plugin_test.dart`, add:

```dart
test('RingtonePlugin satisfies IRingtoneProvider', () {
  final plugin = RingtonePlugin();
  expect(plugin, isA<IRingtoneProvider>());
});
```

Also add/adapt a test confirming `initialize()` registers the plugin under `IRingtoneProvider` on a real or fake `ServiceRegistry`/`PluginContext` — copy the equivalent test from `Omnis-Plugins/test/radio_plugin_test.dart` (Tier 0 added this exact pattern for `IRadioProvider`) and adapt it.

- [ ] **Step 6: Verify and commit**

Run `flutter analyze` and `flutter test` in both repos. Commit.

---

### Task 5: `ITagWriter` — new interface + moved value types, convert `library_page.dart`'s Tag Editor reach

**This is the largest and highest-risk task in this plan** — the spec's own T1.4 flagged it "Higher risk," and investigation for this plan found the real surface is bigger than the spec assumed: `TagEditorPlugin`'s existing `IFileTagWriter` interface only covers `writeLyrics` (one narrow method), while `library_page.dart` and `Omnis/lib/ui/tag_editor_dialog.dart` between them call four other methods (`writeTags`, `readTags`, `wasAutoTagged`, `undoLastEdit`) and `readTags` returns a plugin-owned value type (`TrackTags`, wrapping `List<TagFrame>`) that must become portable before an interface can return it.

**Files:**
- Create: `Omnis/packages/omnis_plugin_api/lib/track_tags.dart` (moved `CustomTagKeys`, `TagFrame`, `TrackTags` — see Step 1 for exact exclusions)
- Modify: `Omnis/packages/omnis_plugin_api/lib/service_interfaces.dart` (new `ITagWriter` interface, append at end)
- Modify: `Omnis-Plugins/lib/tag_editor_plugin.dart` (remove the moved classes, import them from the api package instead, add `implements ITagWriter` alongside the existing `implements IFileTagWriter`)
- Modify: `Omnis/lib/ui/library_page.dart` (8 call sites: lines 641, 806, 970, 1519-1520, 1736, 1884, 2050, 2082, 2189)
- Modify: `Omnis/lib/ui/tag_editor_dialog.dart` (constructor/`show()` signature, `_plugin` getter type)
- Test: `Omnis-Plugins/test/tag_editor_plugin_test.dart` (verify existing tests still pass against the moved types — they should need only import changes, no logic changes; add one `isA<ITagWriter>()` assertion)

**Interfaces:**
- Consumes: `TagEditorPlugin.writeTags(...)`, `.readTags(...)`, `.wasAutoTagged(...)`, `.undoLastEdit(...)` — all already exist at `Omnis-Plugins/lib/tag_editor_plugin.dart` (lines 440, 341, 664, 302 respectively) with the exact signatures reproduced in Step 3 below.
- Produces: `ITagWriter` (all four methods), plus the moved `CustomTagKeys`/`TagFrame`/`TrackTags` types, now importable from `package:omnis_plugin_api/track_tags.dart`.

- [ ] **Step 1: Move `CustomTagKeys`, `TagFrame`, `TrackTags` into `omnis_plugin_api`**

Read `Omnis-Plugins/lib/tag_editor_plugin.dart` lines 1-230 in full first (it has more of `TrackTags` than reproduced below — a `replayGainValues` getter and possibly more after it; read to the end of the `TrackTags` class to get everything). Confirm every member of `TrackTags`/`TagFrame`/`CustomTagKeys` depends only on: `dart:typed_data` (`Uint8List`), plain Dart, and (for `replayGainValues`, if present) a `ReplayGainValues` type — check where `ReplayGainValues` is defined (likely already in `packages/omnis_plugin_api/lib/base_track.dart`, since `BaseTrack.replayGain` uses it per the existing dartdoc at `TrackTags.replayGainValues`) and import it from there rather than redefining it.

Create `Omnis/packages/omnis_plugin_api/lib/track_tags.dart` containing exactly the `CustomTagKeys`, `TagFrame`, and `TrackTags` class definitions, moved verbatim (including their existing dartdoc comments) from `tag_editor_plugin.dart`, with imports adjusted (`dart:typed_data`, and `package:omnis_plugin_api/base_track.dart` if `ReplayGainValues` lives there).

In `Omnis-Plugins/lib/tag_editor_plugin.dart`: delete the three moved class definitions, add `import 'package:omnis_plugin_api/track_tags.dart';` at the top. Every remaining reference to `TagFrame`/`TrackTags`/`CustomTagKeys` in that file (its own internals use them extensively — `writeTags`'s body, `readTags`'s body) needs no change beyond the import, since the types are identical, just relocated.

In `Omnis/lib/ui/tag_editor_dialog.dart`: the file currently has no direct import of `tag_editor_plugin.dart` for these types (it gets them transitively) — check whether it references `TagFrame` directly (it does: `List<TagFrame> _otherFrames = const [];`). Add `import 'package:omnis_plugin_api/track_tags.dart';` there too once the concrete-plugin import is removed in Step 5 below.

- [ ] **Step 2: Read `writeTags`'s and `readTags`'s exact current signatures**

Before writing the interface, re-read `Omnis-Plugins/lib/tag_editor_plugin.dart`'s current `writeTags` (around line 440) and `readTags` (around line 341) in full — this plan reproduces `writeTags`'s signature below exactly as read during planning, but confirm it hasn't drifted, and get `readTags`'s exact signature (this plan did not capture its full body, only its declaration line: `Future<TrackTags> readTags(String filePath, {bool includeArtwork = true}) async {`).

- [ ] **Step 3: Add `ITagWriter`**

Append to `service_interfaces.dart` (add `import 'package:omnis_plugin_api/track_tags.dart';` at the top of the file alongside its existing imports):

```dart

/// Reads and writes every tag field a local audio file supports — the
/// broader read/write surface `IFileTagWriter` deliberately doesn't
/// cover (that interface is scoped to one narrow write, `writeLyrics`,
/// for a different caller — see its own doc comment). Implemented by
/// `TagEditorPlugin` alongside `IFileTagWriter`; both interfaces exist
/// independently because they serve different callers with different
/// needs, not because one supersedes the other.
abstract class ITagWriter {
  /// Writes any subset of the given fields into [filePath]'s own tags —
  /// every parameter left `null` is left unchanged in the file. Returns
  /// `true` on success. Never throws — an unreadable/unwritable file, or
  /// an unsupported platform, returns `false`.
  Future<bool> writeTags(
    String filePath, {
    String? title,
    String? artist,
    String? album,
    String? albumArtist,
    String? genre,
    String? year,
    String? track,
    String? disc,
    String? composer,
    String? comment,
    String? bpm,
    String? initialKey,
    String? mood,
    Uint8List? artworkBytes,
    Map<String, String>? extraFields,
  });

  /// Reads every tag from [filePath], as both flattened raw frames (for
  /// a "show everything" editor UI) and the convenience getters
  /// `TrackTags` exposes for the fields `BaseTrack` understands
  /// directly. Set [includeArtwork] to `false` to skip decoding the
  /// (potentially large) artwork frame when only text fields are needed.
  Future<TrackTags> readTags(String filePath, {bool includeArtwork = true});

  /// Whether [trackId] has already been auto-tagged in a previous batch
  /// run — lets a caller skip re-processing on repeat runs.
  bool wasAutoTagged(String trackId);

  /// Restores [filePath] to the tag values it had immediately before the
  /// most recent [writeTags] call that touched it (the snapshot
  /// [writeTags] itself records on every successful write). Returns
  /// `true` on success, `false` if there is no snapshot for this file or
  /// the restore itself fails — never throws.
  Future<bool> undoLastEdit(String filePath);
}
```

Confirm the parameter list above still matches `writeTags`'s real signature after Step 2's re-read — if it has drifted, use the real one, not this plan's copy.

- [ ] **Step 4: Declare `ITagWriter` on `TagEditorPlugin`**

Change the class declaration at `tag_editor_plugin.dart:220` from:

```dart
class TagEditorPlugin extends MusicPlugin implements IFileTagWriter {
```

to:

```dart
class TagEditorPlugin extends MusicPlugin implements IFileTagWriter, ITagWriter {
```

No method bodies change — `TagEditorPlugin` already has real implementations of all four `ITagWriter` methods.

- [ ] **Step 5: Convert `library_page.dart`'s 8 call sites**

Replace the concrete-type getter (currently lines 1519-1520):

```dart
  TagEditorPlugin? get _tagEditorPlugin =>
      widget.pluginManager.bundled<TagEditorPlugin>(onlyEnabled: true);
```

with:

```dart
  ITagWriter? get _tagWriter =>
      widget.pluginManager.services.get<ITagWriter>();
```

Then, at each of the following lines, replace `final tagEditor = _tagEditorPlugin;` with `final tagEditor = _tagWriter;` — every one of these is a pure rename with **no other change**, since each surrounding method already only calls `tagEditor.writeTags(...)`, `.readTags(...)`, `.wasAutoTagged(...)`, or `.undoLastEdit(...)`, all now on the interface (confirmed by reading each method's full body during planning): lines 641 (`_lookupArtworkOnline`), 806 (`_lookupArtworkForAll`), 970 (`_writeAnalysisTagsToFile`), 1736 (`_editTags`), 1884 (`_autoTagLibrary`), 2050 (`_undoAutoTagBatch`), 2082 (`_findReplaceSelected`), 2189 (`_calculatedTagsSelected`).

The one call site that's more than a rename is inside `_editTags` (around line 1745): `TagEditorDialog.show(context, track, plugin: tagEditor)` — this compiles once Step 6 changes `TagEditorDialog`'s parameter type to `ITagWriter`, with no change needed at this call site itself (a `tagEditor` of static type `ITagWriter?` — already null-checked earlier in the method — passes straight through).

Grep the file for `_tagEditorPlugin` after these edits to confirm zero references remain, then remove `import 'package:omnis_plugins/tag_editor_plugin.dart';` from `library_page.dart`.

- [ ] **Step 6: Convert `TagEditorDialog`**

In `Omnis/lib/ui/tag_editor_dialog.dart`:
- Replace `import 'package:omnis_plugins/tag_editor_plugin.dart';` with `import 'package:omnis/plugin_api/service_interfaces.dart';` and `import 'package:omnis_plugin_api/track_tags.dart';` (check whether a `lib/plugin_api/track_tags.dart` shim should exist for consistency with the established re-export-shim convention — read `lib/plugin_api/service_interfaces.dart` to see the pattern, and add `lib/plugin_api/track_tags.dart` the same way if the convention calls for it).
- Change `final TagEditorPlugin plugin;` (line 16) to `final ITagWriter plugin;`.
- Change `required TagEditorPlugin plugin,` (line 28, in `show()`) to `required ITagWriter plugin,`.
- Change `TagEditorPlugin get _plugin => widget.plugin;` (line 60) to `ITagWriter get _plugin => widget.plugin;`.

Read the rest of the file (it's a `StatefulWidget` with real form-editing logic reading/writing `TrackFrame`/`TrackTags` fields) to confirm no other member reference needs a concrete `TagEditorPlugin`-specific type — everything it calls on `_plugin` should now resolve through `ITagWriter` given the four methods just added.

- [ ] **Step 7: Verify existing tag-editor tests still pass**

`Omnis-Plugins/test/tag_editor_plugin_test.dart` tests the plugin directly by concrete type — it should require no logic changes, only picking up the moved `TrackTags`/`TagFrame`/`CustomTagKeys` from their new import location if the test file references them directly (check). Add:

```dart
test('TagEditorPlugin satisfies ITagWriter', () {
  final plugin = TagEditorPlugin();
  expect(plugin, isA<ITagWriter>());
});
```

matching the existing file's constructor/setup pattern.

Check whether any widget test exists for `tag_editor_dialog.dart` (`grep -rln "TagEditorDialog" Omnis/test/`) — if one does, it constructs a `TagEditorDialog` directly and will need its `plugin:` argument's static type to satisfy `ITagWriter` (a real `TagEditorPlugin` instance already does, no test logic change needed, just confirm it still compiles).

- [ ] **Step 8: Verify and commit**

Run `flutter analyze` and `flutter test` in both repos. This task touches the most files in this plan — read every analyzer error fully before fixing, since a missed reference to the old `tag_editor_plugin.dart`-local `TrackTags`/`TagFrame` types elsewhere in either repo (search both repos with `grep -rln "TrackTags\|TagFrame" --include=*.dart` before declaring done) will surface as an import/type-mismatch error, not a silent bug. Commit.

---

### Task 6: `ISmartPlaylistProvider` + moved rule types — convert `playlist_page.dart`'s Smart Playlist reach

**Files:**
- Create: `Omnis/packages/omnis_plugin_api/lib/smart_playlist_rule.dart` (moved `RuleField`, `RuleOperator`, `RuleMatchType`, `RuleCondition`, `SmartPlaylistRule` — verbatim move, see Step 1)
- Modify: `Omnis/packages/omnis_plugin_api/lib/service_interfaces.dart` (new `ISmartPlaylistProvider`, append at end)
- Modify: `Omnis-Plugins/lib/smart_playlist_plugin.dart` (import the moved file instead of the local one; add `implements ISmartPlaylistProvider` alongside existing `implements IQueueBuilder`)
- Modify: `Omnis-Plugins/test/smart_playlist_plugin_edit_test.dart`, `test/smart_playlist_plugin_test.dart`, `test/smart_playlist_rule_test.dart` (import path only)
- Delete: `Omnis-Plugins/lib/smart_playlist_rule.dart` (superseded by the moved copy)
- Modify: `Omnis/lib/ui/playlist_page.dart` (lines 86-87, 1041-1042, 978-1011)

**Interfaces:**
- Consumes: `SmartPlaylistPlugin.savedRules -> List<SmartPlaylistRule>` (`Omnis-Plugins/lib/smart_playlist_plugin.dart:60`), `.buildQueueForRule(List<BaseTrack>, String) -> List<BaseTrack>` (called at `playlist_page.dart:980`, exact signature not yet read — re-read before writing the interface method, see Step 2), `.deleteRule(String) -> Future<void>` (called at `playlist_page.dart:991`, same caveat) — all already exist, unchanged.
- Produces: `ISmartPlaylistProvider` (three methods below), plus the moved rule types importable from `package:omnis_plugin_api/smart_playlist_rule.dart`.

- [ ] **Step 1: Move `smart_playlist_rule.dart` into `omnis_plugin_api`**

`Omnis-Plugins/lib/smart_playlist_rule.dart` already imports only `package:omnis_plugin_api/base_track.dart` and `package:omnis_plugin_api/service_interfaces.dart` (confirmed by reading the file during planning) — it has no dependency on anything else in the Omnis-Plugins repo, making it a clean verbatim move.

Copy the entire file (all of `RuleField`, `RuleOperator`, `RuleMatchType`, `RuleCondition`, `SmartPlaylistRule`, including the private `_firstWhereOrNull` helper and every dartdoc comment) to `Omnis/packages/omnis_plugin_api/lib/smart_playlist_rule.dart`, unchanged.

Delete `Omnis-Plugins/lib/smart_playlist_rule.dart`.

In `Omnis-Plugins/lib/smart_playlist_plugin.dart`, replace whatever local import it currently has for that file (check the exact current import line — likely `import 'smart_playlist_rule.dart';` or `import 'package:omnis_plugins/smart_playlist_rule.dart';`) with `import 'package:omnis_plugin_api/smart_playlist_rule.dart';`.

In `Omnis-Plugins/test/smart_playlist_plugin_edit_test.dart`, `test/smart_playlist_plugin_test.dart`, and `test/smart_playlist_rule_test.dart`, make the same import-path change (check each file's current import line first — do not assume all three import it the same way).

- [ ] **Step 2: Read `buildQueueForRule`'s and `deleteRule`'s exact signatures**

Read `Omnis-Plugins/lib/smart_playlist_plugin.dart` in full for the real signatures of `buildQueueForRule` and `deleteRule` (this plan only observed their call sites, not their declarations) before writing the interface in Step 3 — use what you find there, not a guess.

- [ ] **Step 3: Add `ISmartPlaylistProvider`**

Append to `service_interfaces.dart` (add `import 'package:omnis_plugin_api/smart_playlist_rule.dart';` at the top):

```dart

/// Reads and plays a user's saved rule-based smart playlists —
/// distinct from [IQueueBuilder] (which `SmartPlaylistPlugin` also
/// implements): that interface matches a *query name* like a mood label
/// against curated `BaseTrack.mood` tags, while this interface plays a
/// specific *saved rule* the user built and named through the plugin's
/// own settings UI. Implemented by `SmartPlaylistPlugin`.
abstract class ISmartPlaylistProvider {
  /// Every rule the user has saved, in no particular guaranteed order —
  /// a caller displaying them decides its own ordering (today,
  /// insertion/save order).
  List<SmartPlaylistRule> get savedRules;

  /// Builds a ready-to-play queue by evaluating the saved rule
  /// [ruleId] against [tracks]. Returns an empty list if no rule with
  /// that id is saved, or if the rule genuinely matches nothing — never
  /// throws.
  List<BaseTrack> buildQueueForRule(List<BaseTrack> tracks, String ruleId);

  /// Deletes the saved rule [ruleId]. A no-op — not an error — if no
  /// rule with that id exists.
  Future<void> deleteRule(String ruleId);
}
```

Use the exact parameter/return types you found in Step 2 for `buildQueueForRule`/`deleteRule` if they differ from what's shown here.

- [ ] **Step 4: Declare `ISmartPlaylistProvider` on `SmartPlaylistPlugin`**

Change the class declaration in `smart_playlist_plugin.dart` from:

```dart
class SmartPlaylistPlugin extends MusicPlugin implements IQueueBuilder {
```

to:

```dart
class SmartPlaylistPlugin extends MusicPlugin implements IQueueBuilder, ISmartPlaylistProvider {
```

No method bodies change — the plugin already has real implementations of all three.

- [ ] **Step 5: Convert `playlist_page.dart`'s call sites**

Replace the concrete-type getter (currently lines 86-87):

```dart
  SmartPlaylistPlugin? get _smartPlaylists =>
      widget.pluginManager.bundled<SmartPlaylistPlugin>(onlyEnabled: true);
```

with:

```dart
  ISmartPlaylistProvider? get _smartPlaylists =>
      widget.pluginManager.services.get<ISmartPlaylistProvider>();
```

(Keeping the same getter name `_smartPlaylists` here, unlike other tasks in this plan — every downstream reference in this file already treats it as a nullable "the provider, if any" value with no concrete-type-specific member access, confirmed by re-reading `_buildIndex` at line 1041-1042 and `_playSmartPlaylist`/`_deleteSmartPlaylist`/`_manageSmartPlaylists` at lines 978-1011 during planning — a rename isn't needed for clarity the way `_ratingsPlugin` → `_ratingsProvider`/`_thumbsProvider` needed one in Task 3, since this one splits into zero new getters.)

The parameter types on `_playSmartPlaylist(SmartPlaylistPlugin plugin, ...)` (line 978-979) and `_deleteSmartPlaylist(SmartPlaylistPlugin plugin, ...)` (line 989-990) must also change from `SmartPlaylistPlugin` to `ISmartPlaylistProvider` — both are private methods only called from within this file (lines 1160, 1163), passing `smartPlaylistPlugin` (the local variable at line 1041, itself now typed `ISmartPlaylistProvider?`, narrowed non-null by the `if (smartPlaylistPlugin != null)` check at line 1127 before either call site is reached).

Grep the file for `SmartPlaylistPlugin` after these edits to confirm the only remaining reference (if any) is intentional, then remove `import 'package:omnis_plugins/smart_playlist_plugin.dart';` if nothing else needs it. The existing `import 'package:omnis_plugins/smart_playlist_rule.dart';` also needs removing/replacing with `import 'package:omnis_plugin_api/smart_playlist_rule.dart';` (since `SmartPlaylistRule` is referenced directly at lines 1011, 1042, 1149, 1153, 1155 for display).

- [ ] **Step 6: Verify and commit**

Run `flutter analyze` and `flutter test` in both repos. Commit.

---

### Task 7: Drop the concrete-type checks in `online_page.dart` — no new interface needed

**Files:**
- Modify: `Omnis/lib/ui/online_page.dart` (lines 67-77)

**Interfaces:** None produced or consumed — this task removes a concrete-type reach without replacing it with an interface, because investigation during planning found the reach was never actually about a capability: `_youtubePlaybackManaged`/`_spotifyPlaybackManaged` only ever use the concrete type to answer "is this specific plugin currently enabled," then immediately discard it and re-fetch the same plugin by id via `pluginManager.byId(...)` (already id-based, already concrete-type-free) to render its existing `uiSlot('plugin_settings')` widget. `ManagedPlugin.enabled` (`Omnis/lib/core/plugin_manager.dart:59`) already answers "is this plugin enabled" generically, keyed by id string — no interface needed at all.

- [ ] **Step 1: Convert the two getters**

Replace (currently lines 67-77):

```dart
  ManagedPlugin? get _youtubePlaybackManaged =>
      widget.pluginManager.bundled<YoutubePlaybackPlugin>(onlyEnabled: true) ==
              null
          ? null
          : widget.pluginManager.byId('youtube_playback');

  ManagedPlugin? get _spotifyPlaybackManaged =>
      widget.pluginManager.bundled<SpotifyPlaybackPlugin>(onlyEnabled: true) ==
              null
          ? null
          : widget.pluginManager.byId('spotify_playback');
```

with:

```dart
  ManagedPlugin? get _youtubePlaybackManaged {
    final managed = widget.pluginManager.byId('youtube_playback');
    return managed != null && managed.enabled ? managed : null;
  }

  ManagedPlugin? get _spotifyPlaybackManaged {
    final managed = widget.pluginManager.byId('spotify_playback');
    return managed != null && managed.enabled ? managed : null;
  }
```

The plugin ids `'youtube_playback'` and `'spotify_playback'` are confirmed exact matches for `YoutubePlaybackPlugin.id` (`Omnis-Plugins/lib/youtube_playback_plugin.dart:77`) and `SpotifyPlaybackPlugin.id` (`Omnis-Plugins/lib/spotify_playback_plugin.dart:199`) — read during planning, not guessed.

- [ ] **Step 2: Remove the now-unused imports**

Remove `import 'package:omnis_plugins/spotify_playback_plugin.dart';` and `import 'package:omnis_plugins/youtube_playback_plugin.dart';` from `online_page.dart` (currently lines 8-9) — grep the rest of the file first to confirm neither concrete type is referenced anywhere else in it (it shouldn't be; every other use of these two sections works through the `ManagedPlugin`/`_OnlineSection` abstraction already).

- [ ] **Step 3: Verify existing behavior is unchanged**

Read `Omnis/test/online_page_test.dart` for any existing test covering the YouTube/Spotify sections' visibility toggling (enabled vs. disabled) — if one exists, it should continue to pass unchanged, since `ManagedPlugin.enabled` is exactly the same boolean `bundled<X>(onlyEnabled: true) == null` was already checking (that helper's own `onlyEnabled: true` parameter filters on this same `enabled` field internally — confirm this by reading `PluginManager.bundled`'s implementation before finalizing, so the new getters are provably behavior-identical, not just plausibly so).

If no such test exists, add one to `online_page_test.dart` matching that file's existing setup pattern: enable the YouTube plugin, confirm its section appears; disable it, confirm the section disappears — using whatever fake/real `PluginManager` setup the file's other tests already use.

- [ ] **Step 4: Verify and commit**

Run `flutter analyze` and `flutter test` in Omnis (this task touches only that repo). Commit.

---

### Task 8: Cross-repo dependency pin bump

**Files:**
- Modify: `Omnis/pubspec.yaml` (the `omnis_plugins:` ref, currently `v0.48.0`)
- Modify: `Omnis-Plugins/pubspec.yaml` (the `omnis_plugin_api:` ref, currently `plugin-api-v0.26.0`) — only if Tasks 1-7 didn't already require bumping it mid-plan (they don't: this plan's Global Constraints deliberately defer every pin bump to this one task)

**Interfaces:** None — this task only changes version pins, no code.

Tier 0's C1 finding and its fix wave (see `Omnis-Plugins/docs/VERSIONING.md`) established the exact ordering this task must follow, and why: a tag cut before its own dependent pin-bump commit lands still points at the old pin, which is invisible under the local `pubspec_overrides.yaml` sibling-checkout path but breaks a clean checkout outright.

- [ ] **Step 1: Bump Omnis-Plugins' own `omnis_plugin_api` pin, if needed**

If any task above added new `omnis_plugin_api` package content that Omnis-Plugins now imports (every task in this plan does: `track_tags.dart`, `smart_playlist_rule.dart`, and every `service_interfaces.dart` addition) — cut a new `plugin-api-vX.Y.Z` tag at Omnis's current HEAD (after Tasks 1-7's commits are all in) and push it, then bump the `ref:` in `Omnis-Plugins/pubspec.yaml` to that tag, in its own commit. Run `flutter analyze`/`flutter test` in Omnis-Plugins against a fresh `flutter pub get` with `pubspec_overrides.yaml` temporarily renamed aside (to force real tag resolution, not the sibling-checkout override) before trusting this step — this is exactly the check Tier 0's C1 fix wave found the brief's own local-`pub get`-only verification couldn't catch.

- [ ] **Step 2: Cut Omnis-Plugins' own release tag**

Only after Step 1's commit (if any) is the tip of Omnis-Plugins' `main` — cut a new `vX.Y.Z` tag there and push it.

- [ ] **Step 3: Bump Omnis's `omnis_plugins` pin**

In `Omnis/pubspec.yaml`, bump the `omnis_plugins:` ref to the tag cut in Step 2. Run `flutter analyze`/`flutter test` in Omnis, again with `pubspec_overrides.yaml` temporarily renamed aside first, to prove the real tag resolves cleanly.

- [ ] **Step 4: Restore local override files and do a final full-suite check**

Confirm `pubspec_overrides.yaml` (renamed aside in Steps 1/3) is restored in both repos, run `flutter pub get` in both, then `flutter analyze` + `flutter test` in both one final time in their normal local-override configuration. Commit the pin bump(s).

---

## After This Plan

Five of the seven `pluginManager.bundled<XPlugin>(onlyEnabled: true)` reaches named in the spec's Part 1D are now fully gone (Lyrics, Ratings, Ringtone, YouTube/Spotify, SmartPlaylist). Two are deliberately partial, not oversights:

- **Metadata** (`library_page.dart`'s `_enrichmentPlugin` getter): one concrete-type reach remains, scoped to a single UI hint (`hasAnyCredential`) that's genuinely provider-specific and was never a candidate for the interface — see the getter's own doc comment.
- **Tag Editor** (`library_page.dart`'s `_tagEditorPlugin` getter): five call sites remain concrete because they call `splitArtists`/`cleanArtistFields`/`wasAutoTagged`/`markAutoTagged` — artist-name-cleanup heuristics and auto-tag bookkeeping, not tag I/O, and not part of `ITagWriter`'s scope. A future cleanup-scoped interface (`ITagCleanup` or similar) covering these, plus `media_scanner.dart`'s own concrete `TagEditorPlugin` constructor parameter, is real, separate work — not attempted here. See that getter's own doc comment for the full accounting.

Tier 2 (moving whole tabs — Home dashboard, Moods, Radio+Online — into plugins via the `PluginDestination` mechanism Tier 0 built) becomes startable; it depends on T0.2 (done) and, for the Radio+Online extraction specifically, on this plan's Task 7 (done) per the spec's T2.3 note. Tier 2 needs its own implementation plan, written separately once this one is verified working end-to-end — same reasoning Tier 0's own plan gave for not pre-writing Tier 1 until Tier 0 landed.
