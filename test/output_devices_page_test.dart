import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/output_device_controller.dart';
import 'package:omnis/ui/settings/output_devices_page.dart';

import 'fakes/fake_output_device_source.dart';

const _speaker = OutputDeviceInfo(
    id: '1', name: 'Phone speaker', kind: OutputDeviceKind.speaker);
const _headset = OutputDeviceInfo(
    id: '2', name: 'Wired headset', kind: OutputDeviceKind.wiredHeadset);
const _buds = OutputDeviceInfo(
    id: '3', name: 'Pixel Buds', kind: OutputDeviceKind.bluetooth);

Future<void> _pump(WidgetTester tester, FakeOutputDeviceSource source) async {
  await tester.pumpWidget(MaterialApp(
    home: OutputDevicesPage(source: source),
  ));
  await tester.pump();
}

void main() {
  group('OutputDevicesPage', () {
    testWidgets('lists every device the source reports, each with a name',
        (tester) async {
      final source =
          FakeOutputDeviceSource(devices: [_speaker, _headset, _buds]);
      await _pump(tester, source);

      expect(find.text('Phone speaker'), findsOneWidget);
      expect(find.text('Wired headset'), findsOneWidget);
      expect(find.text('Pixel Buds'), findsOneWidget);
      expect(find.text('System default'), findsOneWidget);
    });

    testWidgets('shows an empty state when no devices are reported',
        (tester) async {
      final source = FakeOutputDeviceSource(devices: const []);
      await _pump(tester, source);

      expect(find.text('No output devices found.'), findsOneWidget);
    });

    testWidgets(
        'tapping a device calls selectDevice with that exact device, not '
        'just any device', (tester) async {
      final source =
          FakeOutputDeviceSource(devices: [_speaker, _headset, _buds]);
      await _pump(tester, source);

      await tester.tap(find.byKey(const ValueKey('output_device_3')));
      await tester.pump();

      expect(source.selectCalls, [_buds]);
    });

    testWidgets('tapping System default calls useSystemDefault, not '
        'selectDevice', (tester) async {
      final source = FakeOutputDeviceSource(devices: [_speaker]);
      await _pump(tester, source);

      // "System default" starts pre-selected (groupValue is null, same as
      // its own value), so tapping it immediately would be a no-op tap on
      // an already-selected radio — Radio's real, correct behavior is to
      // not fire onChanged in that case. Select a real device first so
      // "System default" is a genuine, different choice to switch back to.
      await tester.tap(find.byKey(const ValueKey('output_device_1')));
      await tester.pump();
      expect(source.selectCalls, [_speaker]);

      await tester.tap(find.text('System default'));
      await tester.pump();

      expect(source.useSystemDefaultCalls, 1);
      expect(source.selectCalls, [_speaker]);
    });

    testWidgets(
        'a selectDevice failure surfaces the real error message, not a '
        'generic one', (tester) async {
      final source = FakeOutputDeviceSource(devices: [_speaker])
        ..nextSelectError = 'Phone speaker is no longer available.';
      await _pump(tester, source);

      await tester.tap(find.byKey(const ValueKey('output_device_1')));
      await tester.pump();

      expect(find.text('Phone speaker is no longer available.'),
          findsOneWidget);
    });

    testWidgets(
        'when the source reports selection is unsupported, radio tiles are '
        'disabled and an explanatory note is shown', (tester) async {
      final source = FakeOutputDeviceSource(
          devices: [_speaker], supportsDeviceSelection: false);
      await _pump(tester, source);

      expect(
          find.textContaining("isn't supported on this platform"),
          findsOneWidget);

      final tile = tester.widget<RadioListTile<String?>>(
          find.byKey(const ValueKey('output_device_1')));
      expect(tile.onChanged, isNull);

      await tester.tap(find.byKey(const ValueKey('output_device_1')));
      await tester.pump();
      expect(source.selectCalls, isEmpty);
    });

    testWidgets('a devicesChanged event refreshes the visible list live',
        (tester) async {
      final source = FakeOutputDeviceSource(devices: [_speaker]);
      await _pump(tester, source);
      expect(find.text('Pixel Buds'), findsNothing);

      source.emitDevicesChanged([_speaker, _buds]);
      await tester.pump();

      expect(find.text('Pixel Buds'), findsOneWidget);
    });
  });
}
