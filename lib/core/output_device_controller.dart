import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:omnis/core/platform_capabilities.dart';

/// Broad, UI-facing category for an output device — §21's "Output
/// devices" only needs enough to pick a sensible icon and label, not the
/// dozen-plus raw `AudioDeviceType` values `audio_session` reports.
enum OutputDeviceKind {
  speaker,
  wiredHeadset,
  bluetooth,
  usb,
  hdmi,
  other,
}

/// One connected (or, on some platforms, merely known) audio output
/// device — a Bluetooth speaker, a wired headset, a USB DAC, the phone's
/// own built-in speaker, etc.
class OutputDeviceInfo {
  final String id;
  final String name;
  final OutputDeviceKind kind;

  const OutputDeviceInfo({
    required this.id,
    required this.name,
    required this.kind,
  });
}

/// Maps `audio_session`'s cross-platform [AudioDeviceType] down to the
/// coarser [OutputDeviceKind] this app's UI actually distinguishes.
/// Pure and platform-channel-free on purpose — the one part of this
/// feature that's genuinely unit-testable without mocking a real plugin
/// channel.
OutputDeviceKind classifyOutputDeviceType(AudioDeviceType type) {
  switch (type) {
    case AudioDeviceType.builtInSpeaker:
    case AudioDeviceType.builtInEarpiece:
      return OutputDeviceKind.speaker;
    case AudioDeviceType.wiredHeadset:
    case AudioDeviceType.wiredHeadphones:
      return OutputDeviceKind.wiredHeadset;
    case AudioDeviceType.bluetoothA2dp:
    case AudioDeviceType.bluetoothLe:
    case AudioDeviceType.bluetoothSco:
      return OutputDeviceKind.bluetooth;
    case AudioDeviceType.usbAudio:
    case AudioDeviceType.dock:
      return OutputDeviceKind.usb;
    case AudioDeviceType.hdmi:
    case AudioDeviceType.hdmiArc:
      return OutputDeviceKind.hdmi;
    default:
      return OutputDeviceKind.other;
  }
}

/// The seam `OutputDevicesPage` depends on, so a test can inject a fake
/// device list instead of a real `audio_session` platform channel — same
/// "small, purpose-specific interface" pattern `HomeWidgetTrackSource`/
/// `PlaybackEngine` already establish elsewhere in this app.
abstract class OutputDeviceSource {
  /// Every currently known output device.
  Future<List<OutputDeviceInfo>> listOutputDevices();

  /// Fires whenever a device connects or disconnects.
  Stream<void> get onDevicesChanged;

  /// Whether [selectDevice] can plausibly succeed on this platform —
  /// purely a best-effort UI hint (used to grey out or explain the
  /// picker before the user tries), not a guarantee: the underlying
  /// platform call can still fail per-device (see [selectDevice]'s doc).
  bool get supportsDeviceSelection;

  /// Attempts to route playback to [device]. Returns `null` on success,
  /// or a human-readable reason it couldn't — never throws.
  Future<String?> selectDevice(OutputDeviceInfo device);

  /// Reverts to whatever the OS would pick on its own.
  Future<void> useSystemDefault();
}

/// Real implementation, backed entirely by `audio_session` (already a
/// dependency of `just_audio`) — no new native platform-channel code.
///
/// Enumeration (`listOutputDevices`/`onDevicesChanged`) is genuinely
/// cross-platform via `AudioSession.getDevices()`/
/// `devicesChangedEventStream`. *Selection* is Android-only: the closest
/// thing Android has to an app-requestable general output route is
/// `AudioManager.setCommunicationDevice()` (API 31+, exposed here via
/// `audio_session`'s `AndroidAudioManager`) — despite the
/// "communication" name, this is the documented, modern replacement for
/// the older per-`AudioTrack` `setPreferredDevice()`, and is what this
/// app's playback session actually routes through. Below API 31, or on
/// any non-Android platform, there is no general-purpose "force this
/// app's output to device X" API to call at all — [supportsDeviceSelection]
/// reports that up front, and [selectDevice] fails soft with a clear
/// reason rather than pretending to succeed.
class AudioSessionOutputDeviceSource implements OutputDeviceSource {
  Future<AudioSession>? _sessionFuture;
  Future<AudioSession> get _session => _sessionFuture ??= AudioSession.instance;

  @override
  Future<List<OutputDeviceInfo>> listOutputDevices() async {
    final session = await _session;
    final devices = await session.getDevices(
      includeInputs: false,
      includeOutputs: true,
    );
    final infos = devices
        .map((d) => OutputDeviceInfo(
              id: d.id,
              name: d.name,
              kind: classifyOutputDeviceType(d.type),
            ))
        .toList();
    infos.sort((a, b) => a.name.compareTo(b.name));
    return infos;
  }

  @override
  Stream<void> get onDevicesChanged {
    final controller = StreamController<void>.broadcast();
    _session.then((session) {
      controller.addStream(session.devicesChangedEventStream.map((_) {}));
    });
    return controller.stream;
  }

  @override
  bool get supportsDeviceSelection =>
      PlatformCapabilities.supportsOutputDeviceSelection;

  @override
  Future<String?> selectDevice(OutputDeviceInfo device) async {
    if (!PlatformCapabilities.supportsOutputDeviceSelection) {
      return 'Choosing a specific output device is only supported on '
          'Android right now.';
    }
    try {
      final manager = AndroidAudioManager();
      final candidates = await manager.getAvailableCommunicationDevices();
      AndroidAudioDeviceInfo? match;
      for (final candidate in candidates) {
        if (candidate.id.toString() == device.id) {
          match = candidate;
          break;
        }
      }
      if (match == null) {
        return '${device.name} is no longer available.';
      }
      final ok = await manager.setCommunicationDevice(match);
      return ok ? null : 'Could not switch to ${device.name}.';
    } catch (e) {
      // Most commonly: API level below 31, where setCommunicationDevice
      // doesn't exist at all and the platform side throws rather than
      // returning false.
      return 'Could not switch to ${device.name}: this device or Android '
          'version may not support it.';
    }
  }

  @override
  Future<void> useSystemDefault() async {
    if (!PlatformCapabilities.supportsOutputDeviceSelection) return;
    try {
      await AndroidAudioManager().clearCommunicationDevice();
    } catch (_) {
      // Same not-supported-below-API-31 case as selectDevice — nothing
      // to revert if nothing could have been set in the first place.
    }
  }
}
