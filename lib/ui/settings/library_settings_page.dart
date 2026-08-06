import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/ui/settings/settings_widgets.dart';

/// Library: where tracks come from and how the cleanup/tagging tools on
/// the Library page decide what counts as a duplicate or a short-track ad
/// stinger. Source-specific settings (metadata credentials, Essentia URL,
/// artist separators) live on their owning plugin's own settings page —
/// see the Plugins entry on the Settings home page.
class LibrarySettingsPage extends StatefulWidget {
  const LibrarySettingsPage({super.key});

  @override
  State<LibrarySettingsPage> createState() => _LibrarySettingsPageState();
}

class _LibrarySettingsPageState extends State<LibrarySettingsPage> {
  late AppSettings _settings;

  @override
  void initState() {
    super.initState();
    _settings = AppSettings.instance;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = _settings;
    return Scaffold(
      appBar: AppBar(title: const Text('Library')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Library access', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          ListTile(
            title: const Text('Library source'),
            subtitle: const Text(
                'Choose whether to scan the whole phone, a dedicated folder, or nothing'),
            trailing: DropdownButton<LibrarySource>(
              value: settings.librarySource,
              items: const [
                DropdownMenuItem(
                    value: LibrarySource.wholePhone,
                    child: Text('Whole phone')),
                DropdownMenuItem(
                    value: LibrarySource.dedicatedFolder,
                    child: Text('Dedicated folder')),
                DropdownMenuItem(
                    value: LibrarySource.none, child: Text('None')),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => settings.librarySource = value);
              },
            ),
          ),
          ListTile(
            title: const Text('Folder for library scans'),
            subtitle:
                Text(settings.selectedFolderPath ?? 'Pick a folder to browse'),
            trailing: FilledButton.tonal(
              onPressed: () async {
                final result = await FilePicker.platform.getDirectoryPath();
                if (result != null && mounted) {
                  setState(() => settings.selectedFolderPath = result);
                }
              },
              child: const Text('Pick folder'),
            ),
          ),
          const SizedBox(height: 16),
          Text('Library cleanup & tagging', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Used by the Library page\'s cleanup tool ("Find duplicates & '
            'short tracks…"). Featured-artist separators, metadata '
            'enrichment credentials, and Essentia analysis are configured '
            'from their own plugins — tap a plugin in Plugins to open its '
            'settings.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          SliderListTile(
            title: 'Short-track threshold: '
                '${settings.shortTrackThresholdSeconds}s',
            value: settings.shortTrackThresholdSeconds.toDouble(),
            min: 0,
            max: 120,
            divisions: 24,
            label: '${settings.shortTrackThresholdSeconds}s',
            onChanged: (value) => setState(
                () => settings.shortTrackThresholdSeconds = value.round()),
          ),
        ],
      ),
    );
  }
}
