---
type: build-log
phase: 3
---

# Build Log — Phase 3: Audio

| Date | Item | Notes |
| --- | --- | --- |
| 2026-08-12 | Recovery, Database | Found and fixed two related concurrency bugs while re-reading the stores just hardened above: (1) `RecoveryJournal.save()`/`clear()` had no serialization — two calls close together (a pause and the 20s heartbeat) raced on the same `.tmp` path. (2) Worse: `PlayHistoryStore.recordPlay`/`recordPosition` each do their own full load→mutate→save cycle, and `MainCore` fires both unawaited from independent stream listeners around every track change — two concurrent calls could each load the same base state and whichever saved last silently discarded the other's update (a lost play count or lost position, not just a file-write race). Both stores now serialize their operations onto one queue, so each call sees the previous one's committed result. Added regression tests exercising real (unawaited, `Future.wait`-joined) concurrency, not just sequential calls. Full suite: 487 passing, `flutter analyze` clean. |
| 2026-08-13 | (all) | User directive: stop asking, keep building autonomously through every remaining phase, auto-commit and push, write a dedicated "missed" document for gaps found but not fixed in the pass that found them. Ran 5 parallel research audits (one per remaining phase) against both repos before touching any code — same discipline as the Phase 2 audit. Result: Phase 4 (Plugin platform) turned out far more built than the blanket tracker credited (real `ServiceRegistry`, real sandboxing, real permission UI); Phase 3 (Audio)/Phase 6 (Discovery)/Phase 7 (Advanced UX) are a real mix of solid-but-narrower-than-spec pieces and genuine 0% gaps; Phase 5 (Connectivity) is almost entirely 0% except Spotify/YouTube, which are solid but self-flagged unverified against real accounts. Full findings appended to `OMNIS_2_0_MISSED_DEEP_PHASE.md`; phase tables above updated from "Not started" to real, cited statuses. |
