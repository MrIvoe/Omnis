---
type: feature
phase: 7
status: solid-unverified
---

# 45. Layout builder

## Status

🟢 Solid for Now Playing (real drag-and-drop editor, 6 bundled layouts); Home now has reorder/hide too, and now UI_SPEC §3-5's pop-out sidebar (a global drawer, reachable via a menu button or Ctrl+B, pinning playlists/moods into user-editable, reorderable sections) — a free-form widget canvas and the sidebar's fuller mode-switching (Compact/Pinned/Auto-hide) remain open

## Implemented by

No single owning component — Now Playing's drag-and-drop layout editor and the pop-out sidebar live in core UI (`lib/ui/player_layouts/`, `lib/core/sidebar_config.dart`), not documented as their own components; Home's reorder/hide is [[HomeDashboardPlugin]].

## Build log

[[Phase 7 - Advanced UX]]
