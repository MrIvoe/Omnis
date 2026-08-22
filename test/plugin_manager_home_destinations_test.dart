import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/plugin_interface.dart';
import 'package:omnis/core/plugin_manager.dart';
import 'package:omnis_plugin_api/plugin_destination.dart';

Widget _placeholderBuilder(BuildContext context) => const Placeholder();

class _NoDestinationsPlugin extends MusicPlugin {
  @override
  String get id => 'no_destinations';
  @override
  String get name => 'No Destinations';
  @override
  String get description => 'test plugin';
  @override
  String get version => '1.0.0';
  @override
  String get author => 'test';
  @override
  Future<void> initialize() async {}
  @override
  Future<void> onTrackStart(BaseTrack track) async {}
  @override
  Future<void> onLibraryScan(String file) async {}
  @override
  dynamic uiSlot(String locationID) => null;
  @override
  Future<void> dispose() async {}
}

class _OneDestinationPlugin extends MusicPlugin {
  @override
  String get id => 'one_destination';
  @override
  String get name => 'One Destination';
  @override
  String get description => 'test plugin';
  @override
  String get version => '1.0.0';
  @override
  String get author => 'test';
  @override
  Future<void> initialize() async {}
  @override
  Future<void> onTrackStart(BaseTrack track) async {}
  @override
  Future<void> onLibraryScan(String file) async {}
  @override
  dynamic uiSlot(String locationID) => null;
  @override
  Future<void> dispose() async {}

  @override
  List<PluginDestination> homeDestinations() => [
        const PluginDestination(
          id: 'one_destination_tab',
          icon: Icons.star,
          label: 'One',
          pageBuilder: _placeholderBuilder,
        ),
      ];
}

class _ThrowingDestinationsPlugin extends MusicPlugin {
  @override
  String get id => 'throwing_destinations';
  @override
  String get name => 'Throwing Destinations';
  @override
  String get description => 'test plugin';
  @override
  String get version => '1.0.0';
  @override
  String get author => 'test';
  @override
  Future<void> initialize() async {}
  @override
  Future<void> onTrackStart(BaseTrack track) async {}
  @override
  Future<void> onLibraryScan(String file) async {}
  @override
  dynamic uiSlot(String locationID) => null;
  @override
  Future<void> dispose() async {}

  @override
  List<PluginDestination> homeDestinations() =>
      throw StateError('boom');
}

void main() {
  test('homeDestinations is empty when no registered plugin contributes any',
      () {
    final manager = PluginManager();
    manager.register(_NoDestinationsPlugin());

    expect(manager.homeDestinations, isEmpty);
  });

  test('homeDestinations collects a contributed destination from an '
      'enabled plugin', () {
    final manager = PluginManager();
    manager.register(_OneDestinationPlugin());

    expect(manager.homeDestinations, hasLength(1));
    expect(manager.homeDestinations.first.id, 'one_destination_tab');
  });

  test('homeDestinations excludes a disabled plugin\'s destinations',
      () async {
    final manager = PluginManager();
    manager.register(_OneDestinationPlugin());
    await manager.disablePlugin(manager.byId('one_destination')!);

    expect(manager.homeDestinations, isEmpty);
  });

  test('a plugin whose homeDestinations() throws contributes nothing, '
      'without taking down the aggregate call', () {
    final manager = PluginManager();
    manager.register(_ThrowingDestinationsPlugin());
    manager.register(_OneDestinationPlugin());

    expect(manager.homeDestinations, hasLength(1));
    expect(manager.homeDestinations.first.id, 'one_destination_tab');
  });

  test('destinations are sorted by order ascending', () {
    final manager = PluginManager();
    manager.register(_OneDestinationPlugin());
    // Second plugin contributes a lower-order destination that should
    // sort first among plugin destinations.
    manager.register(_LowOrderDestinationPlugin());

    final ids = manager.homeDestinations.map((d) => d.id).toList();
    expect(ids, ['low_order_tab', 'one_destination_tab']);
  });

  test('destinations tied on order keep their registration order', () {
    final manager = PluginManager();
    // Two plugins, several destinations each, every one of them at the
    // same `order` — PluginDestination.order's dartdoc promises ties
    // break by registration order, and `List.sort` is documented as an
    // unspecified algorithm rather than a stable one, so homeDestinations
    // makes the collection index an explicit tie-breaker instead of
    // leaning on sort stability. More than one tied pair here on purpose:
    // a two-element tie is preserved by essentially any sort, so it would
    // not actually exercise the guarantee.
    manager.register(_TiedOrderPlugin('tied_a'));
    manager.register(_TiedOrderPlugin('tied_b'));

    final ids = manager.homeDestinations.map((d) => d.id).toList();
    expect(ids, [
      'tied_a_1',
      'tied_a_2',
      'tied_a_3',
      'tied_b_1',
      'tied_b_2',
      'tied_b_3',
    ]);
  });

  test('an order tie-break never outranks the order value itself', () {
    final manager = PluginManager();
    // The later-registered plugin has the lower order, so registration
    // order must lose here — guards against a tie-breaker that
    // accidentally became the primary sort key.
    manager.register(_TiedOrderPlugin('tied_a'));
    manager.register(_LowOrderDestinationPlugin());

    final ids = manager.homeDestinations.map((d) => d.id).toList();
    expect(ids.first, 'low_order_tab');
  });
}

/// Contributes three destinations that all share one `order` value, with
/// ids prefixed by [prefix] so two instances can be told apart.
class _TiedOrderPlugin extends MusicPlugin {
  final String prefix;
  _TiedOrderPlugin(this.prefix);

  @override
  String get id => prefix;
  @override
  String get name => 'Tied Order $prefix';
  @override
  String get description => 'test plugin';
  @override
  String get version => '1.0.0';
  @override
  String get author => 'test';
  @override
  Future<void> initialize() async {}
  @override
  Future<void> onTrackStart(BaseTrack track) async {}
  @override
  Future<void> onLibraryScan(String file) async {}
  @override
  dynamic uiSlot(String locationID) => null;
  @override
  Future<void> dispose() async {}

  @override
  List<PluginDestination> homeDestinations() => [
        for (var i = 1; i <= 3; i++)
          PluginDestination(
            id: '${prefix}_$i',
            icon: Icons.star,
            label: '$prefix $i',
            pageBuilder: _placeholderBuilder,
            order: 7,
          ),
      ];
}

class _LowOrderDestinationPlugin extends MusicPlugin {
  @override
  String get id => 'low_order';
  @override
  String get name => 'Low Order';
  @override
  String get description => 'test plugin';
  @override
  String get version => '1.0.0';
  @override
  String get author => 'test';
  @override
  Future<void> initialize() async {}
  @override
  Future<void> onTrackStart(BaseTrack track) async {}
  @override
  Future<void> onLibraryScan(String file) async {}
  @override
  dynamic uiSlot(String locationID) => null;
  @override
  Future<void> dispose() async {}

  @override
  List<PluginDestination> homeDestinations() => [
        const PluginDestination(
          id: 'low_order_tab',
          icon: Icons.star,
          label: 'Low',
          pageBuilder: _placeholderBuilder,
          order: -1,
        ),
      ];
}
