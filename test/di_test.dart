import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lemon_x/lemon_x.dart';

class _Service {
  _Service(this.id);
  final int id;
}

class _A {
  _A(this.b);
  final _B b;
}

class _B {
  _B(this.a);
  final _A a;
}

class _AsyncA {
  _AsyncA(this.b);
  final _AsyncB b;
}

class _AsyncB {
  _AsyncB(this.a);
  final _AsyncA a;
}

class _TrackedController extends LxController {
  _TrackedController(this.events, this.name);
  final List<String> events;
  final String name;

  @override
  void onInit() => events.add('init:$name');

  @override
  void onDispose() => events.add('dispose:$name');
}

void main() {
  setUp(() {
    LxDiagnostics.enabled = false;
  });

  test('put is eager, deduplicated, and returns the instance', () async {
    final container = LxContainer(debugLabel: 'test');
    var builds = 0;

    final first = container.put(() => _Service(++builds));
    final second = container.put(() => _Service(++builds));

    expect(identical(first, second), isTrue);
    expect(builds, 1);
    await container.dispose();
  });

  test('lazyPut constructs on first find', () async {
    final container = LxContainer(debugLabel: 'test');
    var builds = 0;
    container.lazyPut(() => _Service(++builds));

    expect(builds, 0);
    expect(container.find<_Service>().id, 1);
    expect(container.find<_Service>().id, 1);
    expect(builds, 1);
    await container.dispose();
  });

  test('child shadows parent and falls back after child disposal', () async {
    final root = LxContainer(debugLabel: 'root');
    final child = LxContainer(parent: root, debugLabel: 'child');
    root.put(() => _Service(1));
    child.put(() => _Service(2));

    expect(child.find<_Service>().id, 2);
    expect(root.find<_Service>().id, 1);
    await child.dispose();
    expect(root.find<_Service>().id, 1);
    await root.dispose();
  });

  test('tags identify separate registrations', () async {
    final container = LxContainer(debugLabel: 'test');
    container.put(() => _Service(1), tag: 'one');
    container.put(() => _Service(2), tag: 'two');

    expect(container.find<_Service>(tag: 'one').id, 1);
    expect(container.find<_Service>(tag: 'two').id, 2);
    await container.dispose();
  });

  test('sync circular dependencies report their path', () async {
    final container = LxContainer(debugLabel: 'test');
    container.lazyPut<_A>(() => _A(container.find<_B>()));
    container.lazyPut<_B>(() => _B(container.find<_A>()));

    expect(
      () => container.find<_A>(),
      throwsA(isA<LxCircularDependencyError>()),
    );
    await container.dispose();
  });

  test('async initialization is shared and failure can retry', () async {
    final container = LxContainer(debugLabel: 'test');
    var attempts = 0;
    final completer = Completer<void>();
    unawaited(
      container
          .putAsync<_Service>(() async {
            attempts++;
            await completer.future;
            if (attempts == 1) throw StateError('first failure');
            return _Service(attempts);
          })
          .catchError((_) => _Service(-1)),
    );

    final first = container.findAsync<_Service>();
    final second = container.findAsync<_Service>();
    completer.complete();
    await expectLater(first, throwsStateError);
    await expectLater(second, throwsStateError);
    expect(attempts, 1);

    final retried = await container.findAsync<_Service>();
    expect(retried.id, 2);
    await container.dispose();
  });

  test('async circular dependencies are detected across awaits', () async {
    final container = LxContainer(debugLabel: 'test');
    final first = container.putAsync<_AsyncA>(() async {
      await Future<void>.value();
      return _AsyncA(await container.findAsync<_AsyncB>());
    });
    container.putAsync<_AsyncB>(() async {
      await Future<void>.value();
      return _AsyncB(await container.findAsync<_AsyncA>());
    }).ignore();

    await expectLater(first, throwsA(isA<LxCircularDependencyError>()));
    await container.dispose();
  });

  test('owned instances dispose in reverse creation order', () async {
    final events = <String>[];
    final container = LxContainer(debugLabel: 'test');
    container.put(() => _TrackedController(events, 'first'));
    container.put(() => _TrackedController(events, 'second'), tag: 'second');

    await container.dispose();

    expect(events, [
      'init:first',
      'init:second',
      'dispose:second',
      'dispose:first',
    ]);
    expect(container.state, LxContainerState.disposed);
    await container.dispose();
  });

  test(
    'putInstance is external by default and can transfer ownership',
    () async {
      final events = <String>[];
      final external = _TrackedController(events, 'external');
      final owned = _TrackedController(events, 'owned');
      final container = LxContainer(debugLabel: 'test');
      container.putInstance(external);
      container.putInstance(owned, tag: 'owned', owned: true);

      await container.dispose();

      expect(external.isDisposed, isFalse);
      expect(owned.isDisposed, isTrue);
    },
  );

  test('parent disposal disposes children first', () async {
    final events = <String>[];
    final root = LxContainer(debugLabel: 'root');
    final child = LxContainer(parent: root, debugLabel: 'child');
    root.put(() => _TrackedController(events, 'root'));
    child.put(() => _TrackedController(events, 'child'));

    await root.dispose();

    expect(events.sublist(2), ['dispose:child', 'dispose:root']);
  });

  test(
    'custom async disposer runs and disposed container rejects access',
    () async {
      final container = LxContainer(debugLabel: 'test');
      var disposed = false;
      container.put(
        () => _Service(1),
        dispose: (_) async {
          await Future<void>.value();
          disposed = true;
        },
      );

      await container.dispose();

      expect(disposed, isTrue);
      expect(() => container.find<_Service>(), throwsA(isA<LxDisposedError>()));
    },
  );

  test('factory, remove, replace, and reset have explicit semantics', () async {
    final container = LxContainer(debugLabel: 'test');
    var builds = 0;
    container.factory(() => _Service(++builds));
    expect(container.find<_Service>().id, 1);
    expect(container.find<_Service>().id, 2);

    await container.remove<_Service>();
    container.put(() => _Service(3));
    expect((await container.replace(() => _Service(4))).id, 4);
    await container.reset();
    expect(container.contains<_Service>(), isFalse);
    expect(container.state, LxContainerState.active);
    await container.dispose();
  });

  test('diagnostics emits structured lifecycle events', () async {
    final events = <LxDiEvent>[];
    LxDiagnostics.enabled = true;
    LxDiagnostics.onEvent = events.add;
    final container = LxContainer(debugLabel: 'diagnostic');
    container.put(() => _Service(1));
    container.find<_Service>();
    await container.dispose();

    expect(events.any((event) => event.type == LxDiEventType.register), isTrue);
    expect(events.any((event) => event.type == LxDiEventType.dispose), isTrue);
    expect(events.every((event) => event.scope == 'diagnostic'), isTrue);
    LxDiagnostics.onEvent = null;
    LxDiagnostics.enabled = false;
  });
}
