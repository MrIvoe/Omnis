import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/playlist_folder_store.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Fake path_provider that returns a temp directory, same pattern as
/// playlist_store_test.dart.
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String tempDir;

  _FakePathProvider(this.tempDir);

  @override
  Future<String?> getApplicationDocumentsPath() async => tempDir;

  @override
  Future<String?> getApplicationSupportPath() async => tempDir;

  @override
  Future<String?> getTemporaryPath() async => tempDir;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late String tempDir;

  // PlaylistFolderStore.instance caches its resolved file path for the
  // whole process after the first load()/save() call — same as
  // PlaylistStore/LibraryStore.
  setUpAll(() async {
    tempDir = (await Directory.systemTemp.createTemp('omnis_folders_test'))
        .path;
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
  });

  tearDown(() async {
    await PlaylistFolderStore.instance.save(PlaylistFolderData.empty);
  });

  test('load() returns empty data when nothing has ever been saved',
      () async {
    final data = await PlaylistFolderStore.instance.load();

    expect(data.folders, isEmpty);
    expect(data.assignments, isEmpty);
  });

  test('saves and reloads folders and assignments', () async {
    const data = PlaylistFolderData(
      folders: [
        PlaylistFolder(id: 'f1', name: 'Road Trips'),
        PlaylistFolder(id: 'f2', name: 'Chill'),
      ],
      assignments: {'p1': 'f1', 'p2': 'f1', 'p3': 'f2'},
    );

    await PlaylistFolderStore.instance.save(data);
    final loaded = await PlaylistFolderStore.instance.load();

    expect(loaded.folders.map((f) => f.name), ['Road Trips', 'Chill']);
    expect(loaded.assignments, {'p1': 'f1', 'p2': 'f1', 'p3': 'f2'});
  });

  test('tolerates corrupt JSON', () async {
    final f = File('$tempDir/omnis_playlist_folders.json');
    await f.writeAsString('not valid json {{{');

    final data = await PlaylistFolderStore.instance.load();

    expect(data.folders, isEmpty);
    expect(data.assignments, isEmpty);
  });

  test('a single malformed folder record among many valid ones is '
      'skipped, not fatal to every other folder', () async {
    final f = File('$tempDir/omnis_playlist_folders.json');
    // PlaylistFolder.fromJson hard-casts id/name and throws when missing.
    await f.writeAsString(jsonEncode({
      'schemaVersion': 1,
      'data': {
        'folders': [
          {'id': 'f1', 'name': 'Good One'},
          <String, dynamic>{},
          {'id': 'f2', 'name': 'Good Two'},
        ],
        'assignments': <String, String>{},
      },
    }));

    final loaded = await PlaylistFolderStore.instance.load();

    expect(loaded.folders.map((f) => f.name).toSet(), {'Good One', 'Good Two'},
        reason: 'every other folder must not be lost over one bad record');
  });

  test('an assignment entry with a non-string key or value is skipped '
      'rather than crashing the whole load', () async {
    final f = File('$tempDir/omnis_playlist_folders.json');
    await f.writeAsString(jsonEncode({
      'schemaVersion': 1,
      'data': {
        'folders': <Map<String, dynamic>>[],
        'assignments': {'p1': 'f1', 'p2': 5},
      },
    }));

    final loaded = await PlaylistFolderStore.instance.load();

    expect(loaded.assignments, {'p1': 'f1'});
  });

  test('a pre-existing bare (unversioned) file still loads correctly',
      () async {
    final f = File('$tempDir/omnis_playlist_folders.json');
    await f.writeAsString(jsonEncode({
      'folders': [
        {'id': 'f1', 'name': 'Legacy Folder'},
      ],
      'assignments': {'p1': 'f1'},
    }));

    final loaded = await PlaylistFolderStore.instance.load();

    expect(loaded.folders.single.name, 'Legacy Folder');
    expect(loaded.assignments, {'p1': 'f1'});
  });

  test('save() writes atomically — no leftover .tmp file, and the real '
      'file always has the latest complete content', () async {
    await PlaylistFolderStore.instance.save(const PlaylistFolderData(
      folders: [PlaylistFolder(id: 'f1', name: 'Road Trips')],
      assignments: {'p1': 'f1'},
    ));

    final tmp = File('$tempDir/omnis_playlist_folders.json.tmp');
    expect(await tmp.exists(), isFalse,
        reason: 'the .tmp file must be renamed away, never left behind');
    final real = File('$tempDir/omnis_playlist_folders.json');
    expect(await real.exists(), isTrue);
    final loaded = await PlaylistFolderStore.instance.load();
    expect(loaded.folders, hasLength(1));
  });
}
