# Tier 2 Completion Report — Core/Plugin Re-architecture

> Status: **Done.** All 6 tasks landed, reviewed, fixed, re-reviewed, and
> verified from a clean checkout (no local sibling-path overrides) in
> both repos. This document is the durable record — the working ledger
> it's drawn from (`.superpowers/sdd/2026-08-24-core-plugin-tier2/`) is
> git-ignored scratch and will eventually be cleared.

**Plan:** [docs/superpowers/plans/2026-08-24-core-plugin-tier2.md](superpowers/plans/2026-08-24-core-plugin-tier2.md)
**Spec:** [docs/superpowers/specs/2026-08-22-core-plugin-rearchitecture-plan.md](superpowers/specs/2026-08-22-core-plugin-rearchitecture-plan.md) (Part 3, Tier 2)
**Dates:** 2026-08-24 through 2026-08-26

## What changed

Three UI subsystems that used to be hardcoded into the Omnis app —
**Home dashboard**, **Moods** (+ mood builder, custom moods, forgotten
music), and **Radio+Online** — are now bundled plugins living in the
sibling Omnis-Plugins repo, contributing their tab via the
`PluginDestination` mechanism instead of being permanent `home_page.dart`
tabs. A plugin-less install now shows exactly three core tabs: **Library,
Playlist, Settings**. Each extracted feature's tab appears only when its
plugin is installed and enabled.

To make removing a tab safe, the plan first added a **default launch
tab** setting (Settings → Controls & Gestures) — defaults to Library,
user-changeable to any currently-available destination, falling back
gracefully if the chosen one's plugin gets disabled later.

## The 6 tasks

| # | Task | Result |
|---|---|---|
| 1 | Default launch tab setting | Clean, no fix round |
| 2 | Sidebar drawer hardcoded-index bug fix | Clean, no fix round |
| 3 | Extract Home dashboard | 2 fix rounds (a test-authoring bug; a cache-removal flicker regression) |
| 4 | Extract Moods cluster | Clean, no fix round — biggest task, approved first pass |
| 5 | Extract Radio+Online | 1 fix round (a cross-cutting data reach that needed a capability interface, not a direct import) |
| 6 | Cross-repo pin bump | Mechanical, verified with local overrides removed |

Every task went through the full loop: implementer → task reviewer →
(fix round + scoped re-review, if findings) → next task. After all 6,
a **final whole-branch review** (a broader pass looking for problems
only visible in aggregate) found several small issues; one fix wave
resolved them, one scoped re-review confirmed clean, and one more
mechanical pin bump (new tag, cut after the fix wave) closed a gap the
fix wave itself introduced (a plugin API signature change that landed
after the previous tag).

**Net result:** 10 commits in Omnis, 8 commits in Omnis-Plugins, 4 new
git tags (`plugin-api-v0.29.0`, `plugin-api-v0.30.0`, `v0.51.0`,
`v0.52.0`), all pushed to `main` in both repos.

## What a real crash-recovery looked like

Two implementer sessions crashed mid-task (Claude session limits) during
Task 3 and once during Task 5, always leaving real, mostly-correct
uncommitted work behind rather than nothing. Each time, the recovering
session audited the leftover state against the task's brief before
deciding to keep it (rather than discarding and redoing from scratch) —
this worked because the SDD ledger + a fresh `git status`/`git diff`
gave enough context to assess "is this actually right" without having
witnessed the crashed session's own reasoning. Nothing was lost.

## Verification

- `flutter analyze`: clean in both repos, every task, every fix round.
- `flutter test`: clean in both repos, every task, every fix round.
  Final counts: **Omnis 1716 passing, Omnis-Plugins 782 passing.**
- **Clean-checkout verification** (the real test of Task 6 and the final
  pin bump): with `pubspec_overrides.yaml` temporarily removed in both
  repos — forcing real git-tag resolution instead of the local
  sibling-checkout dev shortcut — `pub get`, `analyze`, and the full test
  suite all passed clean in both repos, twice (once after Task 6, once
  again after the final-review fix wave needed a follow-up tag). A fresh
  clone of either repo today builds correctly.
- A debug APK was built successfully from the final state
  (`flutter build apk --debug`, then `--split-per-abi`) — the app
  compiles and packages correctly end-to-end.

## Notable engineering decisions (rulings made along the way)

These were judgment calls made without stopping to ask, each documented
in the ledger at the time:

1. **`IHomeCustomizer`/`IMoodPlayer`/`ICustomRadioStationProvider`** — a
   new capability interface per extracted plugin, added to
   `packages/omnis_plugin_api/lib/service_interfaces.dart`, is the
   established replacement for "the app reaches into a plugin's mounted
   widget via `GlobalKey`" (impossible once the widget is plugin-owned).
   `IMoodPlayer` grew a third member (`customMoods`) beyond its original
   two, because the sidebar drawer needed the actual custom-mood list,
   not just "play one by name" — verified independently by task review
   as load-bearing, not a shortcut.
2. **Value types that a capability interface's signature needs move to
   `omnis_plugin_api`; their store/implementation stays in
   Omnis-Plugins.** `CustomMood`, `TrackPlayStats` both followed this
   split, matching the Tier 1 precedent (`track_tags.dart`,
   `smart_playlist_rule.dart`).
3. **Some files got duplicated, not moved**, when the app still needs
   them but the cross-repo dependency isn't reachable yet
   (`track_artwork.dart`, `schema_versioning.dart`,
   `reorder_menu_button.dart`, `color_picker_dialog.dart`). One of
   these, `track_artwork.dart`, later became *intentionally* different
   (not just duplicated) — the app's copy keeps a process-global cache,
   the plugin's copy uses per-`State` memoization instead, because a
   process-global cache doesn't get invalidated by the plugin's own
   internal reach.
4. **All cross-repo dependency pin bumps were batched to the end**
   (Task 6, plus one follow-up), never done per-task — cutting a tag
   before its own dependent commit lands is invisible locally (under
   `pubspec_overrides.yaml`) but breaks a clean checkout. This lesson
   was already learned by prior plans this session and held throughout.
5. **Push after every task completes**, not batched — an explicit
   standing instruction set partway through this plan.

## Real bugs caught and fixed by review (not just style nits)

- **Task 3, fix round 1:** two new tests failed for a deeper reason than
  first suspected — the command palette dialog wasn't opening at all,
  due to a real (pre-existing, unrelated to this plan) focus-dispatch
  quirk in `GlobalKeyboardShortcuts`. Worked around test-side per
  instructions (production fix out of scope), documented as a follow-up.
- **Task 3, fix round 2:** fixing artwork-cache staleness by simply
  removing the cache caused a *worse* regression — visible flicker on
  every dashboard rebuild (which happens on every track change). Fixed
  properly with per-track-id memoization in `State`.
- **Task 5, fix round 1:** an app-side reach into a plugin-owned store
  used a direct concrete import instead of a capability interface —
  worked, but violated the plan's own binding architecture and made a
  core file's own doc comment ("deliberately knows no concrete plugin")
  false. Fixed by adding `ICustomRadioStationProvider`.
- **Final whole-branch review:** caught a real privacy-control bug
  (`OnlinePlugin.usesNetwork` returned `false` despite making real
  network calls), a UI ordering bug that only worked by accident of
  `Future` completion timing, and a narrow silent-data-loss window in
  `MoodsPlugin.customMoods` (pinned custom moods could read as
  empty/stale during a startup race) — all three fixed.

See [TIER2_RECOMMENDATIONS.md](TIER2_RECOMMENDATIONS.md) for what's
deliberately left open and what's recommended next.
