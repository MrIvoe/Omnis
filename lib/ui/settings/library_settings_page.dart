import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/ui/settings/settings_widgets.dart';
import 'package:omnis/ui/widgets/settings_highlight.dart';

/// Library: where tracks come from and how the cleanup/tagging tools on
/// the Library page decide what counts as a duplicate or a short-track ad
/// stinger. Source-specific settings (metadata credentials, Essentia URL,
/// artist separators) live on their owning plugin's own settings page —
/// see the Plugins entry on the Settings home page.
class LibrarySettingsPage extends StatefulWidget {
  /// Set when opened from `SettingsPage`'s search with a specific row in
  /// mind — that row scrolls into view and flashes once this page mounts.
  final String? highlightField;

  const LibrarySettingsPage({super.key, this.highlightField});

  @override
  State<LibrarySettingsPage> createState() => _LibrarySettingsPageState();
}

class _LibrarySettingsPageState extends State<LibrarySettingsPage> {
  late AppSettings _settings;

  final Map<String, GlobalKey<SettingsHighlightState>> _keys = {
    for (final field in [
      'library_source',
      'library_folder',
      'library_watcher',
      'list_density',
      'group_by_album_artist',
      'short_track_threshold',
    ])
      field: GlobalKey<SettingsHighlightState>(),
  };

  @override
  void initState() {
    super.initState();
    _settings = AppSettings.instance;
    scrollToAndFlashSetting(_keys[widget.highlightField]);
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
          SettingsHighlight(
            key: _keys['library_source'],
            child: ListTile(
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
          ),
          SettingsHighlight(
            key: _keys['library_folder'],
            child: ListTile(
              title: const Text('Folder for library scans'),
              subtitle: Text(
                  settings.selectedFolderPath ?? 'Pick a folder to browse'),
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
          ),
          SettingsHighlight(
            key: _keys['library_watcher'],
            child: SwitchListTile(
              title: const Text('Watch folder for changes'),
              subtitle: const Text(
                  'Automatically rescan shortly after files change in the '
                  'folder above — desktop only, and only takes effect on '
                  'the next app restart'),
              value: settings.libraryWatcherEnabled,
              onChanged: (value) =>
                  setState(() => settings.libraryWatcherEnabled = value),
            ),
          ),
          const SizedBox(height: 16),
          Text('Display', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          SettingsHighlight(
            key: _keys['list_density'],
            child: ListTile(
              title: const Text('List density'),
              subtitle: const Text(
                  'Compact fits more tracks on screen with shorter rows'),
              trailing: DropdownButton<LibraryDensity>(
                value: settings.libraryDensity,
                items: const [
                  DropdownMenuItem(
                      value: LibraryDensity.comfortable,
                      child: Text('Comfortable')),
                  DropdownMenuItem(
                      value: LibraryDensity.compact, child: Text('Compact')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => settings.libraryDensity = value);
                },
              ),
            ),
          ),
          SettingsHighlight(
            key: _keys['group_by_album_artist'],
            child: SwitchListTile(
              title: const Text('Group Artists view by album artist'),
              subtitle: const Text(
                  'Groups a compilation\'s tracks under one album artist '
                  '(e.g. "Various Artists") instead of scattering them '
                  'across each track\'s own listed performer. Only affects '
                  'tracks with an album artist tag — most local files won\'t '
                  'have one until re-tagged or looked up.'),
              value: settings.groupArtistsByAlbumArtist,
              onChanged: (value) =>
                  setState(() => settings.groupArtistsByAlbumArtist = value),
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
          SettingsHighlight(
            key: _keys['short_track_threshold'],
            child: SliderListTile(
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
          ),
        ],
      ),
    );
  }
}
