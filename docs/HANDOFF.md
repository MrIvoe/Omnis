# Handoff — Read This First

> **Purpose:** this file is the entry point for any new chat session
> picking up work on Omnis/Omnis-Plugins. It orients you to what's
> running, what's broken, and where the real detail lives — it does not
> duplicate that detail. Update it at the end of every session (or when
> asked to "update the handoff") so the next session doesn't have to
> reconstruct state from scratch.

## Two repos, one system

- `c:\Users\MrIvo\Github\Omnis` — the app. Also owns
  `packages/omnis_plugin_api/`, the dependency-free contracts package
  both repos import.
- `c:\Users\MrIvo\Github\Omnis-Plugins` — bundled + downloadable plugins.
  Depends only on `omnis_plugin_api`, never on the Omnis app itself.
- Both repos are on `main`, no worktrees in use for current plans (an
  established consent recorded in each plan's Global Constraints — see
  below). Local dev resolves the cross-repo dependency via
  `pubspec_overrides.yaml` (sibling-checkout paths) in both repos — a
  clean clone without that override file resolves via the pinned git
  refs in `pubspec.yaml` instead.
- Flutter SDK on this machine: `C:\Users\MrIvo\flutter\bin\flutter.bat`
  (there's also one at `C:\src\flutter` — the `MrIvo` one is what's been
  used this session). Not on PATH in either Bash or PowerShell — invoke
  by full path.

## The workflow this project uses: Superpowers SDD

This codebase is being built via `superpowers:subagent-driven-development`
(the "SDD" workflow) — a controller session dispatches fresh implementer
subagents per task, reviews each, and tracks progress in a **ledger**
that survives context loss/compaction/session death better than chat
memory does.

**If you are picking this up cold, read in this order:**
0. For architecture and feature status, see `docs/vault/README.md`.
1. This file (top-level orientation).
2. `docs/OMNIS_2_0_STATUS.md` — feature-level "how much of the whole app
   is done" snapshot (50 tracked areas, ~72% as of last regen).
3. Whichever plan(s) are active (see "Active plans" below) — read the
   **plan file** for scope/architecture, then the plan's own **ledger**
   (`.superpowers/sdd/<plan-name>/progress.md`) for exactly which tasks
   are done, in-flight, or blocked. **Trust the ledger and `git log` over
   any chat's memory of what happened** — that's the whole point of the
   ledger.

Never re-derive "what's done" by reading source — the ledgers are
authoritative and cheaper to read.

## Status (as of 2026-08-26)

**Tier 2 (Home dashboard / Moods / Radio+Online extraction) is fully
complete.** All 6 tasks landed, reviewed, fixed, re-reviewed, and a
final whole-branch review + fix wave + follow-up pin bump closed
everything out — verified clean from a real clean checkout (no local
override) in both repos. See
[TIER2_COMPLETION.md](TIER2_COMPLETION.md) for the full record and
[TIER2_RECOMMENDATIONS.md](TIER2_RECOMMENDATIONS.md) for what's
deliberately left open and recommended next. The SDD ledger this was
tracked in (`.superpowers/sdd/2026-08-24-core-plugin-tier2/`) has served
its purpose — those two docs are the durable record now.

**Next up:** the theme/layout/icon plugin system plan (see "Active
plans" below) was waiting for Tier 2 to finish and can now start.

## Active plans (as of 2026-08-26)

1. **Core/Plugin Tier 2** — **done.** See "Status" above,
   [TIER2_COMPLETION.md](TIER2_COMPLETION.md), and
   [TIER2_RECOMMENDATIONS.md](TIER2_RECOMMENDATIONS.md).

2. **Theme/Layout/Icon plugin system** — let plugins contribute themes,
   Now Playing layouts, and icon artwork.
   - Plan: `docs/superpowers/plans/2026-08-24-theme-layout-icon-plugin-system.md`
   - Ledger: `.superpowers/sdd/2026-08-24-theme-layout-icon-plugin-system/progress.md`
   - Status: **Not started.** Was explicitly waiting for Tier 2 to
     finish (both plans touch `service_interfaces.dart`/
     `bundled_plugins.dart`) — that's no longer a blocker. Ready to
     start whenever picked up.

**Standing instruction for this repo pair:** push after every task
completes, not batched — an explicit standing rule set during Tier 2.
Also: batch all cross-repo dependency pin bumps into one clearly-labeled
task/step at the end of a plan, never per-task — a tag cut before its
own dependent commit lands is invisible locally (under
`pubspec_overrides.yaml`) but breaks a clean checkout. Learned the hard
way more than once before Tier 2 codified it; verify with
`pubspec_overrides.yaml` temporarily removed in both repos before
considering a pin bump done.

## Patterns established during Tier 2 (reuse, don't rediscover)

- Every extracted plugin follows `radio_plugin.dart`'s exact
  `ServiceRegistry` lifecycle (register in `initialize()`+`enable()`,
  unregister in `disable()`+`dispose()`) — verify against that file's
  *current* content each time, don't work from a paraphrase.
- A capability a UI call site needs from a plugin-owned page goes through
  a new interface in `packages/omnis_plugin_api/lib/service_interfaces.dart`
  + `pluginManager.services.get<T>()`, never a `GlobalKey` into a widget
  the app no longer constructs itself.
- A value type a capability interface's signature needs moves to
  `omnis_plugin_api`; its store/implementation stays in Omnis-Plugins
  (see `CustomMood`, `TrackPlayStats`).
- When the app still needs a file that moved to Omnis-Plugins and the
  cross-repo pin isn't bumped yet, duplicate it (with a doc comment
  explaining why) rather than block the extraction — but if the two
  copies later need to diverge on purpose (see `track_artwork.dart` in
  TIER2_COMPLETION.md), say so explicitly so nobody "helpfully"
  reconsolidates them later.
- An implementer that hits a session limit mid-task leaves real,
  usually-correct uncommitted work behind, not nothing — audit it
  against the task brief (`git status`/`git diff --stat` in both repos)
  before deciding to keep, fix, or redo it. This happened 3 times during
  Tier 2 and nothing was lost by trusting the audit over discarding and
  restarting.

## How to resume after reading this file

1. Check `ListAgents` / ask whether any dispatched implementer is still
   live before touching anything (avoid duplicate work).
2. Read the relevant plan's ledger tail for the last recorded state.
3. Run `git status`/`git diff --stat` in **both** repos before starting
   anything — see the crashed-implementer note above.
4. Continue the SDD loop (`superpowers:subagent-driven-development`)
   from wherever the ledger says to resume.
