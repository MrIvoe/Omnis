import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/event_bus.dart';

class _TrackFavorited {
  final String trackId;
  const _TrackFavorited(this.trackId);
}

class _TrackUnfavorited {
  final String trackId;
  const _TrackUnfavorited(this.trackId);
}

void main() {
  test('a subscriber receives an event emitted after it subscribed', () async {
    final bus = EventBus();
    final received = <_TrackFavorited>[];
    final sub = bus.on<_TrackFavorited>().listen(received.add);

    bus.emit(const _TrackFavorited('t1'));
    await Future<void>.delayed(Duration.zero);

    expect(received, [isA<_TrackFavorited>()]);
    expect(received.single.trackId, 't1');
    await sub.cancel();
  });

  test('matching is by exact type — a listener for one event type never '
      'receives an unrelated one', () async {
    final bus = EventBus();
    final favorited = <_TrackFavorited>[];
    final unfavorited = <_TrackUnfavorited>[];
    final subs = [
      bus.on<_TrackFavorited>().listen(favorited.add),
      bus.on<_TrackUnfavorited>().listen(unfavorited.add),
    ];

    bus.emit(const _TrackFavorited('t1'));
    bus.emit(const _TrackUnfavorited('t2'));
    await Future<void>.delayed(Duration.zero);

    expect(favorited, hasLength(1));
    expect(favorited.single.trackId, 't1');
    expect(unfavorited, hasLength(1));
    expect(unfavorited.single.trackId, 't2');
    for (final sub in subs) {
      await sub.cancel();
    }
  });

  test('multiple subscribers to the same type all receive the event', () async {
    final bus = EventBus();
    final a = <_TrackFavorited>[];
    final b = <_TrackFavorited>[];
    final subs = [
      bus.on<_TrackFavorited>().listen(a.add),
      bus.on<_TrackFavorited>().listen(b.add),
    ];

    bus.emit(const _TrackFavorited('t1'));
    await Future<void>.delayed(Duration.zero);

    expect(a, hasLength(1));
    expect(b, hasLength(1));
    for (final sub in subs) {
      await sub.cancel();
    }
  });

  test('emit after dispose is a harmless no-op, not a throw', () async {
    final bus = EventBus();
    await bus.dispose();

    expect(() => bus.emit(const _TrackFavorited('t1')), returnsNormally);
  });
}
