# Manual QA

Two bundled plugins depend on real hardware/movement that neither
static review nor a unit test can verify — both self-flag this in their
own doc comments (see
[Omnis-Plugins' README](https://github.com/MrIvoe/Omnis-Plugins#plugins)
for the full verification-status table). Run this checklist before
each release; it should take under 15 minutes with a phone in hand.

## `DrivingModePlugin` — GPS speed detection

Implemented against `geolocator`'s documented API; not exercised
against real movement.

1. Enable the plugin (Settings → Plugins → Driving Mode) on a physical
   device — the emulator's simulated location won't produce real speed
   deltas.
2. Grant foreground location permission when prompted.
3. Walk briskly, then stop. Confirm the Now Playing layout switches to
   Car Mode above the configured speed threshold and switches back once
   stopped.
4. If a car is available: drive (as a passenger) above the threshold
   and confirm the same switch happens smoothly, without flapping back
   and forth at the threshold boundary.
5. Deny location permission and confirm the plugin degrades quietly —
   no crash, no repeated permission-prompt loop.

## `BluetoothPlaybackPlugin` — device connect/disconnect

Implemented against `audio_session`'s documented API; not exercised
against a real Bluetooth device.

1. Enable the plugin and pair a real Bluetooth speaker or car stereo
   (A2DP profile is the common case; SCO/LE if available).
2. Connect it. Confirm the "quick play" prompt (library / mood /
   playlist) appears and each option actually starts playback.
3. Disconnect the device mid-playback. Confirm playback either pauses
   or continues sanely (whichever Omnis's audio-route-change policy
   intends) rather than crashing or playing through a now-disconnected
   route.
4. Reconnect the same device. Confirm the plugin doesn't double-prompt
   or leave a stale "connected" state from before the disconnect.
5. Deny the Bluetooth permission prompt and confirm the plugin degrades
   quietly.

## Waveform seek bar — real peak rendering

`WaveformStore`/`WaveformSeekBar` are covered by unit/widget tests against
synthetic data (no platform channel is registered in `flutter test`), but
the actual `just_waveform` native extraction — Android/iOS/macOS only, no
Windows/Linux/web — has never run against a real audio file.

1. Play a local track (`TrackType.local`) on a supported device. Open Now
   Playing and confirm the seek bar eventually renders real peaks instead
   of the plain slider — the first play of a track will show the plain
   slider briefly while extraction runs, then switch over.
2. Drag across the waveform and confirm it seeks smoothly, matching the
   plain slider's `onSeek`/haptic-on-release feel.
3. Re-open the same track later and confirm the waveform appears
   immediately (served from the on-disk cache, no re-extraction delay).
4. Play a Spotify/YouTube (streaming) track and confirm the plain slider
   is used the whole time — no attempt to extract, no crash.
5. On a platform `just_waveform` doesn't support (Windows/desktop),
   confirm every track — local or streaming — just uses the plain slider,
   with no error surfaced to the user.

## After this checklist

If either plugin behaves differently from its doc comment's caveat
(e.g. driving detection actually does work reliably), update that
plugin's doc comment and the README table — the point of flagging
"unverified" is to keep it accurate, not to leave a permanent hedge
once it's actually been checked.
