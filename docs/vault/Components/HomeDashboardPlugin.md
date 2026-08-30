---
type: component
kind: plugin
repo: Omnis-Plugins
status: stable
---

# HomeDashboardPlugin

Contributes the Home tab (Recently Played / Most Played / Recently Added / Continue Listening / Favorites / Most Skipped) as a [PluginDestination] — Tier 2 task 3's extraction of what used to be `home_page.dart`'s hardcoded first tab, built directly from `HomeDashboardPage` (`lib/ui/home_dashboard_page.dart`) and `HomeLayoutStore` (`lib/core/home_layout_store.dart`) inside the Omnis app itself.

## Where it lives

`Omnis-Plugins/lib/home_dashboard_plugin.dart`

## Implements

- [[IHomeCustomizer]]

## Serves

- [[45 - Layout builder]] (Home's reorder/hide)
