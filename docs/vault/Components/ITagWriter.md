---
type: component
kind: interface
repo: both
status: stable
---

# ITagWriter

Reads and writes every tag field a local audio file supports — the broader read/write surface `IFileTagWriter` deliberately doesn't cover (that interface is scoped to one narrow write, `writeLyrics`, for a different caller — see its own doc comment).

## Where it lives

`packages/omnis_plugin_api/lib/service_interfaces.dart`

## Implemented by

- [[TagEditorPlugin]]

## Serves

- [[12 - Artwork]] (writes looked-up artwork into the file's own tags)
- [[17 - Tag editor]]
