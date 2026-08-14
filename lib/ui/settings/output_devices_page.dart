import 'dart:async';

import 'package:flutter/material.dart';
import 'package:omnis/core/output_device_controller.dart';

/// §21 "Output devices" — lists every output device `audio_session`
/// currently knows about (built-in speaker, wired headset, Bluetooth,
/// USB DAC, HDMI) and, on Android, lets the user pick one to route
/// playback to via `AudioManager.setCommunicationDevice()`. See
/// [AudioSessionOutputDeviceSource]'s doc for why selection is
/// Android-only and what that API actually is.
class OutputDevicesPage extends StatefulWidget {
  /// Defaults to a real [AudioSessionOutputDeviceSource] when null —
  /// not a plain default parameter value, since that class holds
  /// mutable state and so has no `const` constructor to default to.
  final OutputDeviceSource? source;

  const OutputDevicesPage({super.key, this.source});

  @override
  State<OutputDevicesPage> createState() => _OutputDevicesPageState();
}

class _OutputDevicesPageState extends State<OutputDevicesPage> {
  late final OutputDeviceSource _source =
      widget.source ?? AudioSessionOutputDeviceSource();

  List<OutputDeviceInfo> _devices = const [];
  bool _loading = true;
  String? _selectedId;
  String? _error;
  StreamSubscription<void>? _changesSub;

  @override
  void initState() {
    super.initState();
    _load();
    _changesSub = _source.onDevicesChanged.listen((_) => _load());
  }

  Future<void> _load() async {
    final devices = await _source.listOutputDevices();
    if (!mounted) return;
    setState(() {
      _devices = devices;
      _loading = false;
    });
  }

  Future<void> _select(OutputDeviceInfo? device) async {
    setState(() => _error = null);
    if (device == null) {
      await _source.useSystemDefault();
      if (!mounted) return;
      setState(() => _selectedId = null);
      return;
    }
    final error = await _source.selectDevice(device);
    if (!mounted) return;
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() => _selectedId = device.id);
  }

  @override
  void dispose() {
    _changesSub?.cancel();
    super.dispose();
  }

  IconData _iconFor(OutputDeviceKind kind) => switch (kind) {
        OutputDeviceKind.speaker => Icons.speaker,
        OutputDeviceKind.wiredHeadset => Icons.headset,
        OutputDeviceKind.bluetooth => Icons.bluetooth_audio,
        OutputDeviceKind.usb => Icons.usb,
        OutputDeviceKind.hdmi => Icons.cast_connected,
        OutputDeviceKind.other => Icons.speaker_group,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canSelect = _source.supportsDeviceSelection;
    return Scaffold(
      appBar: AppBar(title: const Text('Output devices')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (!canSelect)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Choosing a specific output device isn\'t supported '
                      'on this platform/Android version — the list below '
                      'is informational only.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.error),
                    ),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(_error!,
                        style: TextStyle(color: theme.colorScheme.error)),
                  ),
                RadioListTile<String?>(
                  title: const Text('System default'),
                  subtitle: const Text('Let Android choose automatically'),
                  value: null,
                  groupValue: _selectedId,
                  onChanged: canSelect ? (_) => _select(null) : null,
                ),
                for (final device in _devices)
                  RadioListTile<String?>(
                    key: ValueKey('output_device_${device.id}'),
                    secondary: Icon(_iconFor(device.kind)),
                    title: Text(device.name),
                    value: device.id,
                    groupValue: _selectedId,
                    onChanged: canSelect ? (_) => _select(device) : null,
                  ),
                if (_devices.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 24),
                    child: Center(child: Text('No output devices found.')),
                  ),
              ],
            ),
    );
  }
}
