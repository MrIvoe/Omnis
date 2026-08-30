# Omnis Architecture Vault

This is the map of how Omnis is built — what plugin/interface/core
singleton implements what, and how done each tracked feature is. It
replaced `docs/OMNIS_2_0_STATUS.md` and `docs/OMNIS_2_0_FINISHED_TASK.md`
on 2026-08-29 (see both files for a short pointer back here, and git
history for their full prior content).

## How to navigate

- Start at **`00-Hubs/`** — one note per phase (Reliability, Library,
  Audio, Plugin Platform, Connectivity, Discovery, Advanced UX), each
  linking to its tracked feature items.
- **`Features/`** — one note per tracked feature item. Status, what
  implements it, known gaps, and a link into its phase's build log.
- **`Components/`** — one note per plugin, capability interface, or
  core singleton. What it is, where it lives, what it implements/depends
  on, which features it serves.
- **`Build Log/`** — one note per phase, a chronological table of dated
  changes (plus `General.md` for entries that don't map to one phase).

Click through links rather than grepping source — that's the entire
point of this existing.

## Keeping it current

No automated tooling enforces this — same discipline that's already
kept `docs/HANDOFF.md` current, just pointed at finer-grained notes now:

- **New component** (plugin, interface, core singleton with real
  cross-cutting responsibility) → new note in `Components/`.
- **A feature's status changes** → update its note in `Features/`
  (and its phase hub's status icon).
- **A plan/task completes** → add a row to the relevant phase's
  `Build Log/` note, and touch whatever Feature/Component notes it
  changed.

If this vault drifts out of sync anyway, that's a signal to build real
tooling later — not a reason to have built it speculatively now.

## Regenerating

`_scripts/` holds the Python scripts that did the original migration
from the old flat docs. They're safe to re-run against updated source
docs if a full mechanical pass is ever needed again — each is
idempotent (overwrites its own output, doesn't touch hand-edited
sections like cross-links unless re-run after they're re-marked).
