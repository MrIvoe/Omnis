---
type: feature
phase: 6
status: partial
---

# 44. Themes

## Status

🟡 Real declarative theme engine (URL/file import, closed-schema colors/typography/icon-style) plus a full in-app visual editor (9 color pickers, font/scale/corner-radius/motion/icon-style controls, solid/gradient background editor, live preview, save-and-install); named-preset parity closed, more presets possible

## Implemented by

No single owning component — the declarative theme engine (import/editor/installer) lives in core UI `lib/ui/theme/declarative/`, not documented as its own component; [[AppSettings]] persists the active theme mode/preset/accent-color choice.

## Build log

[[Phase 6 - Discovery]]
