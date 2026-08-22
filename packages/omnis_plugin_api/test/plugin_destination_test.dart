import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnis_plugin_api/plugin_destination.dart';

void main() {
  test('PluginDestination holds the fields home_page.dart needs to '
      'render a plugin-contributed tab', () {
    Widget builder(BuildContext context) => const Placeholder();

    final destination = PluginDestination(
      id: 'my_plugin_tab',
      icon: Icons.star,
      label: 'My Tab',
      pageBuilder: builder,
    );

    expect(destination.id, 'my_plugin_tab');
    expect(destination.icon, Icons.star);
    expect(destination.label, 'My Tab');
    expect(destination.pageBuilder, builder);
    expect(destination.order, 0, reason: 'default order is 0');
  });

  test('order can be set explicitly for sorting relative to other '
      'plugin destinations', () {
    Widget builder(BuildContext context) => const Placeholder();
    final destination = PluginDestination(
      id: 'x',
      icon: Icons.star,
      label: 'X',
      pageBuilder: builder,
      order: 5,
    );
    expect(destination.order, 5);
  });
}
