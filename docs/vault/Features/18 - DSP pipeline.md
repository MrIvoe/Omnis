---
type: feature
phase: 3
status: partial
---

# 18. DSP pipeline

## Status

🟡 Flat named-multiplier gain composition; not yet the spec's staged, independently-reorderable pipeline

## Implemented by

No single owning component — the named-multiplier gain pipeline (`setGainContribution`/`_gainContributions`) lives in [[AudioEngine]], fed by named contributions from [[EqualizerPlugin]] and [[ReplayGainPlugin]].

## Build log

[[Phase 3 - Audio]]
