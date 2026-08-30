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
    "✅": "solid",              # ✅
    "🟢": "solid-unverified",  # 🟢
    "🟡": "partial",        # 🟡
    "⬜": "not-started",        # ⬜
}

PHASE_RE = re.compile(r"^## Phase (\d+) [—-] (.+)$", re.MULTILINE)


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
