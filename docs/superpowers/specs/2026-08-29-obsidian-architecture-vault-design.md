# Obsidian Architecture Vault — Design

**Goal:** replace the flat, prose-heavy `OMNIS_2_0_STATUS.md` (feature
status) and `OMNIS_2_0_FINISHED_TASK.md` (build log) with a linked note
graph in Obsidian that also captures the architecture those docs never
did — what plugin/interface/singleton implements what, and how they
connect. The payoff is fewer tokens spent re-deriving "where does X
live and what talks to it" by reading source or grepping across two
repos: a future Claude Code session (or the human) opens one small,
precise note instead.

**Non-goals:** this is not a rewrite of `ARCHITECTURE.md`,
`PLUGIN_GUIDE.md`, or any other reference-manual doc in `docs/` — those
stay exactly where they are, and vault notes link to them rather than
duplicating their content. This is also not an automated
codebase-scanning tool — v1 is hand-authored and hand-maintained,
matching how `HANDOFF.md` has already been kept current this session.

## Location

`docs/vault/` inside the Omnis repo, opened as its own Obsidian vault
(a vault is just a folder — this doesn't require moving or reorganizing
anything else, and doesn't preclude the user's existing general-purpose
`C:\Ai\Obsidian` vault from being used for unrelated things). Committed
to git like any other doc.

Omnis-Plugins' files are referenced by relative path from the vault
(`../../../Omnis-Plugins/lib/...`) — a single vault spans both repos,
no second vault, no symlink.

## Folder structure

```
docs/vault/
  README.md              # vault entry point: what this is, how to navigate, the maintenance rule
  00-Hubs/                # 7 phase hub notes
  Components/             # one note per plugin, capability interface, or core singleton
  Features/               # one note per tracked feature item (the existing 50)
  Build Log/               # one note per phase (7), each holding that phase's chronological table
  _templates/              # the 4 templates below, as literal files Obsidian's template plugin (or copy-paste) can use
```

## Note types and templates

All four types share one rule: **short and link-heavy.** A note should
be useful in a couple hundred tokens, not a couple thousand. Facts and
links, not restated prose. Status language matches the voice already
established in `OMNIS_2_0_STATUS.md` (✅/🟢/🟡/⬜, "no known named gaps
left," etc.) rather than inventing a new one.

### Component note — `Components/<Name>.md`

```yaml
---
type: component
kind: plugin            # plugin | interface | core-singleton
repo: Omnis-Plugins      # Omnis | Omnis-Plugins | both
status: stable
---
```
- One-line purpose (what it does, in plain terms)
- **Where it lives** — real file path(s)
- **Implements** — links to interface notes it registers/implements,
  e.g. `[[IMoodPlayer]]`
- **Depends on** — links to other component notes it reaches
  (`pluginManager.services.get<T>()`, direct imports, singletons)
- **Serves** — links to the feature note(s) it's the implementation of
- Optional **Notes** section — only for a genuinely non-obvious
  constraint or gotcha (e.g. "GlobalKey is owned by the plugin, not the
  host — see Tier 2's pattern"), never a restatement of what the code
  already says

### Feature note — `Features/<N> - <Name>.md`

Same numbering as today's `OMNIS_2_0_STATUS.md` (1-50), same titles.

```yaml
---
type: feature
phase: 6                 # 1-7, matching the existing phase numbering
status: partial           # solid | solid-unverified | partial | not-started
---
```
- One-line description
- **Status** — current state + the short "why" behind it, in the same
  voice as today's status doc
- **Implemented by** — links to component note(s)
- **Known gaps** — bullets (only if any remain)
- **Build log** — links into the relevant phase's Build Log note

### Phase hub — `00-Hubs/Phase <N> - <Name>.md`

Short intro paragraph (what this phase covers), then a linked list/table
of its items with status, mirroring `OMNIS_2_0_STATUS.md`'s per-phase
tables today.

### Build Log note — `Build Log/Phase <N> - <Name>.md`

One per phase (7 total, not per historical row). Holds that phase's
chronological table, relocated verbatim from
`OMNIS_2_0_FINISHED_TASK.md`'s existing "Build log" section (filtered to
that phase's rows), reformatted with wikilinks to feature/component
notes added where a row's "Item" column names something that now has a
note. Going forward, new entries are appended as new table rows in the
relevant phase's note — not new standalone notes per entry.

## Linking & tagging conventions

- Links are plain `[[Wikilink]]` by note title, not by path — Obsidian
  auto-updates a wikilink when the target note is renamed or moved,
  which a path-based link wouldn't survive.
- Status/kind/phase/type live in YAML frontmatter properties (as shown
  in each template above), not inline `#tags`. This works with vanilla
  Obsidian's built-in property search/filter — no community plugin
  (e.g. Dataview) required for v1. If richer querying is wanted later,
  frontmatter properties are exactly what Dataview reads, so nothing
  here blocks adding it.

## Migration plan

| Source | Action |
|---|---|
| `OMNIS_2_0_STATUS.md` | Fully superseded. Every row becomes a `Features/` note; every phase section becomes a `00-Hubs/` note. Original file replaced with a short stub: "Superseded by [[docs/vault/README]] — see the Features/ and 00-Hubs/ notes there." |
| `OMNIS_2_0_FINISHED_TASK.md` | Fully superseded. Its "Build log" table's rows are split by phase into the 7 `Build Log/` notes; its phase-header sections (which largely mirror `OMNIS_2_0_STATUS.md`'s own item descriptions) inform the `Features/` notes' content where more detail is useful. Original file replaced with the same kind of stub. |
| `ARCHITECTURE.md`, `PLUGIN_GUIDE.md`, `FEATURES.md`, and the rest of `docs/` | Untouched. Component notes link to specific sections where it adds real value; no content duplicated into the vault. |
| `HANDOFF.md` | Untouched except one added line pointing at the vault (different job: session/SDD continuity, not the architecture map). |
| `docs/superpowers/plans/`, `docs/superpowers/specs/` | Untouched (already the established durable-record convention). Vault notes — especially Build Log rows — link out to the relevant plan/spec instead of restating it. |

**Component inventory to write notes for** (identified from the current
codebase, subject to the implementer re-verifying counts against the
real source before writing, per this codebase's own "verify, don't
paraphrase" discipline used throughout Tier 2):
- Every bundled plugin in `Omnis-Plugins/lib/*_plugin.dart` (dozens —
  exact count TBD by the implementation plan's own directory listing)
- Every capability interface in
  `packages/omnis_plugin_api/lib/service_interfaces.dart` (9+ as of
  Tier 2's completion — `IHomeCustomizer`, `IMoodPlayer`,
  `ICustomRadioStationProvider`, `IRadioProvider`, `IFavoritesProvider`,
  `IOnlineSearchProvider`, `IEmbeddedPlaybackProvider`,
  `IQueueBuilder`, `ISmartPlaylistProvider`, plus whatever else is
  actually in the file by the time this plan executes)
- Core singletons: `MainCore`, `AudioEngine`, `PluginManager`,
  `LibraryRepository`, `PlayHistoryStore`, `AppSettings`, and any other
  `locator<T>()`-registered singleton with real cross-cutting
  responsibility (not every small store needs a note — the implementer
  should use judgment on what's actually load-bearing enough to be
  worth a node in the graph, and say so if a borderline case comes up)

Expected total note count: **~104-124** (50 feature + 7 hub + 7 build-log
+ ~40-60 component, depending on the real component count found during
implementation).

## Discovery & maintenance

**`CLAUDE.md`** (new — this repo has none today) — states plainly: for
any question about where something lives or what connects to what,
check `docs/vault/00-Hubs/` first before reading source or grepping.
Also states the maintenance rule below, so it's a durable instruction
every session sees, not something relying on memory.

**`docs/vault/README.md`** — the vault's own front door: what this is,
how the four note types relate, and the maintenance rule stated once,
in full: *new component → new note; a feature's status changes → update
its note; a plan/task completes → add a Build Log row and touch
whatever it changed.* No automated tooling enforces this in v1 — same
discipline that's already kept `HANDOFF.md` current, now pointed at
finer-grained notes instead of one flat file. If it drifts anyway,
revisit with real tooling later; not worth building speculatively now.

## Open items for the implementation plan to resolve

These are genuine judgment calls the planning/implementation step should
make explicitly, not guess silently — flagged here rather than decided
in this spec, since they need the real current file listing to answer
correctly:

1. The exact current component inventory (plugin count, interface
   count, which singletons are load-bearing enough to warrant a note).
2. Whether any of the 50 feature items map to zero clean "implemented
   by" components (a genuinely cross-cutting feature with no single
   owning file) — if so, the feature note should say so honestly rather
   than force a link that doesn't exist.
3. Note naming collisions — if two components share a display name
   across repos, the implementer needs a disambiguation convention
   (e.g., append `(Omnis)`/`(Omnis-Plugins)` only when it collides, not
   universally).
