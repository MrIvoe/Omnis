# Obsidian Architecture Vault Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `docs/OMNIS_2_0_STATUS.md` and `docs/OMNIS_2_0_FINISHED_TASK.md` with a linked note graph at `docs/vault/` — one note per plugin/interface/core singleton (Components), one per tracked feature item (Features), one per phase (00-Hubs, Build Log) — so future work (human or agent) finds "where does X live and what talks to it" by opening one small note instead of grepping across two repos.

**Architecture:** Bulk, mechanical generation (build log rows, feature/hub tables, plugin/interface component notes) is done by small Python scripts run once against the current source docs/code — the source docs already have consistent enough structure to parse reliably, and hand-typing ~100+ notes would waste far more tokens than the vault is meant to save. Judgment-requiring work (which core singletons matter enough for a note, and cross-linking features to the components that implement them) is done by a person/agent reading the generated notes, not scripted.

**Tech Stack:** Markdown + YAML frontmatter (Obsidian-native, no community plugins required), Python 3 (stdlib only) for the generator scripts.

**Spec:** `docs/superpowers/specs/2026-08-29-obsidian-architecture-vault-design.md`

## Global Constraints

- Every note is short and link-heavy — facts and links, not restated prose. A note should be useful in a couple hundred tokens.
- Links are plain `[[Wikilink]]` by note title, never by path.
- Status/kind/phase/type live in YAML frontmatter properties, never inline `#tags`.
- `ARCHITECTURE.md`, `PLUGIN_GUIDE.md`, `FEATURES.md`, and the rest of `docs/` are untouched by this plan — only `OMNIS_2_0_STATUS.md`, `OMNIS_2_0_FINISHED_TASK.md`, and `HANDOFF.md` are touched, exactly as scoped in the spec.
- Generator scripts live in `docs/vault/_scripts/` and are kept (not deleted after running) — they're the reusable "regenerate this section" tool if source docs change before the next full pass.
- Run every script from the Omnis repo root (`cd c:\Users\MrIvo\Github\Omnis`) with `python docs/vault/_scripts/<name>.py`. If `python` isn't on PATH, use the full interpreter path found via `where python` first.

---

### Task 1: Vault scaffolding — folders, templates, README, CLAUDE.md

**Files:**
- Create: `docs/vault/README.md`
- Create: `docs/vault/_templates/Component.md`
- Create: `docs/vault/_templates/Feature.md`
- Create: `docs/vault/_templates/Phase Hub.md`
- Create: `docs/vault/_templates/Build Log.md`
- Create: `CLAUDE.md` (repo root — none exists today)

**Interfaces:** None — this task produces no code, only the scaffolding every later task writes into.

- [ ] **Step 1: Create the template files**

`docs/vault/_templates/Component.md`:
```markdown
---
type: component
kind: plugin
repo: Omnis-Plugins
status: stable
---

# {{title}}

One-line purpose.

## Where it lives

`path/to/file.dart`

## Implements

- [[InterfaceName]]

## Depends on

- [[OtherComponent]]

## Serves

- [[N - Feature Name]]

## Notes

Only for a genuinely non-obvious constraint — omit this section entirely otherwise.
```

`docs/vault/_templates/Feature.md`:
```markdown
---
type: feature
phase: 1
status: partial
---

# {{title}}

One-line description.

## Status

🟡 Current state and the short "why".

## Implemented by

- [[ComponentName]]

## Known gaps

- Gap one

## Build log

- [[Phase 1 - Reliability]]
```

`docs/vault/_templates/Phase Hub.md`:
```markdown
---
type: hub
phase: 1
---

# Phase 1: Reliability

Short description of what this phase covers.

| # | Item | Status |
| --- | --- | --- |
| 1 | [[1 - Item Name]] | 🟡 |
```

`docs/vault/_templates/Build Log.md`:
```markdown
---
type: build-log
phase: 1
---

# Build Log — Phase 1: Reliability

| Date | Item | Notes |
| --- | --- | --- |
| 2026-01-01 | Example | Example entry. |
```

- [ ] **Step 2: Write `docs/vault/README.md`**

```markdown
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
```

- [ ] **Step 3: Write `CLAUDE.md`** (repo root — this file doesn't exist yet)

```markdown
# Omnis / Omnis-Plugins

For any question about where something lives, what a plugin implements,
what depends on what, or how done a tracked feature is: check
`docs/vault/00-Hubs/` first. It's a linked note graph (Obsidian-
compatible plain markdown) purpose-built to answer exactly those
questions in a couple hundred tokens instead of grepping source across
two repos. Full navigation guide: `docs/vault/README.md`.

Keep it current as you work: a new plugin/interface/core-singleton
gets a new note in `docs/vault/Components/`; a feature's status
changing gets its `docs/vault/Features/` note updated; a completed
plan/task gets a row in the relevant `docs/vault/Build Log/` phase
note. See `docs/vault/README.md`'s "Keeping it current" section for
the full rule.

For session-to-session continuity on in-flight work (not architecture),
see `docs/HANDOFF.md` instead — different job, read both if picking
this project up cold.
```

- [ ] **Step 4: Verify and commit**

```bash
cd c:\Users\MrIvo\Github\Omnis
git add docs/vault CLAUDE.md
git status --short
```

Confirm the output shows exactly the 6 new files above, nothing else.

```bash
git commit -m "Scaffold the Obsidian architecture vault (Tier: vault task 1)"
```

---

### Task 2: Migrate the build log

**Files:**
- Create: `docs/vault/_scripts/migrate_build_log.py`
- Create: `docs/vault/Build Log/Phase 1 - Reliability.md` through `Phase 7 - Advanced UX.md` (7 files)
- Create: `docs/vault/Build Log/General.md` (only if any row has no parseable phase number — check the script's own output to know if this file was written)

**Interfaces:**
- Consumes: `docs/OMNIS_2_0_FINISHED_TASK.md`'s `## Build log` markdown table (columns: `Date`, `Phase`, `Item`, `Notes`).
- Produces: `docs/vault/Build Log/Phase N - <Name>.md` files matching Task 1's `Build Log.md` template shape — later tasks (Feature notes) link to these by the exact title `Phase N - <Name>` (no `.md`).

- [ ] **Step 1: Write the script**

`docs/vault/_scripts/migrate_build_log.py`:
```python
#!/usr/bin/env python3
"""Split OMNIS_2_0_FINISHED_TASK.md's Build log table into per-phase
vault notes. Idempotent: re-running overwrites its own output files.

Usage (from the Omnis repo root):
    python docs/vault/_scripts/migrate_build_log.py
"""
import re
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
SOURCE = REPO_ROOT / "docs" / "OMNIS_2_0_FINISHED_TASK.md"
OUT_DIR = REPO_ROOT / "docs" / "vault" / "Build Log"

PHASE_NAMES = {
    1: "Reliability",
    2: "Library",
    3: "Audio",
    4: "Plugin platform",
    5: "Connectivity",
    6: "Discovery",
    7: "Advanced UX",
}


def parse_table(text: str) -> list[dict]:
    lines = [l for l in text.splitlines() if l.strip().startswith("|")]
    if len(lines) < 3:
        return []
    header = [c.strip() for c in lines[0].strip("|").split("|")]
    rows = []
    for line in lines[2:]:
        cells = [c.strip() for c in line.strip("|").split("|")]
        if len(cells) != len(header):
            continue
        rows.append(dict(zip(header, cells)))
    return rows


def phases_for(cell: str) -> list[int]:
    return [int(n) for n in re.findall(r"\d+", cell)]


def write_table(out_path: Path, title: str, rows: list[dict]) -> None:
    lines = [
        "---",
        "type: build-log",
        f"phase: {out_path.stem.split(' - ')[0].replace('Phase ', '') if 'Phase' in out_path.stem else 'null'}",
        "---",
        "",
        f"# Build Log — {title}",
        "",
        "| Date | Item | Notes |",
        "| --- | --- | --- |",
    ]
    for row in rows:
        lines.append(f"| {row['Date']} | {row['Item']} | {row['Notes']} |")
    out_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
    text = SOURCE.read_text(encoding="utf-8")
    if "## Build log" not in text:
        raise SystemExit("No '## Build log' section found in source doc")
    section = text.split("## Build log", 1)[1]
    rows = parse_table(section)
    if not rows:
        raise SystemExit("Parsed zero rows from the Build log table — check the source format")

    by_phase: dict[int, list[dict]] = {n: [] for n in PHASE_NAMES}
    general: list[dict] = []
    for row in rows:
        phases = phases_for(row.get("Phase", ""))
        if not phases:
            general.append(row)
            continue
        for p in phases:
            if p in by_phase:
                by_phase[p].append(row)

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for n, name in PHASE_NAMES.items():
        out = OUT_DIR / f"Phase {n} - {name}.md"
        write_table(out, f"Phase {n}: {name}", by_phase[n])
        print(f"wrote {out} ({len(by_phase[n])} rows)")

    if general:
        out = OUT_DIR / "General.md"
        write_table(out, "General (no single phase)", general)
        print(f"wrote {out} ({len(general)} rows)")
    else:
        print("no phase-less rows found — General.md not written")


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Run it**

```bash
cd c:\Users\MrIvo\Github\Omnis
python docs/vault/_scripts/migrate_build_log.py
```

Expected: 7 (or 8, if `General.md` was written) `wrote ...` lines, each with a row count greater than 0. If any phase shows 0 rows, stop and investigate before continuing — that means the parser missed rows that should have matched (re-check `OMNIS_2_0_FINISHED_TASK.md`'s exact table header spelling against the script's `parse_table`, don't just proceed).

- [ ] **Step 3: Spot-check the output**

Open 2 of the generated files (e.g. `docs/vault/Build Log/Phase 1 - Reliability.md` and `Phase 6 - Discovery.md`) and confirm: valid YAML frontmatter, a real markdown table with real dates/items/notes (not garbled cells), and that the row count roughly matches what you'd expect from skimming the source table's `Phase` column for that number.

- [ ] **Step 4: Commit**

```bash
git add docs/vault/_scripts/migrate_build_log.py "docs/vault/Build Log"
git commit -m "Migrate build log into per-phase vault notes (Tier: vault task 2)"
```

---

### Task 3: Migrate feature status — Features/ notes and 00-Hubs/ phase notes

**Files:**
- Create: `docs/vault/_scripts/migrate_status.py`
- Create: `docs/vault/Features/1 - <Item>.md` through `50 - <Item>.md` (50 files — exact names depend on the source doc's current item titles)
- Create: `docs/vault/00-Hubs/Phase 1 - Reliability.md` through `Phase 7 - Advanced UX.md` (7 files)

**Interfaces:**
- Consumes: `docs/OMNIS_2_0_STATUS.md`'s per-phase `| # | Item | Status |` tables.
- Produces: `docs/vault/Features/<N> - <Item>.md` files, each with an `## Implemented by` section containing the literal marker text `*(fill in during cross-linking pass)*` — Task 7 finds and replaces every occurrence of that exact string. Also produces `docs/vault/00-Hubs/Phase N - <Name>.md`, distinct from (but linking the same items as) Task 2's `Build Log/Phase N - <Name>.md`.

- [ ] **Step 1: Write the script**

`docs/vault/_scripts/migrate_status.py`:
```python
#!/usr/bin/env python3
"""Generate Features/ notes and 00-Hubs/ phase notes from
OMNIS_2_0_STATUS.md. Idempotent for the hub notes and the generated
sections of feature notes; re-running will NOT preserve hand-edited
'Implemented by' links added by the cross-linking task, so don't
re-run this after Task 7 without re-doing that link work.

Usage (from the Omnis repo root):
    python docs/vault/_scripts/migrate_status.py
"""
import re
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
SOURCE = REPO_ROOT / "docs" / "OMNIS_2_0_STATUS.md"
FEATURES_DIR = REPO_ROOT / "docs" / "vault" / "Features"
HUBS_DIR = REPO_ROOT / "docs" / "vault" / "00-Hubs"

STATUS_MAP = {
    "\u2705": "solid",              # ✅
    "\U0001F7E2": "solid-unverified",  # 🟢
    "\U0001F7E1": "partial",        # 🟡
    "\u2B1C": "not-started",        # ⬜
}

PHASE_RE = re.compile(r"^## Phase (\d+) [\u2014-] (.+)$", re.MULTILINE)


def sanitize(name: str) -> str:
    return re.sub(r'[\\/:*?"<>|]', "-", name).strip()


def main() -> None:
    text = SOURCE.read_text(encoding="utf-8")
    matches = list(PHASE_RE.finditer(text))
    if not matches:
        raise SystemExit("No '## Phase N — Name' headers found — check the source format")

    FEATURES_DIR.mkdir(parents=True, exist_ok=True)
    HUBS_DIR.mkdir(parents=True, exist_ok=True)

    total_features = 0
    for i, m in enumerate(matches):
        phase_num = int(m.group(1))
        phase_name = m.group(2).strip()
        start = m.end()
        end = matches[i + 1].start() if i + 1 < len(matches) else len(text)
        section = text[start:end]

        rows = []
        for line in section.splitlines():
            line = line.strip()
            if not line.startswith("|"):
                continue
            cells = [c.strip() for c in line.strip("|").split("|")]
            if len(cells) != 3 or not cells[0].isdigit():
                continue
            rows.append(cells)

        hub_lines = [
            "---", "type: hub", f"phase: {phase_num}", "---", "",
            f"# Phase {phase_num}: {phase_name}", "",
            "| # | Item | Status |", "| --- | --- | --- |",
        ]

        for num, item, status_text in rows:
            icon = status_text[:1]
            status_value = STATUS_MAP.get(icon, "partial")
            desc = status_text[1:].strip() if icon in STATUS_MAP else status_text
            safe_item = sanitize(item)

            hub_lines.append(f"| {num} | [[{num} - {safe_item}]] | {icon} |")

            feature_lines = [
                "---", "type: feature", f"phase: {phase_num}",
                f"status: {status_value}", "---", "",
                f"# {num}. {item}", "",
                "## Status", "", f"{icon} {desc}".strip(), "",
                "## Implemented by", "",
                "*(fill in during cross-linking pass)*", "",
                "## Build log", "",
                f"[[Phase {phase_num} - {phase_name}]]", "",
            ]
            out = FEATURES_DIR / f"{num} - {safe_item}.md"
            out.write_text("\n".join(feature_lines), encoding="utf-8")
            total_features += 1

        hub_out = HUBS_DIR / f"Phase {phase_num} - {phase_name}.md"
        hub_out.write_text("\n".join(hub_lines) + "\n", encoding="utf-8")
        print(f"wrote {hub_out} and {len(rows)} feature notes")

    print(f"total feature notes: {total_features}")


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Run it**

```bash
cd c:\Users\MrIvo\Github\Omnis
python docs/vault/_scripts/migrate_status.py
```

Expected: 7 `wrote ...` lines (one per phase) plus a final `total feature notes: 50` line. If the total isn't 50, stop and check — count the actual rows in `docs/OMNIS_2_0_STATUS.md` first (`grep -c "^| [0-9]" docs/OMNIS_2_0_STATUS.md`) to see whether the source has drifted from 50 items since the spec was written, or the parser missed rows.

- [ ] **Step 3: Spot-check the output**

Open `docs/vault/Features/1 - Playback engine.md` (or whatever item 1 is actually titled) and confirm: frontmatter status matches the source emoji, the status prose reads correctly (not truncated mid-word), and the build-log link target filename matches a real file from Task 2.

- [ ] **Step 4: Commit**

```bash
git add docs/vault/_scripts/migrate_status.py docs/vault/Features docs/vault/00-Hubs
git commit -m "Migrate feature status into Features/ and 00-Hubs/ vault notes (Tier: vault task 3)"
```

---

### Task 4: Component notes — bundled plugins

**Files:**
- Create: `docs/vault/_scripts/migrate_plugins.py`
- Create: `docs/vault/Components/<PluginClassName>.md` — one per file in `Omnis-Plugins/lib/*_plugin.dart` (35 as of this plan being written; the script itself determines the real current count — don't hardcode 35 anywhere except as this comment's context)

**Interfaces:**
- Consumes: every `Omnis-Plugins/lib/*_plugin.dart` file's doc comment immediately preceding its `class X extends MusicPlugin` declaration, and any `implements I..., I...` clause on that same declaration.
- Produces: `docs/vault/Components/<ClassName>.md` files with a `## Serves` section containing the literal marker `*(fill in during cross-linking pass)*` for Task 7, and (when the plugin implements at least one interface) an `## Implements` section linking to `[[InterfaceName]]` — those targets are created by Task 5, which can run before or after this task in either order (both write to `Components/`, no shared filenames since plugin class names and interface names never collide in this codebase).

- [ ] **Step 1: Write the script**

`docs/vault/_scripts/migrate_plugins.py`:
```python
#!/usr/bin/env python3
"""Generate Components/ notes for every bundled plugin in the sibling
Omnis-Plugins repo. Idempotent for its own output; doesn't touch
hand-added '## Serves' links added by the cross-linking task unless
re-run (which will overwrite them back to the placeholder marker).

Usage (from the Omnis repo root):
    python docs/vault/_scripts/migrate_plugins.py
"""
import re
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
PLUGINS_DIR = REPO_ROOT.parent / "Omnis-Plugins" / "lib"
OUT_DIR = REPO_ROOT / "docs" / "vault" / "Components"

CLASS_RE = re.compile(
    r"((?:^///.*\n)+)^class (\w+) extends MusicPlugin(?: implements ([\w, ]+))?",
    re.MULTILINE,
)


def doc_to_purpose(doc_block: str) -> str:
    lines = [l[3:].strip() for l in doc_block.splitlines() if l.startswith("///")]
    text = " ".join(l for l in lines if l)
    m = re.match(r"(.+?[.!?])(\s|$)", text)
    return m.group(1) if m else text[:200]


def main() -> None:
    if not PLUGINS_DIR.exists():
        raise SystemExit(f"Omnis-Plugins/lib not found at {PLUGINS_DIR} — check sibling checkout path")

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    written = 0
    skipped = []
    for path in sorted(PLUGINS_DIR.glob("*_plugin.dart")):
        text = path.read_text(encoding="utf-8")
        m = CLASS_RE.search(text)
        if not m:
            skipped.append(path.name)
            continue
        doc_block, class_name, implements = m.group(1), m.group(2), m.group(3)
        purpose = doc_to_purpose(doc_block)
        interfaces = [i.strip() for i in (implements or "").split(",") if i.strip()]

        lines = [
            "---", "type: component", "kind: plugin", "repo: Omnis-Plugins",
            "status: stable", "---", "",
            f"# {class_name}", "", purpose, "",
            "## Where it lives", "",
            f"`Omnis-Plugins/lib/{path.name}`", "",
        ]
        if interfaces:
            lines += ["## Implements", ""]
            lines += [f"- [[{i}]]" for i in interfaces]
            lines.append("")
        lines += ["## Serves", "", "*(fill in during cross-linking pass)*", ""]

        (OUT_DIR / f"{class_name}.md").write_text("\n".join(lines), encoding="utf-8")
        written += 1

    print(f"wrote {written} plugin component notes")
    if skipped:
        print(f"SKIPPED (no doc-comment+class match, needs hand-authoring): {', '.join(skipped)}")


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Run it**

```bash
cd c:\Users\MrIvo\Github\Omnis
python docs/vault/_scripts/migrate_plugins.py
```

- [ ] **Step 3: Hand-author any SKIPPED files**

If the script printed any `SKIPPED` filenames, open each one, find its class declaration and doc comment by hand (the regex only matches the exact `/// doc lines directly above `class X extends MusicPlugin`` shape — a file with a blank line between the doc comment and the class, or a different base class, won't match), and write its `docs/vault/Components/<ClassName>.md` manually, following the same template Task 1 created. Do not skip this step even if only 1-2 files were skipped — every plugin gets a note.

- [ ] **Step 4: Spot-check the output**

Open 2 generated notes for plugins with genuinely different shapes (e.g. one with `implements` clauses like `HomeDashboardPlugin`, one without like a simple metadata-only plugin) and confirm the purpose sentence reads as a real, grammatical one-liner (not cut off mid-clause) and the `Implements` links (if any) list real interface names.

- [ ] **Step 5: Commit**

```bash
git add docs/vault/_scripts/migrate_plugins.py docs/vault/Components
git commit -m "Add plugin component notes to the vault (Tier: vault task 4)"
```

---

### Task 5: Component notes — capability interfaces

**Files:**
- Create: `docs/vault/_scripts/migrate_interfaces.py`
- Create: `docs/vault/Components/<InterfaceName>.md` — one per `abstract class I...` in `packages/omnis_plugin_api/lib/service_interfaces.dart` (23 as of this plan being written; script determines the real current count)

**Interfaces:**
- Consumes: `packages/omnis_plugin_api/lib/service_interfaces.dart`'s doc comments preceding each `abstract class I\w+` declaration.
- Produces: `docs/vault/Components/<InterfaceName>.md` with both `## Implemented by` and `## Serves` sections containing the `*(fill in during cross-linking pass)*` marker for Task 7.

- [ ] **Step 1: Write the script**

`docs/vault/_scripts/migrate_interfaces.py`:
```python
#!/usr/bin/env python3
"""Generate Components/ notes for every capability interface in
service_interfaces.dart. Idempotent for its own output.

Usage (from the Omnis repo root):
    python docs/vault/_scripts/migrate_interfaces.py
"""
import re
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
SOURCE = REPO_ROOT / "packages" / "omnis_plugin_api" / "lib" / "service_interfaces.dart"
OUT_DIR = REPO_ROOT / "docs" / "vault" / "Components"

CLASS_RE = re.compile(
    r"((?:^///.*\n)+)^abstract class (I\w+)",
    re.MULTILINE,
)


def doc_to_purpose(doc_block: str) -> str:
    lines = [l[3:].strip() for l in doc_block.splitlines() if l.startswith("///")]
    text = " ".join(l for l in lines if l)
    m = re.match(r"(.+?[.!?])(\s|$)", text)
    return m.group(1) if m else text[:200]


def main() -> None:
    if not SOURCE.exists():
        raise SystemExit(f"source file not found: {SOURCE}")

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    text = SOURCE.read_text(encoding="utf-8")
    written = 0
    for m in CLASS_RE.finditer(text):
        doc_block, name = m.group(1), m.group(2)
        purpose = doc_to_purpose(doc_block)
        lines = [
            "---", "type: component", "kind: interface", "repo: both",
            "status: stable", "---", "",
            f"# {name}", "", purpose, "",
            "## Where it lives", "",
            "`packages/omnis_plugin_api/lib/service_interfaces.dart`", "",
            "## Implemented by", "", "*(fill in during cross-linking pass)*", "",
            "## Serves", "", "*(fill in during cross-linking pass)*", "",
        ]
        (OUT_DIR / f"{name}.md").write_text("\n".join(lines), encoding="utf-8")
        written += 1

    print(f"wrote {written} interface component notes")


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Run it**

```bash
cd c:\Users\MrIvo\Github\Omnis
python docs/vault/_scripts/migrate_interfaces.py
```

Expected: `wrote 23 interface component notes` (or the current real count — cross-check with `grep -c "^abstract class I" packages/omnis_plugin_api/lib/service_interfaces.dart` if the number looks surprising).

- [ ] **Step 3: Spot-check and commit**

Open 1-2 generated notes to confirm the purpose sentence is real and complete, then:

```bash
git add docs/vault/_scripts/migrate_interfaces.py docs/vault/Components
git commit -m "Add capability interface component notes to the vault (Tier: vault task 5)"
```

---

### Task 6: Component notes — core singletons

**Files:**
- Create: `docs/vault/Components/MainCore.md`
- Create: `docs/vault/Components/AudioEngine.md`
- Create: `docs/vault/Components/PluginManager.md`
- Create: `docs/vault/Components/LibraryRepository.md`
- Create: `docs/vault/Components/PlayHistoryStore.md`
- Create: `docs/vault/Components/AppSettings.md`
- Create: `docs/vault/Components/MediaScanner.md`
- Create: `docs/vault/Components/RecoveryJournal.md`
- Create: `docs/vault/Components/PlaylistStore.md`

**Interfaces:** None — hand-authored, no script. This is the plan's judgment call from the spec's Open Item #1: not every `.instance`-backed store in `lib/core/` earns a node in the graph, only the ones with real cross-cutting responsibility that other components genuinely reach into. The 9 above were selected on that basis (each is referenced from multiple plugins or is itself referenced throughout this session's own work); smaller single-purpose stores (`ab_loop_store.dart`, `sidebar_config.dart`, `playlist_folder_store.dart`, `queue_history_store.dart`, `track_fingerprint_store.dart`, `home_widget_service.dart`, `playback_schedule.dart`) are deliberately left out — they're implementation detail of one feature area each, not shared infrastructure. If a later contributor finds one of these genuinely needs a note (something else starts depending on it), add one then, following this task's template — don't force it now.

- [ ] **Step 1: Read each file's current top-of-file doc comment before writing its note**

For each of the 9 files below, read its doc comment and class declaration first — don't write from memory of what these classes do, verify against current source, matching this codebase's own established discipline:
- `lib/core/main_core.dart`
- `lib/core/audio_engine.dart`
- `lib/core/plugin_manager.dart`
- `lib/core/library_repository.dart`
- `lib/core/play_history_store.dart`
- `lib/core/app_settings.dart`
- `lib/core/media_scanner.dart`
- `lib/core/recovery_journal.dart`
- `lib/core/playlist_store.dart`

- [ ] **Step 2: Write each note**

Use this shape for all 9 (kind is always `core-singleton`, repo is always `Omnis` — none of these live in the shared package):

```markdown
---
type: component
kind: core-singleton
repo: Omnis
status: stable
---

# MainCore

The app's central orchestrator — wires AudioEngine and PluginManager
together at startup and owns cross-cutting timers (playback-schedule
checking). Deliberately holds no concrete plugin knowledge; the only
plugin-side import it has is the bundled-plugin factory list.

## Where it lives

`lib/core/main_core.dart`

## Depends on

- [[AudioEngine]]
- [[PluginManager]]

## Serves

*(fill in during cross-linking pass)*
```

Write the actual 9 notes with real purpose sentences drawn from Step 1's reading — the example above (`MainCore`) is illustrative of the shape, not something to copy verbatim without verifying it still matches current source.

- [ ] **Step 3: Commit**

```bash
git add "docs/vault/Components/MainCore.md" "docs/vault/Components/AudioEngine.md" "docs/vault/Components/PluginManager.md" "docs/vault/Components/LibraryRepository.md" "docs/vault/Components/PlayHistoryStore.md" "docs/vault/Components/AppSettings.md" "docs/vault/Components/MediaScanner.md" "docs/vault/Components/RecoveryJournal.md" "docs/vault/Components/PlaylistStore.md"
git commit -m "Add core singleton component notes to the vault (Tier: vault task 6)"
```

---

### Task 7: Cross-linking pass

**Files:**
- Modify: all 50 files in `docs/vault/Features/` (replace the `## Implemented by` marker)
- Modify: relevant files in `docs/vault/Components/` (add real entries to `## Serves` / `## Depends on`, replacing markers where present)

**Interfaces:**
- Consumes: every Feature note (Task 3), every Component note (Tasks 4-6), plus `docs/PLUGIN_GUIDE.md` and each phase's `Build Log/` note (Task 2) as reference material for figuring out which component actually implements which feature.
- Produces: nothing new — this task only edits `## Implemented by`/`## Serves`/`## Depends on` sections in files that already exist.

This is the one task in this plan that isn't scriptable — matching a
feature description to the component(s) that implement it needs
real reading, not regex. Work phase by phase (7 sub-steps below);
within each phase, for every feature note: search `docs/vault/Components/`
for plausible matches (grep component note titles/purposes for terms
from the feature's title and status description), check the feature's
`Build Log` link for entries naming a specific file/plugin, and when
still unsure, grep the actual source for the feature's distinguishing
terms. Every `*(fill in during cross-linking pass)*` marker gets
replaced with either real `[[Component]]` links or, if a feature is
genuinely cross-cutting with no single owning component, the honest
sentence "No single owning component — implemented across
`[[ComponentA]]`, `[[ComponentB]]`, and core playback logic." Never
leave the marker text itself in a finished note.

Two worked examples to calibrate on:

- **Feature "Recommendations" (Discovery phase)** — grep
  `docs/vault/Components/` for "mood" and "recommend" → find
  `MoodsPlugin.md`. Open it, confirm its purpose mentions
  preset/custom moods and recommendation-style queue building — it's
  the real implementer. Replace the feature note's marker with
  `- [[MoodsPlugin]]`. Then open `MoodsPlugin.md` and add
  `- [[N - Recommendations]]` under its `## Serves` section (replacing
  its own marker, or appending if other features already linked there).
- **Feature "Plugin lifecycle" (Plugin platform phase)** — this is
  genuinely cross-cutting (every plugin goes through it). Replace the
  marker with `[[PluginManager]]` (the component that actually
  implements lifecycle management), not a list of all 35 plugins that
  merely use it.

- [ ] **Step 1: Cross-link Phase 1 (Reliability) feature notes**
- [ ] **Step 2: Cross-link Phase 2 (Library) feature notes**
- [ ] **Step 3: Cross-link Phase 3 (Audio) feature notes**
- [ ] **Step 4: Cross-link Phase 4 (Plugin platform) feature notes**
- [ ] **Step 5: Cross-link Phase 5 (Connectivity) feature notes**
- [ ] **Step 6: Cross-link Phase 6 (Discovery) feature notes**
- [ ] **Step 7: Cross-link Phase 7 (Advanced UX) feature notes**

- [ ] **Step 8: Verify no markers remain**

```bash
cd c:\Users\MrIvo\Github\Omnis
grep -rl "fill in during cross-linking pass" docs/vault/
```

Expected: no output (empty). If any files are listed, go back and finish them — this is the completion gate for this task, not optional cleanup.

- [ ] **Step 9: Commit**

```bash
git add docs/vault/Features docs/vault/Components
git commit -m "Cross-link feature notes to their implementing components (Tier: vault task 7)"
```

---

### Task 8: Retire the old docs, update HANDOFF.md

**Files:**
- Modify: `docs/OMNIS_2_0_STATUS.md` (replace full content with a stub)
- Modify: `docs/OMNIS_2_0_FINISHED_TASK.md` (replace full content with a stub)
- Modify: `docs/HANDOFF.md` (add one pointer line)

**Interfaces:** None.

- [ ] **Step 1: Replace `docs/OMNIS_2_0_STATUS.md`'s content**

```markdown
# Omnis 2.0 — Progress At a Glance

**Superseded on 2026-08-29** by the Obsidian architecture vault —
see [`docs/vault/README.md`](vault/README.md), starting from
[`docs/vault/00-Hubs/`](vault/00-Hubs/) for the same per-phase feature
status this file used to hold, now as linked notes instead of one flat
table. This file's prior content is preserved in git history.
```

- [ ] **Step 2: Replace `docs/OMNIS_2_0_FINISHED_TASK.md`'s content**

```markdown
# Omnis 2.0 — Build Log

**Superseded on 2026-08-29** by the Obsidian architecture vault —
see [`docs/vault/Build Log/`](vault/Build%20Log/) for the same
chronological log, now split by phase and linked into the features/
components it touched. This file's prior content is preserved in git
history.
```

- [ ] **Step 3: Add a pointer line to `docs/HANDOFF.md`**

Read the file's current content first (it changes often), then add one
line near the top — in whichever existing section already lists other
docs to read first (per this file's own "read in this order" list) —
pointing at `docs/vault/README.md` as the architecture/status reference,
distinct from `HANDOFF.md`'s own session-continuity job. Don't restructure
the rest of the file.

- [ ] **Step 4: Verify and commit**

```bash
cd c:\Users\MrIvo\Github\Omnis
git add docs/OMNIS_2_0_STATUS.md docs/OMNIS_2_0_FINISHED_TASK.md docs/HANDOFF.md
git diff --cached --stat
```

Confirm exactly 3 files changed, then:

```bash
git commit -m "Retire OMNIS_2_0_STATUS.md/FINISHED_TASK.md in favor of the vault; point HANDOFF.md at it (Tier: vault task 8)"
```

---

## After This Plan

`docs/vault/` is the primary reference for architecture and feature
status going forward. No pin bumps, no cross-repo coordination needed
(this plan only touches the Omnis repo — Omnis-Plugins is read from,
never written to). Push to `main` after each task per this session's
standing "push after every task" rule.
