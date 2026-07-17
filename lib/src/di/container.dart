import 'dart:async';
import 'dart:collection';

import '../core/disposable.dart';
import 'controller.dart';
import 'diagnostics.dart';
import 'errors.dart';

/// Synchronously creates a dependency.
typedef LxFactory<T> = T Function();

/// Asynchronously creates a dependency.
typedef LxAsyncFactory<T> = Future<T> Function();

/// Releases a dependency synchronously or asynchronously.
typedef LxDisposer<T> = FutureOr<void> Function(T value);

/// Lifecycle states of an [LxContainer].
enum LxContainerState { active, disposing, disposed }

enum _RegistrationKind { singleton, lazy, factory, asyncSingleton, instance }

const Object _asyncResolutionPathKey = #lemonXAsyncResolutionPath;

class _DependencyKey {
  const _DependencyKey(this.type, this.tag);
  final Type type;
  final Object? tag;

  @override
  bool operator ==(Object other) =>
      other is _DependencyKey && other.type == type && other.tag == tag;

  @override
  int get hashCode => Object.hash(type, tag);

  @override
  String toString() => '$type${tag == null ? '' : '($tag)'}';
}

class _Registration {
  _Registration({
    required this.key,
    required this.kind,
    this.builder,
    this.asyncBuilder,
    this.instance,
    required this.owned,
    this.disposer,
    this.created = false,
  });

  final _DependencyKey key;
  final _RegistrationKind kind;
  final Object? Function()? builder;
  final Future<Object?> Function()? asyncBuilder;
  Object? instance;
  Future<Object?>? pending;
  _DependencyKey? waitingOn;
  final bool owned;
  final LxDisposer<Object?>? disposer;
  bool created;
}

/// A scoped dependency container with explicit ownership and disposal.
class LxContainer {
  /// Creates a container that optionally falls back to [parent].
  LxContainer({this.parent, String? debugLabel})
    : debugLabel = debugLabel ?? 'scope-${identityHashCode(Object())}' {
    parent?._children.add(this);
  }

  final LxContainer? parent;
  final String debugLabel;
  final Map<_DependencyKey, _Registration> _registrations = {};
  final List<_Registration> _creationOrder = [];
  final Set<Object> _disposedInstances = HashSet<Object>.identity();
  final Set<LxContainer> _children = HashSet<LxContainer>.identity();
  final List<_DependencyKey> _resolutionStack = [];
  LxContainerState _state = LxContainerState.active;
  Future<void>? _disposeFuture;
  bool _ready = false;

  LxContainerState get state => _state;
  bool get isDisposed => _state == LxContainerState.disposed;

  /// Registers and immediately creates an owned singleton.
  T put<T>(LxFactory<T> builder, {Object? tag, LxDisposer<T>? dispose}) {
    _ensureActive();
    final key = _DependencyKey(T, tag);
    final existing = _registrations[key];
    if (existing != null) {
      _emit(LxDiEventType.duplicate, key, existing.instance);
      if (existing.kind == _RegistrationKind.factory ||
          existing.kind == _RegistrationKind.asyncSingleton) {
        throw LxAlreadyRegisteredError(
          '$key already uses ${existing.kind.name} in $debugLabel.',
        );
      }
      return _resolveRegistration<T>(existing);
    }
    final registration = _Registration(
      key: key,
      kind: _RegistrationKind.singleton,
      builder: builder,
      owned: true,
      disposer: dispose == null ? null : (value) => dispose(value as T),
    );
    _registrations[key] = registration;
    _emit(LxDiEventType.register, key);
    return _resolveRegistration<T>(registration);
  }

  /// Registers an existing instance, optionally transferring ownership.
  T putInstance<T>(
    T instance, {
    Object? tag,
    bool owned = false,
    LxDisposer<T>? dispose,
  }) {
    _ensureActive();
    final key = _DependencyKey(T, tag);
    final existing = _registrations[key];
    if (existing != null) {
      _emit(LxDiEventType.duplicate, key, existing.instance);
      return _resolveRegistration<T>(existing);
    }
    final registration = _Registration(
      key: key,
      kind: _RegistrationKind.instance,
      instance: instance,
      owned: owned,
      disposer: owned && dispose != null
          ? (value) => dispose(value as T)
          : null,
      created: true,
    );
    _registrations[key] = registration;
    try {
      _initialize(instance);
      if (owned) _creationOrder.add(registration);
      _emit(LxDiEventType.register, key, instance);
      return instance;
    } catch (_) {
      _registrations.remove(key);
      if (owned) unawaited(_disposeValue(registration, instance));
      rethrow;
    }
  }

  /// Registers an owned singleton that is created on first lookup.
  void lazyPut<T>(LxFactory<T> builder, {Object? tag, LxDisposer<T>? dispose}) {
    _registerFactory(
      T,
      tag,
      _RegistrationKind.lazy,
      builder,
      dispose == null ? null : (value) => dispose(value as T),
    );
  }

  /// Registers an unowned factory that creates a new value per lookup.
  void factory<T>(LxFactory<T> builder, {Object? tag}) {
    _registerFactory(T, tag, _RegistrationKind.factory, builder, null);
  }

  /// Registers and starts creating an owned asynchronous singleton.
  Future<T> putAsync<T>(
    LxAsyncFactory<T> builder, {
    Object? tag,
    LxDisposer<T>? dispose,
  }) {
    _ensureActive();
    final key = _DependencyKey(T, tag);
    if (_registrations.containsKey(key)) {
      throw LxAlreadyRegisteredError(
        '$key is already registered in $debugLabel.',
      );
    }
    final registration = _Registration(
      key: key,
      kind: _RegistrationKind.asyncSingleton,
      asyncBuilder: () async => builder(),
      owned: true,
      disposer: dispose == null ? null : (value) => dispose(value as T),
    );
    _registrations[key] = registration;
    _emit(LxDiEventType.register, key);
    return _resolveAsyncRegistration<T>(registration);
  }

  void _registerFactory(
    Type type,
    Object? tag,
    _RegistrationKind kind,
    Object? Function() builder,
    LxDisposer<Object?>? disposer,
  ) {
    _ensureActive();
    final key = _DependencyKey(type, tag);
    if (_registrations.containsKey(key)) {
      throw LxAlreadyRegisteredError(
        '$key is already registered in $debugLabel.',
      );
    }
    _registrations[key] = _Registration(
      key: key,
      kind: kind,
      builder: builder,
      owned: kind != _RegistrationKind.factory,
      disposer: disposer,
    );
    _emit(LxDiEventType.register, key);
  }

  /// Finds a synchronous dependency from this container or its ancestors.
  T find<T>({Object? tag}) {
    _ensureActive();
    final key = _DependencyKey(T, tag);
    final registration = _registrations[key];
    if (registration != null) {
      _emit(LxDiEventType.find, key, registration.instance);
      return _resolveRegistration<T>(registration);
    }
    if (parent != null) return parent!.find<T>(tag: tag);
    throw LxNotFoundError('$key was not found from $debugLabel to root.');
  }

  /// Finds an asynchronous dependency from this container or its ancestors.
  Future<T> findAsync<T>({Object? tag}) {
    _ensureActive();
    final key = _DependencyKey(T, tag);
    final registration = _registrations[key];
    if (registration != null) return _resolveAsyncRegistration<T>(registration);
    if (parent != null) return parent!.findAsync<T>(tag: tag);
    throw LxNotFoundError('$key was not found from $debugLabel to root.');
  }

  /// Whether a matching registration exists in the selected scope chain.
  bool contains<T>({Object? tag, bool includeParents = true}) {
    _ensureActive();
    final key = _DependencyKey(T, tag);
    return _registrations.containsKey(key) ||
        (includeParents && parent?.contains<T>(tag: tag) == true);
  }

  T _resolveRegistration<T>(_Registration registration) {
    if (registration.kind == _RegistrationKind.asyncSingleton) {
      throw StateError('${registration.key} is asynchronous; use findAsync().');
    }
    if (registration.kind == _RegistrationKind.factory) {
      return _construct<T>(registration, cache: false);
    }
    if (registration.created) return registration.instance as T;
    return _construct<T>(registration, cache: true);
  }

  T _construct<T>(_Registration registration, {required bool cache}) {
    _enterResolution(registration.key);
    Object? instance;
    try {
      instance = registration.builder!();
      _initialize(instance);
      if (cache) {
        registration
          ..instance = instance
          ..created = true;
        if (registration.owned) _creationOrder.add(registration);
      }
      _emit(LxDiEventType.create, registration.key, instance);
      return instance as T;
    } catch (_) {
      if (instance != null && registration.owned) {
        unawaited(_disposeValue(registration, instance));
      }
      registration
        ..instance = null
        ..created = false;
      rethrow;
    } finally {
      _leaveResolution();
    }
  }

  Future<T> _resolveAsyncRegistration<T>(_Registration registration) async {
    if (registration.kind != _RegistrationKind.asyncSingleton) {
      return _resolveRegistration<T>(registration);
    }
    if (registration.created) return registration.instance as T;
    final inheritedPath =
        Zone.current[_asyncResolutionPathKey] as List<_DependencyKey>? ??
        const <_DependencyKey>[];
    final cycleIndex = inheritedPath.indexOf(registration.key);
    if (cycleIndex >= 0) {
      final path = [
        ...inheritedPath.sublist(cycleIndex),
        registration.key,
      ].join(' -> ');
      throw LxCircularDependencyError('$path in $debugLabel.');
    }
    final callerKey = inheritedPath.isEmpty ? null : inheritedPath.last;
    final caller = callerKey == null ? null : _registrations[callerKey];
    if (caller != null && caller.key != registration.key) {
      caller.waitingOn = registration.key;
      var cursor = registration;
      final seen = <_DependencyKey>{};
      while (cursor.waitingOn != null && seen.add(cursor.key)) {
        if (cursor.waitingOn == caller.key) {
          final path = [
            ...inheritedPath,
            registration.key,
            caller.key,
          ].join(' -> ');
          throw LxCircularDependencyError('$path in $debugLabel.');
        }
        final next = _registrations[cursor.waitingOn];
        if (next == null) break;
        cursor = next;
      }
    }
    final existing = registration.pending;
    if (existing != null) return (await existing) as T;
    final future = runZoned(
      () async {
        Object? instance;
        try {
          instance = await registration.asyncBuilder!();
          _initialize(instance);
          registration
            ..instance = instance
            ..created = true;
          _creationOrder.add(registration);
          _emit(LxDiEventType.create, registration.key, instance);
          return instance;
        } catch (_) {
          if (instance != null) await _disposeValue(registration, instance);
          registration
            ..instance = null
            ..created = false;
          rethrow;
        } finally {
          registration.pending = null;
          registration.waitingOn = null;
        }
      },
      zoneValues: {
        _asyncResolutionPathKey: [...inheritedPath, registration.key],
      },
    );
    registration.pending = future;
    return (await future) as T;
  }

  void _enterResolution(_DependencyKey key) {
    final index = _resolutionStack.indexOf(key);
    if (index >= 0) {
      final path = [..._resolutionStack.sublist(index), key].join(' -> ');
      throw LxCircularDependencyError('$path in $debugLabel.');
    }
    _resolutionStack.add(key);
  }

  void _leaveResolution() {
    if (_resolutionStack.isNotEmpty) _resolutionStack.removeLast();
  }

  void _initialize(Object? instance) {
    if (instance is! LxController) return;
    instance.initialize();
    if (_ready) instance.ready();
  }

  /// Marks a Flutter-backed scope ready after its first frame.
  void markReady() {
    _ensureActive();
    if (_ready) return;
    _ready = true;
    for (final registration in _creationOrder) {
      final instance = registration.instance;
      if (instance is LxController) instance.ready();
    }
  }

  /// Removes a registration and disposes its owned value, if created.
  Future<bool> remove<T>({Object? tag}) async {
    _ensureActive();
    final key = _DependencyKey(T, tag);
    final registration = _registrations.remove(key);
    if (registration == null) return false;
    _creationOrder.remove(registration);
    if (registration.created && registration.owned) {
      await _disposeValue(registration, registration.instance);
    }
    _emit(LxDiEventType.remove, key, registration.instance);
    return true;
  }

  /// Removes an existing registration and installs an eager singleton.
  Future<T> replace<T>(LxFactory<T> builder, {Object? tag}) async {
    await remove<T>(tag: tag);
    final result = put<T>(builder, tag: tag);
    _emit(LxDiEventType.replace, _DependencyKey(T, tag), result);
    return result;
  }

  /// Removes all registrations while keeping this container active.
  Future<void> reset() async {
    _ensureActive();
    await _disposeRegistrations();
    _registrations.clear();
    _emit(LxDiEventType.reset, const _DependencyKey(Object, null));
  }

  /// Disposes child scopes and owned values in reverse creation order.
  Future<void> dispose() => _disposeFuture ??= _disposeInternal();

  Future<void> _disposeInternal() async {
    if (_state == LxContainerState.disposed) return;
    _state = LxContainerState.disposing;
    final errors = <Object>[];
    for (final child in List<LxContainer>.of(_children)) {
      try {
        await child.dispose();
      } catch (error) {
        errors.add(error);
      }
    }
    try {
      await _disposeRegistrations();
    } catch (error) {
      errors.add(error);
    }
    _registrations.clear();
    parent?._children.remove(this);
    _state = LxContainerState.disposed;
    if (errors.isNotEmpty) {
      throw StateError('Errors while disposing $debugLabel: $errors');
    }
  }

  Future<void> _disposeRegistrations() async {
    final disposed = HashSet<Object?>.identity();
    final errors = <Object>[];
    for (final registration in _creationOrder.reversed.toList()) {
      final instance = registration.instance;
      if (!disposed.add(instance)) continue;
      try {
        await _disposeValue(registration, instance);
      } catch (error) {
        errors.add(error);
      }
    }
    _creationOrder.clear();
    if (errors.isNotEmpty) throw StateError('$errors');
  }

  Future<void> _disposeValue(_Registration registration, Object? value) async {
    if (value == null) return;
    if (!_disposedInstances.add(value)) return;
    if (value is LxController) {
      await value.disposeController();
    } else if (value is LxDisposable) {
      await value.dispose();
    } else if (registration.disposer != null) {
      await registration.disposer!(value);
    }
    _emit(LxDiEventType.dispose, registration.key, value);
  }

  void _ensureActive() {
    if (_state != LxContainerState.active) {
      throw LxDisposedError('$debugLabel is ${_state.name}.');
    }
  }

  void _emit(LxDiEventType type, _DependencyKey key, [Object? instance]) {
    if (!LxDiagnostics.enabled ||
        (type == LxDiEventType.find && !LxDiagnostics.logFind)) {
      return;
    }
    LxDiagnostics.emit(
      LxDiEvent(
        type: type,
        scope: debugLabel,
        dependencyType: key.type,
        tag: key.tag,
        instanceIdentity: instance == null ? null : identityHashCode(instance),
        timestamp: DateTime.now(),
      ),
    );
  }
}
