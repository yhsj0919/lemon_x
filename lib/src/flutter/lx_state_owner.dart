import 'dart:async';

import 'package:flutter/widgets.dart';

import '../di/container.dart';
import '../di/lemon.dart';

/// Lets a [State] own dependencies that are released with its lifecycle.
///
/// Use `late final controller = put(Controller.new);` in the State. The
/// registration is globally discoverable through [Lemon.find], while this
/// State remains its sole lifecycle owner.
mixin LxStateOwner<T extends StatefulWidget> on State<T> {
  LxContainer? _lxOwnerContainer;
  bool _lxOwnerDisposed = false;

  LxContainer get _lxContainer {
    if (_lxOwnerDisposed) {
      throw StateError('Cannot register dependencies after State.dispose().');
    }
    return _lxOwnerContainer ??= _createOwnerContainer();
  }

  LxContainer _createOwnerContainer() {
    final container = LxContainer(
      parent: Lemon.root,
      debugLabel: 'state-${T.toString()}-${identityHashCode(this)}',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (container.state == LxContainerState.active) container.markReady();
    });
    return container;
  }

  /// Registers and returns a dependency owned by this State.
  U put<U>(LxFactory<U> builder, {Object? tag, LxDisposer<U>? dispose}) =>
      _lxContainer.put<U>(builder, tag: tag, dispose: dispose);

  @mustCallSuper
  @override
  void dispose() {
    _lxOwnerDisposed = true;
    final container = _lxOwnerContainer;
    _lxOwnerContainer = null;
    if (container != null) {
      unawaited(
        container.dispose().catchError((Object error, StackTrace stack) {
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stack,
              library: 'lemon_x',
              context: ErrorDescription('while disposing an LxStateOwner'),
            ),
          );
        }),
      );
    }
    super.dispose();
  }
}
