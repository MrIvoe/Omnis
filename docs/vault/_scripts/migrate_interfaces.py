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
