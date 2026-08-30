---
type: component
kind: plugin
repo: Omnis-Plugins
status: stable
---

# TagEditorPlugin

Reads and writes ID3 tags — every standard frame on read, the four most structurally-supported ones (title/artist/album/artwork) as real native ID3v2.3 frames on write, everything else as custom `TXXX` frames.

## Where it lives

`Omnis-Plugins/lib/tag_editor_plugin.dart`

## Implements

- [[IFileTagWriter]]
- [[ITagWriter]]

## Serves

*(fill in during cross-linking pass)*
