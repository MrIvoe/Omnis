---
type: component
kind: plugin
repo: Omnis-Plugins
status: stable
---

# AudioAnalysisPlugin

A bundled plugin that sends a local track's audio to a self-hosted Essentia analysis service and returns real BPM/key/mood data.

## Where it lives

`Omnis-Plugins/lib/audio_analysis_plugin.dart`

## Implements

- [[IAudioAnalysisProvider]]

## Serves

- [[23 - Audio analysis]]
- [[40 - Sonic similarity]] (supplies the acoustic features the similarity scoring is computed over)
