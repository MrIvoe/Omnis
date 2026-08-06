import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/plugins/tag_editor_plugin.dart';
import 'package:omnis/ui/widgets/track_artwork.dart';

/// Manual tag editor: every field [TagEditorPlugin] can read or write for
/// one track, plus artwork and freeform custom fields — not just
/// title/artist/album. Fields the file doesn't have yet start blank, not
/// hidden; the same dialog works for a fully-tagged file and a completely
/// untagged one.
class TagEditorDialog extends StatefulWidget {
  final BaseTrack track;
  final TagEditorPlugin plugin;

  const TagEditorDialog({super.key, required this.track, required this.plugin});

  /// Shows the dialog and returns `true` if the file's tags were changed
  /// (so the caller knows to re-read them into its own track list). Takes
  /// the *registered* [plugin] instance rather than constructing its own
  /// — disabling Tag Editor in Settings must actually stop this dialog
  /// from being reachable, not just hide an unrelated toggle.
  static Future<bool> show(
    BuildContext context,
    BaseTrack track, {
    required TagEditorPlugin plugin,
  }) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (context) => TagEditorDialog(track: track, plugin: plugin),
    );
    return changed ?? false;
  }

  @override
  State<TagEditorDialog> createState() => _TagEditorDialogState();
}

/// (fieldKey, label) pairs for every named field [TagEditorPlugin.writeTags]
/// actually supports — the fields this editor can both show and save.
const _coreFields = [
  ('title', 'Title'),
  ('artist', 'Artist'),
  ('albumArtist', 'Album artist'),
  ('album', 'Album'),
  ('genre', 'Genre'),
  ('year', 'Year'),
  ('track', 'Track #'),
  ('disc', 'Disc #'),
  ('composer', 'Composer'),
  ('comment', 'Comment'),
  ('bpm', 'BPM'),
  ('initialKey', 'Key'),
  ('mood', 'Mood'),
];

class _TagEditorDialogState extends State<TagEditorDialog> {
  TagEditorPlugin get _plugin => widget.plugin;
  final Map<String, TextEditingController> _controllers = {
    for (final f in _coreFields) f.$1: TextEditingController(),
  };
  final List<(TextEditingController, TextEditingController)> _extraRows = [];

  bool _loading = true;
  bool _saving = false;
  Uint8List? _newArtwork;
  List<TagFrame> _otherFrames = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    for (final (key, value) in _extraRows) {
      key.dispose();
      value.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final path = widget.track.localPath;
    final tags =
        path != null ? await _plugin.readTags(path) : const TrackTags([]);
    if (!mounted) return;

    _controllers['title']!.text = tags.title ?? widget.track.title;
    _controllers['artist']!.text =
        tags.artist ?? widget.track.artists.join(', ');
    _controllers['albumArtist']!.text = tags.albumArtist ?? '';
    _controllers['album']!.text = tags.album ?? widget.track.album;
    _controllers['genre']!.text =
        tags.genre ?? widget.track.genres.join(', ');
    _controllers['year']!.text =
        tags.year ?? widget.track.year?.toString() ?? '';
    _controllers['track']!.text =
        tags.track ?? widget.track.trackNumber?.toString() ?? '';
    _controllers['disc']!.text =
        tags.disc ?? widget.track.discNumber?.toString() ?? '';
    _controllers['composer']!.text = tags.composer ?? '';
    _controllers['comment']!.text = tags.comment ?? '';
    _controllers['bpm']!.text =
        tags.bpm ?? widget.track.bpm?.toString() ?? '';
    _controllers['initialKey']!.text = tags.initialKey ?? widget.track.key ?? '';
    _controllers['mood']!.text = tags.mood ?? widget.track.mood ?? '';

    const customKeys = [
      CustomTagKeys.genre,
      CustomTagKeys.year,
      CustomTagKeys.track,
      CustomTagKeys.disc,
      CustomTagKeys.composer,
      CustomTagKeys.comment,
      CustomTagKeys.albumArtist,
      CustomTagKeys.bpm,
      CustomTagKeys.initialKey,
      CustomTagKeys.mood,
    ];
    // Native frame ids each core field falls back to (see TrackTags'
    // getters) — excluded too, so a file tagged by other software doesn't
    // show the same value twice (once as the field above, once as an
    // "other tag").
    const nativeFallbackIds = {
      'TCON', 'TYER', 'TDRC', 'TRCK', 'TPOS', 'TCOM', 'COMM', 'TPE2',
      'TBPM', 'TKEY', 'TMOO',
    };
    final knownIds = <String>{
      'TIT2', 'TPE1', 'TALB', 'APIC',
      ...nativeFallbackIds,
      for (final key in customKeys) 'TXXX:$key',
    };
    setState(() {
      _otherFrames =
          tags.frames.where((f) => !f.isArtwork && !knownIds.contains(f.id)).toList();
      _loading = false;
    });
  }

  Future<void> _pickArtwork() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final bytes = result?.files.single.bytes;
    if (bytes == null) return;
    setState(() => _newArtwork = Uint8List.fromList(bytes));
  }

  void _addExtraRow() {
    setState(() => _extraRows
        .add((TextEditingController(), TextEditingController())));
  }

  void _removeExtraRow(int index) {
    final (key, value) = _extraRows[index];
    key.dispose();
    value.dispose();
    setState(() => _extraRows.removeAt(index));
  }

  String? _emptyToNull(String text) {
    final trimmed = text.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<void> _save() async {
    final path = widget.track.localPath;
    if (path == null) {
      Navigator.pop(context, false);
      return;
    }
    setState(() => _saving = true);

    final extra = <String, String>{
      for (final (key, value) in _extraRows)
        if (key.text.trim().isNotEmpty) key.text.trim().toUpperCase(): value.text,
    };

    final ok = await _plugin.writeTags(
      path,
      title: _emptyToNull(_controllers['title']!.text) ?? widget.track.title,
      artist: _emptyToNull(_controllers['artist']!.text) ??
          widget.track.artists.join(', '),
      album: _emptyToNull(_controllers['album']!.text) ?? widget.track.album,
      albumArtist: _emptyToNull(_controllers['albumArtist']!.text),
      genre: _emptyToNull(_controllers['genre']!.text),
      year: _emptyToNull(_controllers['year']!.text),
      track: _emptyToNull(_controllers['track']!.text),
      disc: _emptyToNull(_controllers['disc']!.text),
      composer: _emptyToNull(_controllers['composer']!.text),
      comment: _emptyToNull(_controllers['comment']!.text),
      bpm: _emptyToNull(_controllers['bpm']!.text),
      initialKey: _emptyToNull(_controllers['initialKey']!.text),
      mood: _emptyToNull(_controllers['mood']!.text),
      artworkBytes: _newArtwork,
      extraFields: extra.isEmpty ? null : extra,
    );

    ArtworkProvider.invalidate(widget.track.id);
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.pop(context, ok);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final noFile = widget.track.localPath == null;

    return AlertDialog(
      title: Text('Edit tags — ${widget.track.title}'),
      content: SizedBox(
        width: 420,
        height: 480,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : noFile
                ? const Center(
                    child: Text('This track has no local file to tag.'))
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Stack(
                            alignment: Alignment.bottomRight,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: _newArtwork != null
                                    ? Image.memory(_newArtwork!,
                                        width: 96, height: 96, fit: BoxFit.cover)
                                    : TrackArtwork(
                                        track: widget.track,
                                        width: 96,
                                        height: 96,
                                      ),
                              ),
                              IconButton.filledTonal(
                                icon: const Icon(Icons.edit, size: 16),
                                tooltip: 'Change artwork',
                                onPressed: _pickArtwork,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        for (final field in _coreFields) ...[
                          TextField(
                            controller: _controllers[field.$1],
                            decoration: InputDecoration(
                              labelText: field.$2,
                              border: const OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Text('Custom fields',
                                  style: theme.textTheme.titleSmall),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add),
                              tooltip: 'Add a custom field',
                              onPressed: _addExtraRow,
                            ),
                          ],
                        ),
                        for (var i = 0; i < _extraRows.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: TextField(
                                    controller: _extraRows[i].$1,
                                    decoration: const InputDecoration(
                                      labelText: 'Key',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 3,
                                  child: TextField(
                                    controller: _extraRows[i].$2,
                                    decoration: const InputDecoration(
                                      labelText: 'Value',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline),
                                  onPressed: () => _removeExtraRow(i),
                                ),
                              ],
                            ),
                          ),
                        if (_otherFrames.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text('Other tags found in this file',
                              style: theme.textTheme.titleSmall),
                          const SizedBox(height: 4),
                          Text(
                            'Read-only — not one of the fields above, so '
                            'editing it here isn\'t supported yet.',
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(height: 4),
                          for (final frame in _otherFrames)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Text('${frame.label}: ${frame.value ?? ''}',
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                            ),
                        ],
                      ],
                    ),
                  ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: (_saving || _loading || noFile) ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }
}
