import 'package:audio_session/audio_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/output_device_controller.dart';

/// [classifyOutputDeviceType] is the one part of the output-devices
/// feature that's pure Dart, with no real `audio_session` platform
/// channel involved — see [OutputDeviceSource]'s doc for why the rest
/// (enumeration, selection) is exercised through a fake instead.
void main() {
  group('classifyOutputDeviceType', () {
    test('speaker types map to speaker', () {
      expect(classifyOutputDeviceType(AudioDeviceType.builtInSpeaker),
          OutputDeviceKind.speaker);
      expect(classifyOutputDeviceType(AudioDeviceType.builtInEarpiece),
          OutputDeviceKind.speaker);
    });

    test('wired types map to wiredHeadset', () {
      expect(classifyOutputDeviceType(AudioDeviceType.wiredHeadset),
          OutputDeviceKind.wiredHeadset);
      expect(classifyOutputDeviceType(AudioDeviceType.wiredHeadphones),
          OutputDeviceKind.wiredHeadset);
    });

    test('every Bluetooth profile maps to bluetooth', () {
      expect(classifyOutputDeviceType(AudioDeviceType.bluetoothA2dp),
          OutputDeviceKind.bluetooth);
      expect(classifyOutputDeviceType(AudioDeviceType.bluetoothSco),
          OutputDeviceKind.bluetooth);
      expect(classifyOutputDeviceType(AudioDeviceType.bluetoothLe),
          OutputDeviceKind.bluetooth);
    });

    test('USB audio and dock map to usb', () {
      expect(classifyOutputDeviceType(AudioDeviceType.usbAudio),
          OutputDeviceKind.usb);
      expect(
          classifyOutputDeviceType(AudioDeviceType.dock), OutputDeviceKind.usb);
    });

    test('HDMI and HDMI-ARC map to hdmi', () {
      expect(
          classifyOutputDeviceType(AudioDeviceType.hdmi), OutputDeviceKind.hdmi);
      expect(classifyOutputDeviceType(AudioDeviceType.hdmiArc),
          OutputDeviceKind.hdmi);
    });

    test('an unrelated type (e.g. telephony) falls back to other', () {
      expect(classifyOutputDeviceType(AudioDeviceType.telephony),
          OutputDeviceKind.other);
      expect(classifyOutputDeviceType(AudioDeviceType.unknown),
          OutputDeviceKind.other);
    });
  });
}
