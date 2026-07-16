import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/disposable.dart';
import 'tracking.dart';

typedef RxCleanup = FutureOr<void> Function();
typedef RxEffectBody = RxCleanup? Function();

class RxEffect implements RxDependencyCollector, LxDisposable {
  RxEffect(this._body) {
    _run();
  }

  final RxEffectBody _body;
  final Set<Listenable> _dependencies = <Listenable>{};
  Set<Listenable>? _collecting;
  RxCleanup? _cleanup;
  bool _scheduled = false;
  bool _disposed = false;

  @override
  void dependOn(Listenable listenable) => _collecting?.add(listenable);

  void _changed() {
    if (_disposed || _scheduled) return;
    _scheduled = true;
    scheduleMicrotask(() {
      _scheduled = false;
      if (!_disposed) _run();
    });
  }

  Future<void> _run() async {
    final previousCleanup = _cleanup;
    _cleanup = null;
    if (previousCleanup != null) await previousCleanup();
    if (_disposed) return;
    final next = <Listenable>{};
    _collecting = next;
    try {
      _cleanup = collectRxDependencies(this, _body);
    } finally {
      _collecting = null;
    }
    if (_disposed) return;
    for (final dependency in _dependencies.difference(next)) {
      dependency.removeListener(_changed);
    }
    for (final dependency in next.difference(_dependencies)) {
      dependency.addListener(_changed);
    }
    _dependencies
      ..clear()
      ..addAll(next);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final dependency in _dependencies) {
      dependency.removeListener(_changed);
    }
    _dependencies.clear();
    await _cleanup?.call();
    _cleanup = null;
  }
}

RxEffect rxEffect(RxEffectBody body) => RxEffect(body);
