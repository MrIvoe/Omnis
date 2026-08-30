---
type: feature
phase: 7
status: partial
---

# 48. Accessibility

## Status

🟡 Keyboard shortcuts (now with per-shortcut remapping and conflict detection), tooltips, `Semantics` pass, reduce-motion/transparency, and a Ctrl+K command palette (11 of 13 spec-named commands, now also §37's "search everywhere" overlay across Commands/Songs/Playlists/Moods) all real; Artists/Albums/Settings search-everywhere coverage and the 2 still-deferred commands are the remaining named gaps

## Implemented by

No single owning component — keyboard shortcut remapping (`lib/core/keyboard_shortcut_remap.dart`) and the Ctrl+K command palette/search-everywhere overlay (`lib/core/command_palette.dart`) are core UI logic, not documented as their own components.

## Build log

[[Phase 7 - Advanced UX]]
