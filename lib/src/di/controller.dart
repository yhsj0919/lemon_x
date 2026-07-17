import 'dart:async';

import '../core/disposable.dart';

/// Optional lifecycle base class for objects owned by an [LxContainer].
abstract class LxController {
  final List<Object> _owned = <Object>[];
  bool _initialized = false;
  bool _ready = false;
  bool _disposed = false;

  bool get isInitialized => _initialized;
  bool get isReady => _ready;
  bool get isDisposed => _disposed;

  /// Adds a resource to be disposed before this controller's [onDispose].
  T own<T extends Object>(T resource) {
    _owned.add(resource);
    return resource;
  }

  /// Called once after the controller enters a container.
  void onInit() {}

  /// Called once after a Flutter-backed scope completes its first frame.
  void onReady() {}

  /// Called once when the controller is removed from its owner.
  FutureOr<void> onDispose() {}

  void initialize() {
    if (_initialized) return;
    _initialized = true;
    onInit();
  }

  void ready() {
    if (_ready || _disposed) return;
    _ready = true;
    onReady();
  }

  Future<void> disposeController() async {
    if (_disposed) return;
    _disposed = true;
    for (final resource in _owned.reversed) {
      if (resource is LxDisposable) {
        await resource.dispose();
      } else if (resource is StreamSubscription<dynamic>) {
        await resource.cancel();
      } else {
        final dynamic value = resource;
        try {
          await value.dispose();
        } on NoSuchMethodError {
          // Resource ownership is intentionally permissive for Flutter objects.
        }
      }
    }
    _owned.clear();
    await onDispose();
  }
}
