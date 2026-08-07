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

## After this checklist

If either plugin behaves differently from its doc comment's caveat
(e.g. driving detection actually does work reliably), update that
plugin's doc comment and the README table — the point of flagging
"unverified" is to keep it accurate, not to leave a permanent hedge
once it's actually been checked.
