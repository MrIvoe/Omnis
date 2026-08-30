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
