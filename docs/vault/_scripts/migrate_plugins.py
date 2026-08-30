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
