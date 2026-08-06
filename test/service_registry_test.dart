import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/service_registry.dart';

abstract class _IGreeter {
  String greet();
}

class _EnglishGreeter implements _IGreeter {
  @override
  String greet() => 'Hello';
}

class _FrenchGreeter implements _IGreeter {
  @override
  String greet() => 'Bonjour';
}

void main() {
  test('get returns null when nothing is registered for the interface', () {
    final registry = ServiceRegistry();
    expect(registry.get<_IGreeter>(), isNull);
    expect(registry.has<_IGreeter>(), isFalse);
  });

  test('register + get round-trips through the interface type, not the concrete class', () {
    final registry = ServiceRegistry();
    final greeter = _EnglishGreeter();

    registry.register(_IGreeter, greeter);

    expect(registry.get<_IGreeter>(), same(greeter));
    expect(registry.has<_IGreeter>(), isTrue);
  });

  test('get returns the first (primary) registration when several exist', () {
    final registry = ServiceRegistry();
    final english = _EnglishGreeter();
    final french = _FrenchGreeter();

    registry.register(_IGreeter, english);
    registry.register(_IGreeter, french);

    expect(registry.get<_IGreeter>(), same(english));
  });

  test('getAll returns every registration in registration order', () {
    final registry = ServiceRegistry();
    final english = _EnglishGreeter();
    final french = _FrenchGreeter();

    registry.register(_IGreeter, english);
    registry.register(_IGreeter, french);

    expect(registry.getAll<_IGreeter>(), [english, french]);
  });

  test('unregister removes exactly that instance, leaving others intact', () {
    final registry = ServiceRegistry();
    final english = _EnglishGreeter();
    final french = _FrenchGreeter();
    registry.register(_IGreeter, english);
    registry.register(_IGreeter, french);

    registry.unregister(_IGreeter, english);

    expect(registry.getAll<_IGreeter>(), [french]);
  });

  test('registering the same instance twice does not duplicate it', () {
    final registry = ServiceRegistry();
    final greeter = _EnglishGreeter();

    registry.register(_IGreeter, greeter);
    registry.register(_IGreeter, greeter);

    expect(registry.getAll<_IGreeter>(), [greeter]);
  });

  test('changes fires on register and on unregister, not on a no-op duplicate', () async {
    final registry = ServiceRegistry();
    final greeter = _EnglishGreeter();
    final events = <void>[];
    final sub = registry.changes.listen(events.add);

    registry.register(_IGreeter, greeter);
    registry.register(_IGreeter, greeter); // duplicate: no second event
    registry.unregister(_IGreeter, greeter);
    await Future<void>.delayed(Duration.zero);

    expect(events, hasLength(2));
    await sub.cancel();
  });

  test('dispose clears all registrations and closes the changes stream', () async {
    final registry = ServiceRegistry();
    registry.register(_IGreeter, _EnglishGreeter());

    await registry.dispose();

    expect(registry.get<_IGreeter>(), isNull);
  });
}
