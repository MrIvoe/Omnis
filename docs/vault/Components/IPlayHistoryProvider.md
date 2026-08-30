---
type: component
kind: interface
repo: both
status: stable
---

# IPlayHistoryProvider

Records and queries real play history — "recently played," "most played." Registered under this interface so a future alternate history source (e.g.

## Where it lives

`packages/omnis_plugin_api/lib/service_interfaces.dart`

## Implemented by

- [[ScrobblePlugin]]

## Serves

No tracked feature relies on this directly — [[ScrobblePlugin]] is its sole implementer; [[16 - History]] is served by the always-on [[PlayHistoryStore]] instead, which doesn't go through this interface.
