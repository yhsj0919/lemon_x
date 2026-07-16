import 'dart:async';

import '../core/disposable.dart';

abstract class LxController {
  final List<Object> _owned = <Object>[];
  bool _initialized = false;
  bool _ready = false;
  bool _disposed = false;

  bool get isInitialized => _initialized;
  bool get isReady => _ready;
  bool get isDisposed => _disposed;

  T own<T extends Object>(T resource) {
    _owned.add(resource);
    return resource;
  }

  void onInit() {}
  void onReady() {}
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
