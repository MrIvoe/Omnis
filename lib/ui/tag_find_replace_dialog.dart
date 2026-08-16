import 'package:flutter/material.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/tag_find_replace.dart';

String _fieldLabel(TagFindReplaceField field) => switch (field) {
      TagFindReplaceField.title => 'Title',
      TagFindReplaceField.artist => 'Artist',
      TagFindReplaceField.album => 'Album',
      TagFindReplaceField.genre => 'Genre',
    };

/// spec §12's "regex search/replace" gap (item 17) — builds a
/// [TagFindReplaceRule] against [tracks] with a live preview of what
/// would change, then hands the confirmed rule back to the caller
/// (`LibraryPage._findReplaceSelected`) to actually apply — this dialog
/// never writes a file itself, the same "dialog builds the value,
/// caller applies it" split `_StarPicker`/`_rateTrack` already use.
class TagFindReplaceDialog extends StatefulWidget {
  final List<BaseTrack> tracks;

  const TagFindReplaceDialog({super.key, required this.tracks});

  static Future<TagFindReplaceRule?> show(
    BuildContext context,
    List<BaseTrack> tracks,
  ) {
    return showDialog<TagFindReplaceRule>(
      context: context,
      builder: (context) => TagFindReplaceDialog(tracks: tracks),
    );
  }

  @override
  State<TagFindReplaceDialog> createState() => _TagFindReplaceDialogState();
}

class _TagFindReplaceDialogState extends State<TagFindReplaceDialog> {
  final _findController = TextEditingController();
  final _replaceController = TextEditingController();
  final Set<TagFindReplaceField> _fields = {TagFindReplaceField.title};
  bool _useRegex = false;
  bool _caseSensitive = false;

  @override
  void dispose() {
    _findController.dispose();
    _replaceController.dispose();
    super.dispose();
  }

  TagFindReplaceRule get _rule => TagFindReplaceRule(
        fields: _fields,
        find: _findController.text,
        replace: _replaceController.text,
        useRegex: _useRegex,
        caseSensitive: _caseSensitive,
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = previewFindReplace(widget.tracks, _rule);
    final affectedTracks = preview.map((m) => m.track.id).toSet().length;

    return AlertDialog(
      title: const Text('Find & Replace tags'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Fields', style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                children: [
                  for (final field in TagFindReplaceField.values)
                    FilterChip(
                      label: Text(_fieldLabel(field)),
                      selected: _fields.contains(field),
                      onSelected: (selected) => setState(() {
                        if (selected) {
                          _fields.add(field);
                        } else {
                          _fields.remove(field);
                        }
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _findController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Find'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _replaceController,
                decoration: const InputDecoration(labelText: 'Replace with'),
                onChanged: (_) => setState(() {}),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Use regex'),
                value: _useRegex,
                onChanged: (v) => setState(() => _useRegex = v ?? false),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Case sensitive'),
                value: _caseSensitive,
                onChanged: (v) => setState(() => _caseSensitive = v ?? false),
              ),
              const Divider(),
              Text(
                preview.isEmpty
                    ? 'No changes yet.'
                    : '${preview.length} change${preview.length == 1 ? '' : 's'} '
                        'across $affectedTracks track'
                        '${affectedTracks == 1 ? '' : 's'}:',
                style: theme.textTheme.bodySmall,
              ),
              for (final match in preview.take(20))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(match.track.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    '${_fieldLabel(match.field)}: "${match.before}" → '
                    '"${match.after}"',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (preview.length > 20)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('…and ${preview.length - 20} more.',
                      style: theme.textTheme.bodySmall),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: preview.isEmpty
              ? null
              : () => Navigator.pop(context, _rule),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}
