---
type: component
kind: core-singleton
repo: Omnis
status: stable
---

# MediaScanner

Scans the device for music into `BaseTrack`s. On Android it queries the OS's pre-indexed MediaStore via `on_audio_query`, which is nearly instant even for thousands of tracks; on desktop/iOS it falls back to a recursive filesystem walk, reusing a `knownTracks` entry's already-read tags whenever that file's path and mtime still match so a repeat scan of a large, mostly-unchanged library stays fast. Honors `AppSettings.librarySource == LibrarySource.none` as a scan-wide guard, enforced here rather than only at the call site so no future caller can accidentally bypass the user's "don't scan my files" choice.

## Where it lives

`lib/core/media_scanner.dart`

## Depends on

- [[AppSettings]]

## Serves

*(fill in during cross-linking pass)*
