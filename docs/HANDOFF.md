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

## Active plans (as of 2026-08-24)

Two plans are running **concurrently** on this same codebase, coordinated
by hand since they both touch `service_interfaces.dart` and
`bundled_plugins.dart`:

1. **Core/Plugin Tier 2** — extract Home dashboard, Moods, and
   Radio+Online out of the app core into bundled plugins.
   - Plan: `docs/superpowers/plans/2026-08-24-core-plugin-tier2.md`
   - Ledger: `.superpowers/sdd/2026-08-24-core-plugin-tier2/progress.md`
   - Status: Tasks 1-2 complete and reviewed clean. **Task 3 (Home
     dashboard extraction) is the current focus** — see "Current
     blocker" below. Tasks 4 (Moods), 5 (Radio+Online), 6 (pin bump) not
     started.

2. **Theme/Layout/Icon plugin system** — let plugins contribute themes,
   Now Playing layouts, and icon artwork.
   - Plan: `docs/superpowers/plans/2026-08-24-theme-layout-icon-plugin-system.md`
   - Ledger: `.superpowers/sdd/2026-08-24-theme-layout-icon-plugin-system/progress.md`
   - Status: **Not started.** Explicitly waiting for Tier 2's active
     implementer to finish first (both plans' own ledgers carry this
     coordination note) — never dispatch an implementer for one plan
     while the other has a live implementer.

**Rule while both are active:** before dispatching any implementer for
either plan, check both ledgers for an open (undispatched-report) task.
Research/read-only dispatches don't conflict and can run in parallel.

## Current status (as of this session, 2026-08-25 ~05:10 UTC)

**Task 3 (Home dashboard extraction) is complete, reviewed clean, and
pushed.** It took 2 prior crashed implementer attempts + a 3rd that
finished it + 2 fix rounds (a real crash bug and a real UX regression,
both caught by task review, both fixed and re-reviewed clean) — full
history in the ledger
(`.superpowers/sdd/2026-08-24-core-plugin-tier2/progress.md`) if you need
the details. 6 minor/out-of-scope items were found and deliberately
parked rather than fixed — see the ledger's "Task 3: complete" entry for
the full list (a real production focus-dispatch quirk in
`GlobalKeyboardShortcuts`, a missing NowPlayingPage-nav capability, a
couple of stale doc comments, etc.) — none block anything, but worth
sweeping up in a future pass or the final whole-branch review.

**Standing instruction for this session:** push after every task
completes (not batched) — the human partner confirmed this explicitly
after Task 3. Don't accumulate unpushed commits across tasks without
asking again if that ever seems to conflict with something.

**Task 4 (Moods cluster extraction) is also complete, reviewed clean
(Approved on first pass, no fix round needed), and pushed** — 5 more
Minor items parked in the ledger.

**Next up:** Task 5 (Radio+Online extraction), then Task 6 (cross-repo
pin bump — the first point where the bundled plugins actually become
reachable without `pubspec_overrides.yaml`'s local sibling-checkout
override). Check the ledger tail for current status.

## Lessons already learned this session (don't relitigate)

- **Batch cross-repo pin bumps into one final task** — a tag cut before
  its own dependent commit lands is invisible locally (under
  `pubspec_overrides.yaml`) but breaks a clean checkout. Learned twice
  before Tier 2's Global Constraints codified it explicitly.
- **Push after committing, not just commit locally** — a prior task left
  a commit unpushed by accident.
- Every extracted plugin follows `radio_plugin.dart`'s exact
  `ServiceRegistry` lifecycle (register in `initialize()`+`enable()`,
  unregister in `disable()`+`dispose()`) — verify against that file's
  *current* content each time, don't work from a paraphrase.
- A capability a UI call site needs from a plugin-owned page goes through
  `pluginManager.services.get<T>()`, never a `GlobalKey` into a widget
  `home_page.dart` no longer constructs itself.

## How to resume after reading this file

1. Check `ListAgents` / ask whether any dispatched implementer is still
   live before touching anything (avoid duplicate work).
2. Read the relevant plan's ledger tail for the last recorded state.
3. Run `git status`/`git diff --stat` in **both** repos — an implementer
   that hit a session limit leaves real uncommitted work behind; assess
   it against the task brief before deciding to keep, fix, or redo it
   (as this session did for Task 3).
4. Continue the SDD loop (`superpowers:subagent-driven-development`)
   from wherever the ledger says to resume.
