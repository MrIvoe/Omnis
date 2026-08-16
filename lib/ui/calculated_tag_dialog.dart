import 'package:flutter/material.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/calculated_tags.dart';

String _fieldLabel(CalculatedTagTargetField field) => switch (field) {
      CalculatedTagTargetField.title => 'Title',
      CalculatedTagTargetField.artist => 'Artist',
      CalculatedTagTargetField.album => 'Album',
      CalculatedTagTargetField.genre => 'Genre',
    };

const _tokenHints = [
  'title',
  'artist',
  'album',
  'genre',
  'year',
  'track',
  'disc',
  'bitrate',
  'duration',
  'codec',
  'dateAdded',
  'folderName',
  'fileExtension',
];

/// spec §12's "virtual/calculated tags" gap (item 17) — builds a
/// [CalculatedTagRule] against [tracks] with a live preview of what
/// would change, then hands the confirmed rule back to the caller
/// (`LibraryPage._calculatedTagsSelected`) to actually apply — this
/// dialog never writes a file itself, the same "dialog builds the
/// value, caller applies it" split `TagFindReplaceDialog` already uses.
class CalculatedTagDialog extends StatefulWidget {
  final List<BaseTrack> tracks;

  const CalculatedTagDialog({super.key, required this.tracks});

  static Future<CalculatedTagRule?> show(
    BuildContext context,
    List<BaseTrack> tracks,
  ) {
    return showDialog<CalculatedTagRule>(
      context: context,
      builder: (context) => CalculatedTagDialog(tracks: tracks),
    );
  }

  @override
  State<CalculatedTagDialog> createState() => _CalculatedTagDialogState();
}

class _CalculatedTagDialogState extends State<CalculatedTagDialog> {
  final _templateController = TextEditingController();
  CalculatedTagTargetField _target = CalculatedTagTargetField.title;

  @override
  void dispose() {
    _templateController.dispose();
    super.dispose();
  }

  CalculatedTagRule get _rule => CalculatedTagRule(
        target: _target,
        template: _templateController.text,
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = previewCalculatedTags(widget.tracks, _rule);

    return AlertDialog(
      title: const Text('Virtual / calculated tags'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Target field', style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              DropdownButton<CalculatedTagTargetField>(
                value: _target,
                isExpanded: true,
                items: [
                  for (final field in CalculatedTagTargetField.values)
                    DropdownMenuItem(
                      value: field,
                      child: Text(_fieldLabel(field)),
                    ),
                ],
                onChanged: (value) => setState(() {
                  if (value != null) _target = value;
                }),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _templateController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Template',
                  hintText: '{artist} - {title} [{year}]',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final token in _tokenHints)
                    ActionChip(
                      label: Text('{$token}'),
                      onPressed: () {
                        final selection = _templateController.selection;
                        final text = _templateController.text;
                        final insertAt =
                            selection.isValid ? selection.start : text.length;
                        final newText = text.replaceRange(
                            insertAt, selection.isValid ? selection.end : text.length,
                            '{$token}');
                        _templateController.value = TextEditingValue(
                          text: newText,
                          selection: TextSelection.collapsed(
                              offset: insertAt + token.length + 2),
                        );
                        setState(() {});
                      },
                    ),
                ],
              ),
              const Divider(),
              Text(
                preview.isEmpty
                    ? 'No changes yet.'
                    : '${preview.length} track${preview.length == 1 ? '' : 's'} '
                        'would change:',
                style: theme.textTheme.bodySmall,
              ),
              for (final match in preview.take(20))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(match.track.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    '"${match.before}" → "${match.after}"',
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
