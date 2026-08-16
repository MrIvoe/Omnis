import 'dart:io' show File, Platform;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/core/backup_service.dart';
import 'package:omnis/core/library_repository.dart';

/// Backup/restore of the core persisted stores (§41/§48 of the Omnis
/// 2.0 product spec). Deliberately simple — two actions, not a page full
/// of toggles — because [BackupService] itself is where the actual
/// safety guarantees live; this page's whole job is to get the user's
/// confirmation before a destructive restore and show them what
/// happened, in plain language, never a raw exception.
class BackupSettingsPage extends StatefulWidget {
  const BackupSettingsPage({super.key});

  @override
  State<BackupSettingsPage> createState() => _BackupSettingsPageState();
}

class _BackupSettingsPageState extends State<BackupSettingsPage> {
  final _service = BackupService();
  late final AppSettings _settings = AppSettings.instance;
  bool _busy = false;

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  String get _lastAutoBackupLabel {
    final last = _settings.lastAutoBackupAt;
    if (last == null) return 'Never yet';
    return last.toLocal().toString().split('.').first;
  }

  /// `file_picker`'s `saveFile` writes the bytes itself on Android/iOS
  /// (required there); on desktop it only returns the chosen path, so
  /// this writes the file itself in that case — same split
  /// `playlist_page.dart`'s M3U export already handles.
  Future<void> _backup() async {
    setState(() => _busy = true);
    try {
      final bytes = await _service.createBackup();
      final stamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Omnis backup',
        fileName: 'omnis-backup-$stamp.zip',
        type: FileType.custom,
        allowedExtensions: ['zip'],
        bytes: bytes,
      );
      if (path == null) return; // user cancelled the save dialog
      if (!kIsWeb && !Platform.isAndroid && !Platform.isIOS) {
        await File(path).writeAsBytes(bytes);
      }
      _snack('Backup saved.');
    } catch (e) {
      _snack('Could not create a backup: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    // Everything — including the picker call itself, which can throw on
    // a platform without the plugin properly available, not just the
    // restore logic after it — goes through one try/catch, the same
    // "never let a real failure surface as an uncaught exception"
    // contract _backup() already has.
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
        withData: true,
      );
      final picked0 = picked?.files.single;
      if (picked0 == null || !mounted) return;

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Restore this backup?'),
          content: const Text(
            'This replaces your current library, playlists, play history, '
            'and recovery journal with the contents of this backup. '
            'Nothing is changed unless the backup file itself checks out '
            '— but once it does, this cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Restore'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;

      setState(() => _busy = true);
      final bytes = picked0.bytes ??
          (picked0.path != null
              ? await File(picked0.path!).readAsBytes()
              : null);
      if (bytes == null) {
        _snack("Couldn't read that file.");
        return;
      }

      final result = await _service.restoreBackup(bytes);
      if (!mounted) return;
      if (!result.success) {
        _snack('Restore failed — nothing was changed: ${result.error}');
        return;
      }

      // The library is the one store already cached in memory
      // (LibraryRepository) with listeners across several pages — refresh
      // it so this page's own change is visible without waiting on a
      // restart. Playlists/play-history/the recovery journal aren't
      // cached this way (each page/store re-reads from disk on its own
      // schedule), so a full restart is still the honest answer for
      // those — no attempt here to hunt down and refresh every other
      // page's own in-memory state piecemeal.
      await LibraryRepository.instance.load(forceReload: true);

      _snack(result.restoredFiles.isEmpty
          ? 'Restored — the backup had nothing to restore.'
          : 'Restored ${result.restoredFiles.length} file(s). Restart '
              'Omnis for the changes to fully take effect.');
    } catch (e) {
      _snack('Restore failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Backup')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Back up your library', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            'Saves your library, playlists, play history, and recovery '
            'journal to one file. Settings, themes, layouts, and plugin '
            'credentials are not included.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.backup_outlined),
              title: const Text('Backup Omnis'),
              subtitle: const Text('Save everything to a file you choose'),
              trailing: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.chevron_right),
              onTap: _busy ? null : _backup,
            ),
          ),
          const SizedBox(height: 24),
          Text('Restore a backup', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            'The backup file is fully checked before anything is changed — '
            'a corrupt or unrecognized file leaves your current library '
            'untouched.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.restore_outlined),
              title: const Text('Restore Omnis'),
              subtitle: const Text('Replace everything with a backup file'),
              trailing: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.chevron_right),
              onTap: _busy ? null : _restore,
            ),
          ),
          const SizedBox(height: 24),
          Text('Automatic backups', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            'Runs the same backup as above on its own, on a schedule, '
            'straight to app storage — no file picker, and it keeps the '
            'last ${BackupService.autoBackupKeepCount} automatic backups.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Enable automatic backups'),
                  value: _settings.autoBackupEnabled,
                  onChanged: (value) =>
                      setState(() => _settings.autoBackupEnabled = value),
                ),
                if (_settings.autoBackupEnabled) ...[
                  ListTile(
                    title: const Text('Frequency'),
                    trailing: DropdownButton<int>(
                      value: _settings.autoBackupIntervalDays,
                      items: const [
                        DropdownMenuItem(value: 1, child: Text('Daily')),
                        DropdownMenuItem(value: 7, child: Text('Weekly')),
                        DropdownMenuItem(value: 30, child: Text('Monthly')),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(
                            () => _settings.autoBackupIntervalDays = value);
                      },
                    ),
                  ),
                  ListTile(
                    title: const Text('Last automatic backup'),
                    subtitle: Text(_lastAutoBackupLabel),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
