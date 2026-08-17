import 'package:flutter/material.dart';
import 'package:omnis/core/command_palette.dart';

/// Opens the item 48/spec §38 command palette. [actions] maps a
/// [PaletteCommand.id] to what running it actually does — kept as a plain
/// `Map` supplied by the caller (`HomePage`) rather than baked into this
/// dialog, so this file stays free of `MainCore`/`AudioEngine`/
/// `AppSettings` dependencies, the same "pure UI shell, caller owns the
/// wiring" split `showDialog`-based helpers elsewhere in this app use. A
/// command with no entry in [actions] is simply not runnable — its row
/// still renders (so the full spec-named list stays visible/searchable)
/// but tapping it does nothing, rather than throwing.
Future<void> showCommandPalette(
  BuildContext context, {
  required Map<String, VoidCallback> actions,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _CommandPaletteDialog(actions: actions),
  );
}

class _CommandPaletteDialog extends StatefulWidget {
  final Map<String, VoidCallback> actions;

  const _CommandPaletteDialog({required this.actions});

  @override
  State<_CommandPaletteDialog> createState() => _CommandPaletteDialogState();
}

class _CommandPaletteDialogState extends State<_CommandPaletteDialog> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _run(PaletteCommand command) {
    Navigator.of(context).pop();
    widget.actions[command.id]?.call();
  }

  @override
  Widget build(BuildContext context) {
    final matches = matchCommands(_query);

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 480),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _controller,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Type a command…',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) => setState(() => _query = value),
                onSubmitted: (_) {
                  if (matches.isNotEmpty) _run(matches.first);
                },
              ),
              const SizedBox(height: 8),
              Flexible(
                child: matches.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text('No commands match "$_query".'),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: matches.length,
                        itemBuilder: (context, index) {
                          final command = matches[index];
                          return ListTile(
                            title: Text(command.title),
                            onTap: () => _run(command),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
