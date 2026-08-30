---
type: feature
phase: 2
status: partial
---

# 10. Search

## Status

🟡 Real full-text + field qualifiers (`rating:`, `bpm:`, `missing:`, etc.), built this project from a genuine 0% start; Library page now also has UI_SPEC §11's toggleable song-row metadata columns (Artist/Album/Year/Genre/Bitrate/Format/Rating/Play count/ReplayGain) — not reorderable spreadsheet columns, a scoped subset

## Implemented by

No single owning component — pure search/filter/field-qualifier logic in core `lib/core/library_search.dart`, invoked from the Library page UI; not documented as its own component.

## Build log

[[Phase 2 - Library]]
