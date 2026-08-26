# Tier 2 Recommendations — What's Next

> Companion to [TIER2_COMPLETION.md](TIER2_COMPLETION.md). Everything
> here was deliberately deferred during Tier 2 (not forgotten — each
> item was ruled on and parked, not silently dropped) or surfaced by
> review but judged out of scope for a mechanical fix round. Nothing
> below blocks Tier 2 being done; these are the next things worth
> spending time on, roughly ordered by how much they matter.

## Product decisions worth making deliberately (not bugs — need a human call)

1. **Nav tab order changed as a side effect, not a design choice.**
   Core tabs (Library, Playlist, Settings) always render before
   plugin-contributed ones, so with the default bundled plugin set the
   order is now Library, Playlist, Settings, Home, Moods, Online —
   Settings sits in the middle of the feature tabs instead of last.
   Each extraction task individually just "appended one tab"; the
   aggregate result wasn't designed. Either accept it, or decide on a
   real ordering mechanism (`PluginDestination.order` only affects
   ordering *within* the plugin-contributed group, not relative to
   core).
2. **What should happen when a command-palette action targets a
   destination with no owning plugin installed?** Two places
   ("Customize home", a mood search result) currently `setState` the
   selected tab to the target id *before* checking whether anything
   handles it — with no plugin, this silently bounces the user to
   Library instead of staying where they were. Tested as a no-crash,
   but nobody decided if that's the right UX. Worth one consistent
   answer applied everywhere this pattern occurs.
3. **A capability interface for "push Now Playing after playback
   starts" doesn't exist yet.** Tapping a Home dashboard card or a Moods
   tile used to open Now Playing afterward; that's lost since neither
   page can reach `NowPlayingPage` from outside the app's own
   navigation stack. Both plugins document the gap. A `INowPlayingOpener`
   (or similar) capability interface, mirroring `IHomeCustomizer`'s
   shape, would restore it — real design work, not a mechanical fix.

## Real, if narrow, bugs worth fixing when convenient

4. **`GlobalKeyboardShortcuts`'s fallback focus anchor sits as an
   ancestor of `home_page.dart`'s own Ctrl+K/P/B `CallbackShortcuts`.**
   Confirmed genuinely pre-existing (predates Tier 2, untouched by it)
   and confirmed by two independent reviews. Key dispatch only walks
   upward from the focused node, so if the anchor is the sole focus
   holder — the exact state a fresh app launch leaves things in before
   the user clicks or tabs anything — Ctrl+K/P/B may not fire. No prior
   test exercised these shortcuts via full keyboard simulation, so this
   had no coverage either way before Tier 2's own tests started probing
   it. Worth its own small task: either reposition the anchor `Focus`
   widget, or fold Ctrl+K/P/B into `GlobalKeyboardShortcuts`' own
   bindings map.
5. **`_checkPlaybackSchedules` in `main_core.dart` has zero direct unit
   test coverage**, before or after Tier 2 — and Tier 5's fix round
   rewrote its radio-station-resolution branch to go through the new
   `ICustomRadioStationProvider` without adding coverage. The logic is
   simple and was verified by hand during review, but a real test would
   catch a future regression a manual read wouldn't.

## Cleanup, now genuinely possible (it wasn't, until Task 6 landed)

6. **Duplicated files are candidates for real consolidation now that
   both repos are pinned to tags that include each other's needed
   commits.** `schema_versioning.dart` and `reorder_menu_button.dart`
   are byte-identical duplicates between Omnis and Omnis-Plugins purely
   because of pin-bump sequencing during the extraction — that blocker
   is gone. `color_picker_dialog.dart` still has 3 real app-side callers
   so it can't simply be deleted app-side, but could become a single
   shared source with the app importing from Omnis-Plugins the same way
   `lib/plugin_api/custom_mood.dart` and `track_tags.dart` already do.
   **Exception:** `track_artwork.dart` is *not* a consolidation
   candidate — its two copies were made deliberately different (the
   app's has a process-global cache, the plugin's uses per-`State`
   memoization) to fix a real flicker bug, and merging them back would
   likely reintroduce it.
7. **`Omnis-Plugins/analysis_options.yaml` has no `include:` line** —
   `flutter_lints` is a declared dependency but its rules never actually
   run; only the built-in analyzer defaults apply. This is why an
   undeclared transitive test dependency (`flutter_secure_storage`)
   went uncaught until a whole-branch review found it by hand. Adding
   `include: package:flutter_lints/flutter.yaml` (matching the Omnis
   app's own config) is one line — but do it as its own small task, not
   bundled into anything else, since enabling a dormant lint set on a
   mature codebase for the first time can surface an unpredictable
   number of new warnings that need triaging.
8. **Three `OmnisIconCatalog` consts are now unreferenced app-side**
   (`.home`, `.mood`, and `.cloudQueue`) — don't delete them. The queued
   theme/layout/icon plugin system plan (see below) is likely to want
   them; check that plan before touching this file.

## Performance & responsiveness

You asked specifically that no user action feel slow or laggy. The
final whole-branch review did a directed check of this for everything
Tier 2 touched — comparing each moved page's rebuild behavior against
its pre-extraction original, not just reading the new code in
isolation. Verdict: **clean, no regression from the extraction itself.**
One real regression was caught and fixed mid-plan (Task 3's artwork-cache
flicker, see the completion report), and the fix was verified not to
have just traded one problem for another.

Two **pre-existing** costs were flagged as worth knowing about, since
they weren't introduced by Tier 2 but Tier 2 is a natural moment to note
them:

9. **`HomeDashboardPage` reloads on every track-start/track-change
   event**, and each reload does five uncached disk reads + JSON decodes
   (`PlayHistoryStore` has no in-memory cache; `HomeLayoutStore`
   re-reads and re-migrates its file on every call). Only the library
   read is cached. On a fast device this is probably imperceptible; on
   a slow one, especially with a large play-history file, it's the kind
   of thing that could show up as a stutter on every track change if
   the Home tab happens to be open. Worth a profiling pass before
   assuming it needs fixing — don't guess, measure.
10. If a broader performance pass is wanted beyond what Tier 2 touched,
    the natural next step is **profiling real user actions on a real
    device** (tab switches, library scans, search-as-you-type, playlist
    reordering) rather than a code-reading sweep — Flutter's DevTools
    timeline view will show actual frame times, which is a much more
    reliable signal than guessing from source. Nothing in this session
    surfaced a *specific* concrete slow path outside what's listed
    above; a real audit needs a device and real usage, not more static
    review.

## What's next in the broader plan

Two things were already queued before Tier 2 started:

- **The theme/layout/icon plugin system plan**
  ([docs/superpowers/plans/2026-08-24-theme-layout-icon-plugin-system.md](superpowers/plans/2026-08-24-theme-layout-icon-plugin-system.md))
  was explicitly waiting for Tier 2 to finish before its first task
  dispatches (both plans touch `service_interfaces.dart`/
  `bundled_plugins.dart`, and this session's rule was never running
  implementers for both plans at once). It can start now.
- **Tier 2's own plan document names T2.4** (moving Settings sub-pages
  behind `uiSlot('settings_page')` injection) as explicitly deferred —
  planning research during Tier 2 found the split isn't clean for
  several settings pages that mix core and plugin-candidate content
  (`accessibility_settings_page.dart`, `keyboard_settings_page.dart`,
  `playback_settings_page.dart`, `appearance_settings_page.dart`). It
  should be scoped as its own investigation, not assumed to be a simple
  file-by-file split.
- **Tier 3** (A/B loop+DJ tools, tag/organization, similarity,
  statistics, and the higher-risk `MainCore`-owned-timer extractions:
  queue continuation, playback scheduling, backup) and **Tier 4** (the
  downloadable-plugin declarative page DSL) remain unplanned, per the
  original architecture spec's own scoping — no implementation plan
  exists for either yet.

## Housekeeping

- `.superpowers/sdd/2026-08-24-core-plugin-tier2/` (the working ledger,
  briefs, reports, and review-diff artifacts this whole plan generated)
  is git-ignored scratch. Now that this document and
  [TIER2_COMPLETION.md](TIER2_COMPLETION.md) capture the durable record,
  that directory can be deleted at any time without losing anything —
  the git history and these two docs are the record now.
- [docs/HANDOFF.md](HANDOFF.md) should be updated to point at these two
  documents instead of the Tier 2 in-progress status it currently
  carries, once this session ends.
