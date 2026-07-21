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

class _DisposableService implements LxDisposable {
  _DisposableService(this.onDispose);

  final void Function() onDispose;

  @override
  void dispose() => onDispose();
}

class _InitController extends LxController {
  _InitController({required this.fail, required this.onDisposed});

  final bool fail;
  final void Function() onDisposed;

  @override
  void onInit() {
    if (fail) throw StateError('init failed');
  }

  @override
  void onDispose() => onDisposed();
}

class _SensitiveTag {
  _SensitiveTag(this.onStringify);
  final void Function() onStringify;

  @override
  String toString() {
    onStringify();
    return 'secret';
  }
}

void main() {
  setUp(() {
    LxDiagnostics.enabled = false;
  });

  tearDown(() async {
    LxDiagnostics.onEvent = null;
    LxDiagnostics.enabled = false;
    await Lemon.dispose();
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

  test('child reuses the first canonical registration', () async {
    final root = LxContainer(debugLabel: 'root');
    final child = LxContainer(parent: root, debugLabel: 'child');
    var childBuilds = 0;
    root.put(() => _Service(1));
    final fromChild = child.put(() => _Service(++childBuilds + 1));

    expect(fromChild.id, 1);
    expect(root.find<_Service>().id, 1);
    expect(child.find<_Service>().id, 1);
    expect(childBuilds, 0);
    await child.dispose();
    expect(root.find<_Service>().id, 1);
    await root.dispose();
  });

  test('duplicate scope aliases neither own nor extend the instance', () async {
    final events = <String>[];
    final root = LxContainer(debugLabel: 'root');
    final firstPage = LxContainer(parent: root, debugLabel: 'first-page');
    final secondPage = LxContainer(parent: root, debugLabel: 'second-page');
    final controller = firstPage.put(
      () => _TrackedController(events, 'shared'),
    );
    final duplicate = secondPage.put(
      () => _TrackedController(events, 'unused'),
    );

    expect(identical(controller, duplicate), isTrue);
    await secondPage.dispose();
    expect(controller.isDisposed, isFalse);
    await firstPage.dispose();
    expect(controller.isDisposed, isTrue);
    expect(root.containsGlobal<_TrackedController>(), isFalse);
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

  test('controller disposes owned resources before onDispose', () async {
    final events = <String>[];
    final container = LxContainer(debugLabel: 'test');
    final controller = container.put(() => _TrackedController(events, 'owner'));
    controller.own(_DisposableService(() => events.add('resource')));

    await container.dispose();

    expect(events, ['init:owner', 'resource', 'dispose:owner']);
  });

  test('controller owns multiple resources in one call', () async {
    final events = <String>[];
    final container = LxContainer(debugLabel: 'test');
    final controller = container.put(() => _TrackedController(events, 'owner'));
    controller.ownAll([
      _DisposableService(() => events.add('first')),
      _DisposableService(() => events.add('second')),
    ]);

    await container.dispose();

    expect(events, ['init:owner', 'second', 'first', 'dispose:owner']);
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

  test(
    'the same owned instance is disposed once across multiple keys',
    () async {
      var disposals = 0;
      final service = _DisposableService(() => disposals++);
      final container = LxContainer(debugLabel: 'test');
      container.putInstance<_DisposableService>(
        service,
        tag: 'one',
        owned: true,
      );
      container.putInstance<_DisposableService>(
        service,
        tag: 'two',
        owned: true,
      );

      await container.remove<_DisposableService>(tag: 'one');
      await container.dispose();

      expect(disposals, 1);
    },
  );

  test('parent disposal disposes children first', () async {
    final events = <String>[];
    final root = LxContainer(debugLabel: 'root');
    final child = LxContainer(parent: root, debugLabel: 'child');
    root.put(() => _TrackedController(events, 'root'), tag: 'root');
    child.put(() => _TrackedController(events, 'child'), tag: 'child');

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
      expect(
        () => container.contains<_Service>(),
        throwsA(isA<LxDisposedError>()),
      );
    },
  );

  test(
    'initialization failure rolls back and disposes the failed value',
    () async {
      final container = LxContainer(debugLabel: 'test');
      var attempts = 0;
      var disposals = 0;
      container.lazyPut<_InitController>(
        () => _InitController(
          fail: ++attempts == 1,
          onDisposed: () => disposals++,
        ),
      );

      expect(() => container.find<_InitController>(), throwsStateError);
      await Future<void>.delayed(Duration.zero);
      final retried = container.find<_InitController>();

      expect(retried.isInitialized, isTrue);
      expect(attempts, 2);
      expect(disposals, 1);
      await container.dispose();
      expect(disposals, 2);
    },
  );

  test('disposal continues after errors and reports them together', () async {
    final container = LxContainer(debugLabel: 'test');
    final disposed = <int>[];
    container.put(
      () => _Service(1),
      dispose: (_) {
        disposed.add(1);
        throw StateError('one');
      },
    );
    container.put(
      () => _Service(2),
      tag: 'two',
      dispose: (_) async {
        disposed.add(2);
        throw StateError('two');
      },
    );

    await expectLater(container.dispose(), throwsStateError);

    expect(disposed, [2, 1]);
    expect(container.state, LxContainerState.disposed);
  });

  test('factory, remove, and reset have explicit semantics', () async {
    final container = LxContainer(debugLabel: 'test');
    var builds = 0;
    container.factory(() => _Service(++builds));
    expect(container.find<_Service>().id, 1);
    expect(container.find<_Service>().id, 2);

    await container.remove<_Service>();
    container.put(() => _Service(3));
    expect(container.find<_Service>().id, 3);
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

  test(
    'disabled diagnostics allocate no events and format tags safely',
    () async {
      var events = 0;
      var stringifications = 0;
      final tag = _SensitiveTag(() => stringifications++);
      LxDiagnostics.enabled = false;
      LxDiagnostics.onEvent = (_) => events++;
      final container = LxContainer(debugLabel: 'quiet');
      container.put(() => _Service(1), tag: tag);

      expect(events, 0);
      final event = LxDiEvent(
        type: LxDiEventType.register,
        scope: 'quiet',
        dependencyType: _Service,
        tag: tag,
        timestamp: DateTime(2026),
      );
      expect(event.format(), contains('_SensitiveTag#'));
      expect(stringifications, 0);
      await container.dispose();
    },
  );

  test('Lemon global entry can reset its root safely', () async {
    Lemon.put(() => _Service(1), permanent: true);
    expect(Lemon.find<_Service>().id, 1);
    await Lemon.reset();
    expect(Lemon.contains<_Service>(), isFalse);

    Lemon.put(() => _Service(2), permanent: true);
    final previous = Lemon.root;
    await Lemon.dispose();

    expect(previous.isDisposed, isTrue);
    expect(Lemon.root.state, LxContainerState.active);
    expect(() => Lemon.find<_Service>(), throwsA(isA<LxNotFoundError>()));
  });

  test('Lemon requires an active page owner for non-permanent put', () {
    expect(
      () => Lemon.put(() => _Service(1)),
      throwsA(isA<LxNoPageScopeError>()),
    );
    expect(Lemon.contains<_Service>(), isFalse);
  });

  test('Lemon root proxies ownership and removal options', () async {
    var disposals = 0;
    Lemon.putInstance<_Service>(
      _Service(1),
      owned: true,
      permanent: true,
      dispose: (_) => disposals++,
    );
    expect(await Lemon.remove<_Service>(), isTrue);
    expect(disposals, 1);
    expect(Lemon.contains<_Service>(), isFalse);
    await Lemon.dispose();
  });

  test(
    'Lemon finds page-owned registrations through the global index',
    () async {
      final page = LxContainer(parent: Lemon.root, debugLabel: 'page');
      final controller = page.put(() => _Service(7));

      expect(identical(Lemon.find<_Service>(), controller), isTrue);
      expect(Lemon.contains<_Service>(), isTrue);
      await page.dispose();
      expect(Lemon.contains<_Service>(), isFalse);
    },
  );

  test('Lemon cannot remove a page-owned registration', () async {
    final page = LxContainer(parent: Lemon.root, debugLabel: 'page');
    page.put(() => _Service(1));

    await expectLater(
      Lemon.remove<_Service>(),
      throwsA(isA<LxOwnershipError>()),
    );
    expect(Lemon.find<_Service>().id, 1);
    await page.dispose();
  });

  test(
    'permanent registration requested by a child is owned by root',
    () async {
      final page = LxContainer(parent: Lemon.root, debugLabel: 'page');
      final service = page.put(() => _Service(9), permanent: true);

      await page.dispose();
      expect(identical(Lemon.find<_Service>(), service), isTrue);
      expect(await Lemon.remove<_Service>(), isTrue);
    },
  );

  test('root reset leaves page-owned registrations active', () async {
    final page = LxContainer(parent: Lemon.root, debugLabel: 'page');
    final pageService = page.put(() => _Service(2), tag: 'page');
    Lemon.put(() => _Service(1), tag: 'root', permanent: true);

    await Lemon.reset();

    expect(Lemon.contains<_Service>(tag: 'root'), isFalse);
    expect(identical(Lemon.find<_Service>(tag: 'page'), pageService), isTrue);
    await page.dispose();
  });

  test('scope registrations are hidden before their disposer runs', () async {
    final page = LxContainer(parent: Lemon.root, debugLabel: 'page');
    var visibleDuringDispose = true;
    page.put(
      () => _Service(1),
      dispose: (_) {
        visibleDuringDispose = Lemon.contains<_Service>();
      },
    );

    await page.dispose();

    expect(visibleDuringDispose, isFalse);
  });

  test('removing a pending async registration disposes its result', () async {
    final page = LxContainer(parent: Lemon.root, debugLabel: 'page');
    final completer = Completer<_Service>();
    var disposals = 0;
    final pending = page.putAsync(
      () => completer.future,
      dispose: (_) => disposals++,
    );
    final removing = page.remove<_Service>();
    completer.complete(_Service(1));

    await pending;
    expect(await removing, isTrue);
    expect(disposals, 1);
    expect(Lemon.contains<_Service>(), isFalse);
    await page.dispose();
  });
}
