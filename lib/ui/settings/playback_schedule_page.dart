import 'package:flutter/material.dart';
import 'package:omnis/core/custom_radio_station_store.dart';
import 'package:omnis/core/playback_schedule.dart';
import 'package:omnis/core/playlist_store.dart';

const _weekdayLabels = {
  1: 'Mon',
  2: 'Tue',
  3: 'Wed',
  4: 'Thu',
  5: 'Fri',
  6: 'Sat',
  7: 'Sun',
};

String _formatTime(int minuteOfDay) {
  final hour = minuteOfDay ~/ 60;
  final minute = minuteOfDay % 60;
  final period = hour < 12 ? 'AM' : 'PM';
  final displayHour = hour % 12 == 0 ? 12 : hour % 12;
  return '$displayHour:${minute.toString().padLeft(2, '0')} $period';
}

String _formatWeekdays(Set<int> weekdays) {
  if (weekdays.length == 7) return 'Every day';
  if (weekdays.isEmpty) return 'Never';
  final ordered = weekdays.toList()..sort();
  return ordered.map((d) => _weekdayLabels[d]).join(', ');
}

/// Scheduled playback (MusicBee comparison §43): recurring "start
/// playback at this time, on these days" triggers, distinct from the
/// countdown-only sleep timer. One concrete, narrowly-scoped trigger
/// type — not a general automation-rules engine (item 50's larger,
/// still-deferred ask).
class PlaybackSchedulePage extends StatefulWidget {
  const PlaybackSchedulePage({super.key});

  @override
  State<PlaybackSchedulePage> createState() => _PlaybackSchedulePageState();
}

class _PlaybackSchedulePageState extends State<PlaybackSchedulePage> {
  List<PlaybackSchedule> _schedules = const [];
  List<Playlist> _playlists = const [];
  List<CustomRadioStation> _stations = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final schedules = await PlaybackScheduleStore.instance.load();
    final playlists = await PlaylistStore.instance.load();
    final stations = await CustomRadioStationStore.instance.load();
    if (!mounted) return;
    setState(() {
      _schedules = schedules;
      _playlists = playlists;
      _stations = stations;
      _loading = false;
    });
  }

  String? _playlistName(String? playlistId) {
    if (playlistId == null) return null;
    for (final p in _playlists) {
      if (p.id == playlistId) return p.name;
    }
    return null;
  }

  String? _stationName(String? radioStationId) {
    if (radioStationId == null) return null;
    for (final s in _stations) {
      if (s.id == radioStationId) return s.name;
    }
    return null;
  }

  Future<void> _addSchedule() async {
    final created = await _openEditor(context,
        playlists: _playlists, stations: _stations);
    if (created == null) return;
    final updated = await PlaybackScheduleStore.instance.add(created);
    if (!mounted) return;
    setState(() => _schedules = updated);
  }

  Future<void> _editSchedule(PlaybackSchedule schedule) async {
    final result = await _openEditor(context,
        existing: schedule, playlists: _playlists, stations: _stations);
    if (result == null) return;
    final updated = await PlaybackScheduleStore.instance.update(result);
    if (!mounted) return;
    setState(() => _schedules = updated);
  }

  Future<void> _toggleEnabled(PlaybackSchedule schedule, bool value) async {
    final updated = await PlaybackScheduleStore.instance
        .update(schedule.copyWith(enabled: value));
    if (!mounted) return;
    setState(() => _schedules = updated);
  }

  Future<void> _deleteSchedule(PlaybackSchedule schedule) async {
    final updated = await PlaybackScheduleStore.instance.delete(schedule.id);
    if (!mounted) return;
    setState(() => _schedules = updated);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Scheduled Playback')),
      floatingActionButton: FloatingActionButton(
        onPressed: _addSchedule,
        tooltip: 'Add schedule',
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _schedules.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'No schedules yet. Add one to start playback '
                      'automatically at a set time.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: _schedules.length,
                  itemBuilder: (context, index) {
                    final schedule = _schedules[index];
                    final playlistName = _playlistName(schedule.playlistId);
                    final stationName = _stationName(schedule.radioStationId);
                    final actionLabel =
                        schedule.action == PlaybackScheduleAction.stop
                            ? 'Stops playback'
                            : playlistName != null
                                ? 'Plays $playlistName'
                                : schedule.radioStationId != null
                                    ? 'Plays radio: '
                                        '${stationName ?? '(deleted station)'}'
                                    : 'Resumes current queue';
                    return Card(
                      child: ListTile(
                        title: Text(schedule.name),
                        subtitle: Text(
                          '${_formatTime(schedule.minuteOfDay)} · '
                          '${_formatWeekdays(schedule.weekdays)} · '
                          '$actionLabel',
                        ),
                        leading: Switch(
                          value: schedule.enabled,
                          onChanged: (value) =>
                              _toggleEnabled(schedule, value),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Delete',
                          onPressed: () => _deleteSchedule(schedule),
                        ),
                        onTap: () => _editSchedule(schedule),
                      ),
                    );
                  },
                ),
    );
  }
}

Future<PlaybackSchedule?> _openEditor(
  BuildContext context, {
  PlaybackSchedule? existing,
  required List<Playlist> playlists,
  required List<CustomRadioStation> stations,
}) {
  return showDialog<PlaybackSchedule>(
    context: context,
    builder: (context) => _ScheduleEditorDialog(
        existing: existing, playlists: playlists, stations: stations),
  );
}

class _ScheduleEditorDialog extends StatefulWidget {
  final PlaybackSchedule? existing;
  final List<Playlist> playlists;
  final List<CustomRadioStation> stations;

  const _ScheduleEditorDialog(
      {this.existing, required this.playlists, required this.stations});

  @override
  State<_ScheduleEditorDialog> createState() => _ScheduleEditorDialogState();
}

class _ScheduleEditorDialogState extends State<_ScheduleEditorDialog> {
  late final TextEditingController _nameController;
  late int _minuteOfDay;
  late Set<int> _weekdays;
  String? _playlistId;
  String? _radioStationId;
  late PlaybackScheduleAction _action;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameController = TextEditingController(text: existing?.name ?? '');
    _minuteOfDay = existing?.minuteOfDay ?? (8 * 60);
    _weekdays = Set<int>.of(existing?.weekdays ?? const {1, 2, 3, 4, 5});
    _playlistId = existing?.playlistId;
    _radioStationId = existing?.radioStationId;
    _action = existing?.action ?? PlaybackScheduleAction.play;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime:
          TimeOfDay(hour: _minuteOfDay ~/ 60, minute: _minuteOfDay % 60),
    );
    if (picked == null) return;
    setState(() => _minuteOfDay = picked.hour * 60 + picked.minute);
  }

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty || _weekdays.isEmpty) return;
    final existing = widget.existing;
    final schedule = PlaybackSchedule(
      id: existing?.id ?? 'schedule_${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      minuteOfDay: _minuteOfDay,
      weekdays: _weekdays,
      enabled: existing?.enabled ?? true,
      // playlistId/radioStationId are meaningless for a stop schedule —
      // never persisted for one, so a schedule switched from Play to
      // Stop doesn't carry a stale, unused reference along with it.
      playlistId: _action == PlaybackScheduleAction.stop ? null : _playlistId,
      radioStationId:
          _action == PlaybackScheduleAction.stop ? null : _radioStationId,
      action: _action,
      createdAt: existing?.createdAt ?? DateTime.now(),
    );
    Navigator.pop(context, schedule);
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _nameController.text.trim().isNotEmpty &&
        _weekdays.isNotEmpty;
    return AlertDialog(
      title: Text(widget.existing == null ? 'New schedule' : 'Edit schedule'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Name'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Time'),
              trailing: Text(_formatTime(_minuteOfDay)),
              onTap: _pickTime,
            ),
            const SizedBox(height: 8),
            SegmentedButton<PlaybackScheduleAction>(
              segments: const [
                ButtonSegment(
                  value: PlaybackScheduleAction.play,
                  label: Text('Play'),
                  icon: Icon(Icons.play_arrow),
                ),
                ButtonSegment(
                  value: PlaybackScheduleAction.stop,
                  label: Text('Stop'),
                  icon: Icon(Icons.stop),
                ),
              ],
              selected: {_action},
              onSelectionChanged: (selection) =>
                  setState(() => _action = selection.first),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final day in _weekdayLabels.entries)
                  FilterChip(
                    label: Text(day.value),
                    selected: _weekdays.contains(day.key),
                    onSelected: (selected) => setState(() {
                      if (selected) {
                        _weekdays.add(day.key);
                      } else {
                        _weekdays.remove(day.key);
                      }
                    }),
                  ),
              ],
            ),
            // Meaningless for a Stop schedule — there's no queue to
            // replace when the action is just "pause," so the picker
            // only shows up for Play. One flat dropdown covers all
            // three kinds of target (resume/playlist/radio station) via
            // prefixed values, rather than a second selector widget —
            // selecting one always clears the other, enforcing mutual
            // exclusivity here even though the model itself
            // (PlaybackSchedule) stays permissive about both being set.
            if (_action == PlaybackScheduleAction.play) ...[
              const SizedBox(height: 16),
              DropdownButtonFormField<String?>(
                value: _playlistId != null
                    ? 'playlist:$_playlistId'
                    : _radioStationId != null
                        ? 'radio:$_radioStationId'
                        : null,
                decoration: const InputDecoration(
                    labelText: 'Playlist or station (optional)'),
                items: [
                  const DropdownMenuItem<String?>(
                      value: null, child: Text('Resume current queue')),
                  for (final playlist in widget.playlists)
                    DropdownMenuItem<String?>(
                      value: 'playlist:${playlist.id}',
                      child: Text(playlist.name),
                    ),
                  for (final station in widget.stations)
                    DropdownMenuItem<String?>(
                      value: 'radio:${station.id}',
                      child: Text('${station.name} (radio)'),
                    ),
                ],
                onChanged: (value) => setState(() {
                  if (value == null) {
                    _playlistId = null;
                    _radioStationId = null;
                  } else if (value.startsWith('playlist:')) {
                    _playlistId = value.substring('playlist:'.length);
                    _radioStationId = null;
                  } else if (value.startsWith('radio:')) {
                    _radioStationId = value.substring('radio:'.length);
                    _playlistId = null;
                  }
                }),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: canSave ? _save : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
