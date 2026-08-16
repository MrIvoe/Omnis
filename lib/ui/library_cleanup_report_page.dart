import 'package:flutter/material.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/library_cleanup_analyzer.dart';

/// Spec §20's "Music Library Cleanup" report: one "Analyze Library"
/// pass over the already-scanned library ([LibraryCleanupAnalyzer],
/// pure — no new file I/O, no fresh scan), then a category list a user
/// can drill into for guided cleanup. Categories with an obvious direct
/// fix (missing artwork, inconsistent artists/genres, malformed track
/// numbers) delegate to [onEditTags] — `LibraryPage`'s own existing
/// `_editTags`, which already opens the real `TagEditorDialog`, re-reads
/// the file afterward, and persists the change, so this page never
/// duplicates that logic. Duplicate tracks/albums point at `LibraryPage`'s
/// own existing "Find duplicates & short tracks…" tool rather than
/// re-implementing merge/delete a second time; corrupt files are listed
/// read-only, since there's nothing this app can do to repair a file's
/// own header bytes.
///
/// A point-in-time snapshot, deliberately: [tracks] is analyzed once in
/// `initState` and the category lists don't live-update as edits are
/// made — the same "acted on a fixed snapshot, re-run to see fresh
/// results" shape `LibraryPage`'s own duplicates/short-tracks tool
/// already has.
class LibraryCleanupReportPage extends StatefulWidget {
  final List<BaseTrack> tracks;
  final Future<void> Function(BaseTrack track) onEditTags;

  /// Drops [track] from the library without touching disk — used only
  /// by the "missing files" category, where the file is already gone,
  /// unlike every other cleanup action here which edits/merges real
  /// data.
  final Future<void> Function(BaseTrack track) onRemoveFromLibrary;

  const LibraryCleanupReportPage({
    super.key,
    required this.tracks,
    required this.onEditTags,
    required this.onRemoveFromLibrary,
  });

  @override
  State<LibraryCleanupReportPage> createState() =>
      _LibraryCleanupReportPageState();
}

class _LibraryCleanupReportPageState extends State<LibraryCleanupReportPage> {
  late LibraryCleanupReport _report;

  @override
  void initState() {
    super.initState();
    _report = LibraryCleanupAnalyzer.analyze(widget.tracks);
    _loadMissingFiles();
  }

  /// Runs after the initial (synchronous) analysis so the report renders
  /// immediately; missing-file detection's real disk I/O fills in a
  /// beat later and just triggers a rebuild once it resolves — the same
  /// "show what you have now, update when the slower thing finishes"
  /// shape already used elsewhere in this app rather than blocking the
  /// whole report behind it.
  Future<void> _loadMissingFiles() async {
    final missing = await LibraryCleanupAnalyzer.findMissingFiles(widget.tracks);
    if (!mounted) return;
    setState(() => _report = _report.copyWithMissingFiles(missing));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Library Cleanup')),
      body: _report.isClean
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_outline,
                        size: 56, color: theme.colorScheme.primary),
                    const SizedBox(height: 12),
                    const Text('Nothing to clean up — your library looks '
                        'good.'),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Analyze Library', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Tap a category to review and clean up what was found.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
                const SizedBox(height: 12),
                for (final category in _report.categories)
                  Card(
                    child: ListTile(
                      leading: Icon(
                        category.count == 0
                            ? Icons.check_circle_outline
                            : Icons.warning_amber_outlined,
                        color: category.count == 0
                            ? theme.colorScheme.outline
                            : theme.colorScheme.error,
                      ),
                      title: Text('${category.count} ${category.label}'),
                      trailing: category.count == 0
                          ? null
                          : const Icon(Icons.chevron_right),
                      onTap: category.count == 0
                          ? null
                          : () => _openCategory(category.label),
                    ),
                  ),
              ],
            ),
    );
  }

  void _openCategory(String label) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => Scaffold(
        appBar: AppBar(title: Text(_titleCase(label))),
        body: _categoryDetail(label),
      ),
    ));
  }

  String _titleCase(String label) =>
      label.isEmpty ? label : label[0].toUpperCase() + label.substring(1);

  Widget _categoryDetail(String label) {
    switch (label) {
      case 'missing artwork':
        return _trackListWithFix(_report.missingArtwork);
      case 'inconsistent artists':
        return _trackListWithFix(_report.inconsistentArtists,
            subtitleBuilder: (t) =>
                t.artists.isNotEmpty ? t.artists.first : '(no artist)');
      case 'malformed track numbers':
        return _trackListWithFix(_report.malformedTrackNumbers,
            subtitleBuilder: (t) =>
                'Track #${t.trackNumber ?? '(none)'} · ${t.album}');
      case 'inconsistent genres':
        return _trackListWithFix(_report.inconsistentGenres,
            subtitleBuilder: (t) =>
                t.genres.isNotEmpty ? t.genres.first : '(no genre)');
      case 'duplicate tracks':
        return _groupList(_report.duplicateTrackGroups,
            hint: 'Use "Find duplicates & short tracks…" from the Library '
                'page\'s tools menu to review and merge these.');
      case 'duplicate albums':
        return _groupList(_report.duplicateAlbumGroups,
            hint: 'These look like the same album saved under slightly '
                'different spellings. Edit tags on each track below so '
                'they all share one exact album name.',
            trackAction: widget.onEditTags);
      case 'albums missing year':
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final album in _report.albumsMissingYear)
              Card(child: ListTile(title: Text(album))),
          ],
        );
      case 'corrupt files':
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'These files have a recognized extension but their header '
                "couldn't be read — possibly corrupt, or scanned before "
                'format detection existed. A re-scan may resolve the '
                'latter case.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            for (final track in _report.corruptFiles)
              Card(
                child: ListTile(
                  title: Text(track.title),
                  subtitle: Text(track.localPath ?? ''),
                ),
              ),
          ],
        );
      case 'missing files':
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                "These tracks' files couldn't be found — moved, renamed, "
                'or deleted outside Omnis since the last scan. Removing '
                "one here only drops its library entry; there's no file "
                'left to delete.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            for (final track in _report.missingFiles)
              Card(
                child: ListTile(
                  title: Text(track.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(track.localPath ?? '',
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: TextButton(
                    onPressed: () => widget.onRemoveFromLibrary(track),
                    child: const Text('Remove'),
                  ),
                ),
              ),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _trackListWithFix(
    List<BaseTrack> tracks, {
    String Function(BaseTrack)? subtitleBuilder,
  }) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final track in tracks)
          Card(
            child: ListTile(
              title: Text(track.title,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                subtitleBuilder?.call(track) ?? track.album,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: TextButton(
                onPressed: () => widget.onEditTags(track),
                child: const Text('Edit tags'),
              ),
            ),
          ),
      ],
    );
  }

  Widget _groupList(
    List<List<BaseTrack>> groups, {
    required String hint,
    Future<void> Function(BaseTrack)? trackAction,
  }) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(hint, style: Theme.of(context).textTheme.bodySmall),
        ),
        for (final group in groups)
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final track in group)
                    ListTile(
                      dense: true,
                      title: Text(track.title,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        '${track.artists.isNotEmpty ? track.artists.first : ''} '
                        '· ${track.album}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: trackAction == null
                          ? null
                          : TextButton(
                              onPressed: () => trackAction(track),
                              child: const Text('Edit tags'),
                            ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
