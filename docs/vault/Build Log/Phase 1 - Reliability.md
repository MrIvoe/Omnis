---
type: build-log
phase: 1
---

# Build Log — Phase 1: Reliability

| Date | Item | Notes |
| --- | --- | --- |
| 2026-08-12 | Recovery, Persistence | Wired `PlaybackWatchdog`/`PlaybackRecovery`/`RecoveryJournal` (built in a prior session but never connected) into `MainCore`: watchdog now actually starts, failure counters reset on a healthy track, the journal saves on pause/track-change/20s heartbeat, and `HomePage` offers a "Resume where you left off?" prompt on launch. Removed a stray leftover file (`lib/core/playback_d`, an interrupted write from the prior session). |
| 2026-08-12 | Tests | Added `test/recovery_journal_test.dart` and a resumable-state test group in `test/main_core_test.dart`. Full suite: 445 passing, `flutter analyze` clean. |
| 2026-08-12 | Playback engine | Split `AudioEngine` per §51.2: extracted `OmnisAudioHandler`/`OmnisWindowsMediaHandler` (audio_service + Windows SMTC) into `lib/core/playback_os_integration.dart` with zero behavior change, and extracted A-B repeat into `lib/core/ab_repeat_controller.dart` as a player-decoupled, unit-testable `AbRepeatController`. Added `test/ab_repeat_controller_test.dart` (10 tests). |
| 2026-08-12 | Tests | Full suite: 455 passing, `flutter analyze` clean. |
| 2026-08-12 | Playback engine, Tests | Introduced `lib/core/playback_engine.dart` (`PlaybackEngine`, §51.3 capability interface); `AudioEngine implements PlaybackEngine`; `PlaybackWatchdog`/`PlaybackRecovery` now depend on the interface instead of the concrete engine. Added `test/fakes/fake_playback_engine.dart`, `test/playback_watchdog_test.dart` (13 tests), `test/playback_recovery_test.dart` (10 tests) — first direct unit coverage for the watchdog/recovery system. Full suite: 478 passing, `flutter analyze` clean. |
