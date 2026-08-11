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

## Media notification / lock-screen controls — Android

Fixed a real bug: `AndroidManifest.xml` was missing the `<service>`/
`<receiver>` declarations `audio_service` requires (its own bundled
manifest doesn't merge these in automatically), and `MainActivity` didn't
extend `AudioServiceActivity`. `flutter build apk --debug` succeeding
only proves the app compiles with the new manifest/activity — it says
nothing about whether the notification actually appears at runtime.

1. Play a local track on a physical device or emulator. Confirm a media
   notification appears (and, on Android 13+, that the earlier
   `POST_NOTIFICATIONS` prompt is what's gating it, not this fix).
2. From the notification, tap play/pause, skip next/previous, and confirm
   each one takes effect immediately in the app.
3. Lock the screen. Confirm the same controls appear on the lock screen
   and still work.
4. Press a wired/Bluetooth headset's media button (or a car stereo's
   button) and confirm it also plays/pauses — this is what
   `MediaButtonReceiver` specifically covers, separate from the
   notification's own on-screen buttons.
5. Swipe the app away from Recents while playing. Confirm playback and
   the notification survive (this is what extending `AudioServiceActivity`
   — reusing the background-persistent Flutter engine — specifically
   fixes over a plain `FlutterActivity`).

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

## Visualizer — real spectrum capture

Replaced a hardcoded demo array with real capture via the `audify`
package (Android `Visualizer` API / iOS `AVAudioEngine`). Its degrade
paths (unsupported platform, permission denied, a native-call failure)
are unit-tested via `platformSupportOverride`, but real capture — and the
permission prompt itself — has never run on an actual device.

1. Open Now Playing on a physical Android or iOS device and tap
   "Activate visualizer." Confirm a microphone-permission prompt appears
   with a clear reason, not just the bare OS default wording.
2. Grant it. Confirm the bars visibly react to the actual music playing —
   quiet passages look different from a loud chorus — not the old fixed
   idle bounce.
3. Leave Now Playing (back button, or switch tabs) and confirm capture
   stops — no persistent microphone-in-use indicator lingering after you
   leave the screen.
4. Deny the permission prompt and confirm the app shows a clear message
   and the bars stay flat, rather than crashing or silently reverting to
   the old fake animation.
5. On a platform `audify` doesn't support (Windows/desktop), confirm
   activating the visualizer degrades to a clear message with flat bars,
   no crash.
6. After activating, look at the seek bar itself (not just the separate
   "Activate visualizer" bars row): a small cluster of live bars should
   be pinned to the current playhead position, growing/shrinking with
   the actual audio. Confirm it tracks the playhead as the track plays
   and as you drag-seek, and that dragging the seek bar still works
   normally — the overlay must never intercept the seek gesture.

## Startup / tab-switch responsiveness — large libraries

`LibraryPage._loadPersistedLibrary()` used to call `engine.setQueue(saved)`
with the *entire* persisted library on every app boot, before the user had
asked to play anything. Confirmed via a live, instrumented run on an Android
emulator with a synthetic 3000-track library that this single call —
`AudioEngine._rebuildQueueSource()` building a native `ConcatenatingAudioSource`
with thousands of `MediaSource` children in one platform-channel round trip —
took 40+ seconds, and left the native player working through invalid/missing
file entries (`ExoPlayerImplInternal`/`FileNotFoundException` spam) for many
seconds afterward, degrading UI responsiveness including plain bottom-nav tab
switches well past that. The fix removes that eager `setQueue` call entirely;
every real play action (tapping a track, a mood, a Home section) already sets
its own queue explicitly at the moment of the action, so nothing depends on
the queue being pre-populated at boot.

This can't be fully proven by `flutter analyze`/`flutter test`/a debug build
alone — it's a live timing characteristic, not a logic branch.

1. With a library of at least a few thousand tracks (real or synthetic),
   launch the app fresh and confirm it reaches the last-used tab without a
   long unresponsive stretch, and without `ExoPlayerImplInternal` /
   `FileNotFoundException` spam in `adb logcat`.
2. Switch between bottom-nav tabs (Home/Library/Playlist/Moods/Settings)
   repeatedly right after launch. Each switch should render immediately —
   check the actual screen content (e.g. via `adb exec-out screencap`), not
   just elapsed wall-clock time from a log line, since `debugPrint` output
   can lag behind the real frame under heavy startup log volume and make a
   genuinely fast switch look slow in logcat alone.
3. Play a track from Library, then background/foreground the app and switch
   tabs again — confirm no regression now that the queue *has* been set.

## After this checklist

If either plugin behaves differently from its doc comment's caveat
(e.g. driving detection actually does work reliably), update that
plugin's doc comment and the README table — the point of flagging
"unverified" is to keep it accurate, not to leave a permanent hedge
once it's actually been checked.
