import 'package:flutter/material.dart';
import 'package:omnis/core/plugin_manager.dart';
import 'package:omnis/ui/plugin_slot_view.dart';

/// Below this width: today's bottom [NavigationBar]. At or above it: a
/// side [NavigationRail].
///
/// 600dp is Material 3's own compact/medium window-size-class boundary
/// (see the M3 "window size classes" guidance) — a bottom bar is the
/// compact recommendation, a rail the medium one. It's also, in practice,
/// close to "phone portrait gets the bottom bar; everything else
/// (phone landscape, tablet, desktop) gets the rail" — relevant here
/// because Windows is a real CI-built target
/// (`.github/workflows/ci.yml` builds a Windows debug build) and a
/// desktop window is essentially always at or above this width.
const double kNavigationRailBreakpoint = 600;

/// Whether [HomeNavigationBar] will render a [NavigationRail] (`true`) or
/// the bottom [NavigationBar] (`false`) for the current [context] — a
/// standalone helper so `HomePage` can make the same width-based call
/// `HomeNavigationBar` makes internally, to decide *where in the layout*
/// (a side `Row` vs. `bottomNavigationBar`) to place it, without
/// duplicating the threshold.
bool isWideHomeLayout(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= kNavigationRailBreakpoint;

/// One of [HomeNavigationBar]'s five fixed destinations.
class HomeDestinationInfo {
  final IconData icon;
  final String label;

  const HomeDestinationInfo(this.icon, this.label);
}

/// The home shell's five fixed destinations, laid out responsively:
///  - narrower than [kNavigationRailBreakpoint]: today's bottom
///    [NavigationBar] (unchanged look/behavior).
///  - at or above it: a side [NavigationRail] — chosen over a
///    [NavigationDrawer] because the five fixed destinations plus
///    whatever a handful of plugins add at `sidebar_item` comfortably
///    fit a rail's compact icon+label column with no scrolling; a
///    drawer would add an open/close affordance and cover part of the
///    content for no real benefit at this destination count, and reads
///    less like the side-nav idiom Windows desktop apps (this app's
///    CI-built desktop target) already use.
///
/// Either way, whatever plugins inject at the `sidebar_item` slot is
/// rendered after the five fixed destinations — via a real
/// [PluginSlotView], so it live-updates as plugins are installed/
/// enabled/disabled exactly like every other slot in the app.
class HomeNavigationBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final PluginManager pluginManager;
  final List<HomeDestinationInfo> destinations;

  const HomeNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.pluginManager,
    required this.destinations,
  });

  @override
  Widget build(BuildContext context) {
    final pluginSlot = PluginSlotView(
      pluginManager: pluginManager,
      locationId: 'sidebar_item',
      direction: Axis.vertical,
    );

    if (isWideHomeLayout(context)) {
      return NavigationRail(
        selectedIndex: selectedIndex,
        onDestinationSelected: onDestinationSelected,
        labelType: NavigationRailLabelType.all,
        destinations: [
          for (final d in destinations)
            NavigationRailDestination(
              icon: Icon(d.icon),
              label: Text(d.label),
            ),
        ],
        // The documented pattern for pinning `trailing` to the bottom of
        // the rail (see [NavigationRail.trailing]'s own doc example) —
        // without the `Expanded`+bottom `Align`, `trailing` renders
        // immediately after the last destination instead.
        trailing: Expanded(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: pluginSlot,
            ),
          ),
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: NavigationBar(
            selectedIndex: selectedIndex,
            height: 72,
            elevation: 0,
            onDestinationSelected: onDestinationSelected,
            destinations: [
              for (final d in destinations)
                NavigationDestination(icon: Icon(d.icon), label: d.label),
            ],
          ),
        ),
        pluginSlot,
      ],
    );
  }
}
