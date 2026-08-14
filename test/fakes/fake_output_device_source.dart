import 'dart:async';

import 'package:omnis/core/output_device_controller.dart';

/// A controllable in-memory [OutputDeviceSource] double for testing
/// [OutputDevicesPage] without a real `audio_session` platform channel.
class FakeOutputDeviceSource implements OutputDeviceSource {
  List<OutputDeviceInfo> devices;
  final _changesController = StreamController<void>.broadcast();

  @override
  bool supportsDeviceSelection;

  /// If set, [selectDevice] returns this instead of succeeding.
  String? nextSelectError;

  /// Every device passed to [selectDevice], in order.
  final List<OutputDeviceInfo> selectCalls = [];

  /// How many times [useSystemDefault] was called.
  int useSystemDefaultCalls = 0;

  FakeOutputDeviceSource({
    this.devices = const [],
    this.supportsDeviceSelection = true,
  });

  @override
  Future<List<OutputDeviceInfo>> listOutputDevices() async => devices;

  @override
  Stream<void> get onDevicesChanged => _changesController.stream;

  void emitDevicesChanged(List<OutputDeviceInfo> newDevices) {
    devices = newDevices;
    _changesController.add(null);
  }

  @override
  Future<String?> selectDevice(OutputDeviceInfo device) async {
    selectCalls.add(device);
    return nextSelectError;
  }

  @override
  Future<void> useSystemDefault() async {
    useSystemDefaultCalls++;
  }

  Future<void> dispose() => _changesController.close();
}
