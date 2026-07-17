import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/disposable.dart';
import 'tracking.dart';

/// A cleanup callback returned by an [RxEffectBody].
typedef RxCleanup = FutureOr<void> Function();

/// A tracked effect body that may return cleanup work.
typedef RxEffectBody = RxCleanup? Function();

/// Runs a side effect and reruns it when its reactive dependencies change.
class RxEffect implements RxDependencyCollector, LxDisposable {
  RxEffect(this._body) {
    _startRun();
  }

  final RxEffectBody _body;
  final Set<Listenable> _dependencies = <Listenable>{};
  Set<Listenable>? _collecting;
  RxCleanup? _cleanup;
  bool _scheduled = false;
  bool _running = false;
  bool _rerunRequested = false;
  bool _disposed = false;
  Future<void>? _runningFuture;

  @override
  void dependOn(Listenable listenable) => _collecting?.add(listenable);

  void _changed() {
    if (_disposed) return;
    if (_running) {
      _rerunRequested = true;
      return;
    }
    if (_scheduled) return;
    _scheduled = true;
    scheduleMicrotask(() {
      _scheduled = false;
      if (!_disposed) _startRun();
    });
  }

  void _startRun() {
    if (_disposed || _running) return;
    _runningFuture = _drain();
  }

  Future<void> _drain() async {
    _running = true;
    try {
      do {
        await _runOnce();
      } while (_rerunRequested && !_disposed);
    } finally {
      _running = false;
    }
  }

  Future<void> _runOnce() async {
    final previousCleanup = _cleanup;
    _cleanup = null;
    if (previousCleanup != null) await previousCleanup();
    if (_disposed) return;
    // Changes that arrived while cleanup was pending are represented by the
    // latest values read by this run and do not require a duplicate rerun.
    _rerunRequested = false;
    final next = <Listenable>{};
    _collecting = next;
    try {
      _cleanup = collectRxDependencies(this, _body);
    } finally {
      _collecting = null;
    }
    if (_disposed) return;
    for (final dependency in _dependencies) {
      if (!next.contains(dependency)) dependency.removeListener(_changed);
    }
    for (final dependency in next) {
      if (!_dependencies.contains(dependency)) dependency.addListener(_changed);
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
    await _runningFuture;
    await _cleanup?.call();
    _cleanup = null;
  }
}

/// Creates and immediately runs a tracked [RxEffect].
RxEffect rxEffect(RxEffectBody body) => RxEffect(body);
