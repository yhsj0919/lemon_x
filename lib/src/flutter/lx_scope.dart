import 'dart:async';

import 'package:flutter/widgets.dart';

import '../di/container.dart';
import '../di/lemon.dart';

/// Registers dependencies through a scope-specific [LxRegistrar].
typedef LxBindings = void Function(LxRegistrar registrar);

/// Registration-only facade used by [LxScope] bindings.
///
/// Registration methods intentionally return `void`. This prevents the
/// surrounding `void` callback from influencing generic inference, so both
/// arrow and block-bodied bindings register the builder's concrete type.
class LxRegistrar {
  LxRegistrar._(this._container);

  final LxContainer _container;

  /// Registers and immediately creates an owned singleton.
  void put<T>(
    LxFactory<T> builder, {
    Object? tag,
    LxDisposer<T>? dispose,
    bool permanent = false,
  }) {
    _container.put<T>(
      builder,
      tag: tag,
      dispose: dispose,
      permanent: permanent,
    );
  }

  /// Registers an existing instance, optionally transferring ownership.
  void putInstance<T>(
    T instance, {
    Object? tag,
    bool owned = false,
    LxDisposer<T>? dispose,
    bool permanent = false,
  }) {
    _container.putInstance<T>(
      instance,
      tag: tag,
      owned: owned,
      dispose: dispose,
      permanent: permanent,
    );
  }

  /// Registers an owned singleton that is created on first lookup.
  void lazyPut<T>(
    LxFactory<T> builder, {
    Object? tag,
    LxDisposer<T>? dispose,
    bool permanent = false,
  }) {
    _container.lazyPut<T>(
      builder,
      tag: tag,
      dispose: dispose,
      permanent: permanent,
    );
  }

  /// Registers an unowned factory that creates a value per lookup.
  void factory<T>(LxFactory<T> builder, {Object? tag, bool permanent = false}) {
    _container.factory<T>(builder, tag: tag, permanent: permanent);
  }

  /// Starts registering an owned asynchronous singleton.
  void putAsync<T>(
    LxAsyncFactory<T> builder, {
    Object? tag,
    LxDisposer<T>? dispose,
    bool permanent = false,
  }) {
    unawaited(
      _container.putAsync<T>(
        builder,
        tag: tag,
        dispose: dispose,
        permanent: permanent,
      ),
    );
  }

  /// Whether a matching dependency exists in this scope or an ancestor.
  bool contains<T>({Object? tag, bool includeParents = true}) =>
      _container.contains<T>(tag: tag, includeParents: includeParents);

  /// Finds a dependency already registered in this scope or an ancestor.
  T find<T>({Object? tag}) => _container.find<T>(tag: tag);

  /// Finds an asynchronous dependency already registered in the scope chain.
  Future<T> findAsync<T>({Object? tag}) => _container.findAsync<T>(tag: tag);
}

/// Exposes a scoped dependency container to a Widget subtree.
class LxScope extends StatefulWidget {
  /// Creates a scope around [child].
  const LxScope({
    required this.child,
    this.container,
    this.create,
    this.bindings,
    this.disposeContainer,
    this.debugLabel,
    super.key,
  }) : assert(container == null || create == null);

  final Widget child;
  final LxContainer? container;
  final LxContainer Function(LxContainer? parent)? create;
  final LxBindings? bindings;
  final bool? disposeContainer;
  final String? debugLabel;

  /// Creates a scope that owns one dependency and wraps [child].
  static Widget put<T>(
    LxFactory<T> builder, {
    required Widget child,
    Object? tag,
    bool permanent = false,
    LxDisposer<T>? dispose,
    Key? key,
    String? debugLabel,
  }) => LxScope(
    key: key,
    debugLabel: debugLabel,
    bindings: (registrar) => registrar.put<T>(
      builder,
      tag: tag,
      permanent: permanent,
      dispose: dispose,
    ),
    child: child,
  );

  /// Returns the nearest scoped container and subscribes to scope changes.
  static LxContainer of(BuildContext context) {
    final inherited = context
        .dependOnInheritedWidgetOfExactType<_LxInheritedScope>();
    if (inherited == null) {
      throw FlutterError('No LxScope found above this BuildContext.');
    }
    return inherited.container;
  }

  /// Returns the nearest scoped container, or `null` when none exists.
  static LxContainer? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_LxInheritedScope>()
      ?.container;

  @override
  State<LxScope> createState() => _LxScopeState();
}

class _LxScopeState extends State<LxScope> {
  LxContainer? _container;
  late bool _owns;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_container != null) return;
    final parent = LxScope.maybeOf(context) ?? Lemon.root;
    _owns = widget.disposeContainer ?? widget.container == null;
    _container =
        widget.container ??
        widget.create?.call(parent) ??
        LxContainer(parent: parent, debugLabel: widget.debugLabel);
    final bindings = widget.bindings;
    if (bindings != null) bindings(LxRegistrar._(_container!));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _container?.state == LxContainerState.active) {
        _container!.markReady();
      }
    });
  }

  @override
  Widget build(BuildContext context) =>
      _LxInheritedScope(container: _container!, child: widget.child);

  @override
  void dispose() {
    if (_owns) {
      unawaited(
        _container!.dispose().catchError((Object error, StackTrace stack) {
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stack,
              library: 'lemon_x',
              context: ErrorDescription('while disposing an LxScope'),
            ),
          );
        }),
      );
    }
    super.dispose();
  }
}

class _LxInheritedScope extends InheritedWidget {
  const _LxInheritedScope({required this.container, required super.child});
  final LxContainer container;

  @override
  bool updateShouldNotify(_LxInheritedScope oldWidget) =>
      !identical(container, oldWidget.container);
}
