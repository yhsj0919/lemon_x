import 'dart:async';

import 'package:flutter/widgets.dart';

import '../di/container.dart';

/// Registers dependencies in an [LxContainer].
typedef LxBindings = void Function(LxContainer container);

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
    final parent = LxScope.maybeOf(context);
    _owns = widget.disposeContainer ?? widget.container == null;
    _container =
        widget.container ??
        widget.create?.call(parent) ??
        LxContainer(parent: parent, debugLabel: widget.debugLabel);
    widget.bindings?.call(_container!);
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
