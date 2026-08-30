---
type: component
kind: interface
repo: both
status: stable
---

# IAudioAnalysisProvider

Analyzes a track's actual audio content (BPM/key/mood via real signal analysis) — as opposed to [IMetadataProvider], which looks things up from external metadata, not the audio itself.

## Where it lives

`packages/omnis_plugin_api/lib/service_interfaces.dart`

## Implemented by

- [[AudioAnalysisPlugin]]

## Serves

- [[23 - Audio analysis]]
- [[40 - Sonic similarity]]
