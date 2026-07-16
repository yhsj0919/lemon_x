import 'package:flutter/foundation.dart';

import '../core/errors.dart';
import 'tracking.dart';

class RxComputed<T> extends ChangeNotifier
    implements ValueListenable<T>, RxDependencyCollector {
  RxComputed(this._compute, {this.debugLabel});

  final T Function() _compute;
  final String? debugLabel;
  final Set<Listenable> _dependencies = <Listenable>{};
  Set<Listenable>? _collecting;
  bool _dirty = true;
  bool _computing = false;
  bool _disposed = false;
  late T _cached;

  @override
  T get value {
    if (_disposed) throw LxDisposedError('RxComputed is disposed.');
    reportRxRead(this);
    if (_dirty) _recompute();
    return _cached;
  }

  void _recompute() {
    if (_computing) {
      throw LxCircularDependencyError(
        'Circular RxComputed dependency${debugLabel == null ? '' : ': $debugLabel'}.',
      );
    }
    _computing = true;
    final nextDependencies = <Listenable>{};
    _collecting = nextDependencies;
    try {
      _cached = collectRxDependencies(this, _compute, forbidMutations: true);
      _dirty = false;
    } finally {
      _collecting = null;
      _computing = false;
    }
    for (final dependency in _dependencies.difference(nextDependencies)) {
      dependency.removeListener(_dependencyChanged);
    }
    for (final dependency in nextDependencies.difference(_dependencies)) {
      dependency.addListener(_dependencyChanged);
    }
    _dependencies
      ..clear()
      ..addAll(nextDependencies);
  }

  @override
  void dependOn(Listenable listenable) => _collecting?.add(listenable);

  void _dependencyChanged() {
    if (_dirty || _disposed) return;
    _dirty = true;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final dependency in _dependencies) {
      dependency.removeListener(_dependencyChanged);
    }
    _dependencies.clear();
    super.dispose();
  }
}
