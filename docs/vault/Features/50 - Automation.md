---
type: feature
phase: 7
status: partial
---

# 50. Automation

## Status

🟡 GPS-speed and Bluetooth-connect triggers (now including a Car Mode layout switch), time-based playback scheduling, and now scheduled radio (a saved custom station); a general rules engine and scheduled podcasts still deferred

## Implemented by

No single owning component — GPS-speed/Bluetooth-connect triggers via [[DrivingModePlugin]] and [[BluetoothPlaybackPlugin]], time-based playback scheduling in core `lib/core/playback_scheduler.dart` (not documented as its own component), and scheduled radio via [[RadioPlugin]].

## Build log

[[Phase 7 - Advanced UX]]
