---
type: component
kind: core-singleton
repo: Omnis
status: stable
---

# AudioEngine

The core playback engine — the "indestructible layer" of Omnis. Owns the `just_audio` `AudioPlayer` instance(s) and exposes the reactive streams the UI and plugins consume; no plugin code runs inside it. The whole queue loads as one `ConcatenatingAudioSource` on the primary player (with a source-index-to-queue-index map, since tracks with no playable URL are skipped when the source is built); when crossfade is enabled, a second, otherwise-idle `AudioPlayer` preloads and silently plays the next track during the overlap window while a periodic ramp fades volume between the two.

## Where it lives

`lib/core/audio_engine.dart`

## Depends on

- [[AppSettings]] (for `RepeatMode`)

## Serves

*(fill in during cross-linking pass)*
