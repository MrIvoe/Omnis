import 'package:flutter/material.dart';
import 'package:omnis/core/audio_engine.dart';
import 'package:omnis/core/queue_history_store.dart';

/// Spec §7's "Queue history" and "Queue snapshots" — a flat, newest-
/// first list of past queues, distinguishing an automatically-recorded
/// history entry (a rolling log, capped by
/// [QueueHistoryStore.maxAutoHistoryEntries]) from a user-named
/// snapshot (kept forever until explicitly deleted) purely by whether
/// [QueueHistoryEntry.name] is set. Restoring replaces the live queue
/// outright (`AudioEngine.setQueue`) rather than merging — the same
/// "you asked for this queue" contract every other queue-replacing
/// action in this app already has.
class QueueHistoryPage extends StatefulWidget {
  final AudioEngine engine;

  const QueueHistoryPage({super.key, required this.engine});

  @override
  State<QueueHistoryPage> createState() => _QueueHistoryPageState();
}

class _QueueHistoryPageState extends State<QueueHistoryPage> {
  List<QueueHistoryEntry> _entries = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await QueueHistoryStore.instance.load();
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  Future<void> _restore(QueueHistoryEntry entry) async {
    if (entry.tracks.isEmpty) return;
    await widget.engine.setQueue(entry.tracks);
    await widget.engine.play();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
          'Restored "${entry.name ?? _describe(entry)}" (${entry.tracks.length} '
          'track${entry.tracks.length == 1 ? '' : 's'}).'),
    ));
  }

  Future<void> _delete(QueueHistoryEntry entry) async {
    final updated = await QueueHistoryStore.instance.deleteEntry(entry.id);
    if (!mounted) return;
    setState(() => _entries = updated);
  }

  String _describe(QueueHistoryEntry entry) {
    if (entry.tracks.isEmpty) return 'Empty queue';
    final first = entry.tracks.first.title;
    final rest = entry.tracks.length - 1;
    return rest <= 0 ? first : '$first and $rest more';
  }

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    }
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Queue History')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.history,
                            size: 56, color: theme.colorScheme.outline),
                        const SizedBox(height: 12),
                        const Text('No past queues yet.'),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: _entries.length,
                  itemBuilder: (context, index) {
                    final entry = _entries[index];
                    return Card(
                      child: ListTile(
                        leading: Icon(
                            entry.isSnapshot ? Icons.bookmark : Icons.history),
                        title: Text(
                          entry.name ?? _describe(entry),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${entry.tracks.length} track'
                          '${entry.tracks.length == 1 ? '' : 's'} · '
                          '${_relativeTime(entry.createdAt)}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.play_arrow),
                              tooltip: 'Restore this queue',
                              onPressed: entry.tracks.isEmpty
                                  ? null
                                  : () => _restore(entry),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              tooltip: 'Delete',
                              onPressed: () => _delete(entry),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
