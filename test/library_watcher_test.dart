import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/library_watcher.dart';

FileSystemEvent _event(String path) =>
    FileSystemModifyEvent(path, false, true);

void main() {
  group('LibraryWatcher', () {
    test('fires onSettled once after the quiet period following a '
        'single event', () {
      fakeAsync((async) {
        var settledCount = 0;
        final controller = StreamController<FileSystemEvent>();
        final watcher = LibraryWatcher(
          onSettled: () async => settledCount++,
          watch: (_) => controller.stream,
          quietPeriod: const Duration(seconds: 3),
        );

        watcher.start('/music');
        controller.add(_event('/music/a.mp3'));
        async.elapse(const Duration(seconds: 3));

        expect(settledCount, 1);
      });
    });

    test('coalesces a burst of events into exactly one rescan', () {
      fakeAsync((async) {
        var settledCount = 0;
        final controller = StreamController<FileSystemEvent>();
        final watcher = LibraryWatcher(
          onSettled: () async => settledCount++,
          watch: (_) => controller.stream,
          quietPeriod: const Duration(seconds: 3),
        );

        watcher.start('/music');
        // A batch copy: many events, each resetting the debounce
        // before the quiet period elapses.
        for (var i = 0; i < 20; i++) {
          controller.add(_event('/music/track$i.mp3'));
          async.elapse(const Duration(milliseconds: 500));
        }
        async.elapse(const Duration(seconds: 3));

        expect(settledCount, 1);
      });
    });

    test('does not fire before the quiet period has fully elapsed', () {
      fakeAsync((async) {
        var settledCount = 0;
        final controller = StreamController<FileSystemEvent>();
        final watcher = LibraryWatcher(
          onSettled: () async => settledCount++,
          watch: (_) => controller.stream,
          quietPeriod: const Duration(seconds: 3),
        );

        watcher.start('/music');
        controller.add(_event('/music/a.mp3'));
        async.elapse(const Duration(seconds: 2));

        expect(settledCount, 0);
      });
    });

    test('a second quiet period after new activity fires a second '
        'rescan', () {
      fakeAsync((async) {
        var settledCount = 0;
        final controller = StreamController<FileSystemEvent>();
        final watcher = LibraryWatcher(
          onSettled: () async => settledCount++,
          watch: (_) => controller.stream,
          quietPeriod: const Duration(seconds: 3),
        );

        watcher.start('/music');
        controller.add(_event('/music/a.mp3'));
        async.elapse(const Duration(seconds: 3));
        expect(settledCount, 1);

        controller.add(_event('/music/b.mp3'));
        async.elapse(const Duration(seconds: 3));
        expect(settledCount, 2);
      });
    });

    test('stop() cancels a pending debounced rescan', () {
      fakeAsync((async) {
        var settledCount = 0;
        final controller = StreamController<FileSystemEvent>();
        final watcher = LibraryWatcher(
          onSettled: () async => settledCount++,
          watch: (_) => controller.stream,
          quietPeriod: const Duration(seconds: 3),
        );

        watcher.start('/music');
        controller.add(_event('/music/a.mp3'));
        async.elapse(const Duration(seconds: 1));
        watcher.stop();
        async.elapse(const Duration(seconds: 5));

        expect(settledCount, 0);
      });
    });

    test('isWatching reflects start()/stop() state', () {
      final controller = StreamController<FileSystemEvent>();
      final watcher = LibraryWatcher(
        onSettled: () async {},
        watch: (_) => controller.stream,
      );

      expect(watcher.isWatching, isFalse);
      watcher.start('/music');
      expect(watcher.isWatching, isTrue);
      watcher.stop();
      expect(watcher.isWatching, isFalse);
    });

    test('calling start() again replaces the previous watch rather '
        'than stacking subscriptions', () {
      fakeAsync((async) {
        var firstSettledCount = 0;
        var secondSettledCount = 0;
        final firstController = StreamController<FileSystemEvent>();
        final secondController = StreamController<FileSystemEvent>();
        var callCount = 0;
        final watcher = LibraryWatcher(
          onSettled: () async {
            callCount == 0 ? firstSettledCount++ : secondSettledCount++;
          },
          watch: (_) {
            final stream = callCount == 0
                ? firstController.stream
                : secondController.stream;
            callCount++;
            return stream;
          },
          quietPeriod: const Duration(seconds: 3),
        );

        watcher.start('/music-a');
        watcher.start('/music-b');
        firstController.add(_event('/music-a/a.mp3'));
        async.elapse(const Duration(seconds: 3));

        // The first watch was replaced by start()'s second call, so an
        // event on the now-abandoned first stream must never fire.
        expect(firstSettledCount, 0);
        expect(secondSettledCount, 0);
      });
    });

    test('a watch function that throws degrades to not-watching rather '
        'than propagating the exception', () {
      final watcher = LibraryWatcher(
        onSettled: () async {},
        watch: (_) => throw const FileSystemException('unsupported'),
      );

      expect(() => watcher.start('/music'), returnsNormally);
      expect(watcher.isWatching, isFalse);
    });
  });
}
