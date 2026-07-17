import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/disposable.dart';

/// A disposable reactive subscription or timer-based worker.
class Worker implements LxDisposable {
  Worker(this._dispose);

  final void Function() _dispose;
  bool _disposed = false;

  bool get isDisposed => _disposed;

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _dispose();
  }
}

/// Calls [callback] after every change to [rx].
Worker ever<T>(ValueListenable<T> rx, void Function(T value) callback) {
  void listener() => callback(rx.value);
  rx.addListener(listener);
  return Worker(() => rx.removeListener(listener));
}

/// Calls [callback] for the first change to [rx], then disposes itself.
Worker once<T>(ValueListenable<T> rx, void Function(T value) callback) {
  late Worker worker;
  void listener() {
    worker.dispose();
    callback(rx.value);
  }

  rx.addListener(listener);
  worker = Worker(() => rx.removeListener(listener));
  return worker;
}

/// Calls [callback] after [rx] has remained unchanged for [time].
Worker debounce<T>(
  ValueListenable<T> rx,
  void Function(T value) callback, {
  Duration time = const Duration(milliseconds: 800),
}) {
  Timer? timer;
  var disposed = false;
  void listener() {
    timer?.cancel();
    timer = Timer(time, () {
      if (!disposed) callback(rx.value);
    });
  }

  rx.addListener(listener);
  return Worker(() {
    disposed = true;
    timer?.cancel();
    rx.removeListener(listener);
  });
}

/// Calls [callback] at most once per [time] window.
Worker interval<T>(
  ValueListenable<T> rx,
  void Function(T value) callback, {
  Duration time = const Duration(seconds: 1),
}) {
  Timer? gate;
  void listener() {
    if (gate?.isActive ?? false) return;
    callback(rx.value);
    gate = Timer(time, () {});
  }

  rx.addListener(listener);
  return Worker(() {
    gate?.cancel();
    rx.removeListener(listener);
  });
}
