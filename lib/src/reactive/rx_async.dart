import 'package:flutter/foundation.dart';

import '../core/disposable.dart';
import 'rx.dart';

enum _RxAsyncPhase { loading, data, error }

@immutable
class _RxAsyncState<T> {
  const _RxAsyncState.loading()
    : phase = _RxAsyncPhase.loading,
      value = null,
      error = null,
      stackTrace = null;

  const _RxAsyncState.data(T this.value)
    : phase = _RxAsyncPhase.data,
      error = null,
      stackTrace = null;

  const _RxAsyncState.error(this.error, this.stackTrace)
    : phase = _RxAsyncPhase.error,
      value = null;

  final _RxAsyncPhase phase;
  final T? value;
  final Object? error;
  final StackTrace? stackTrace;
}

/// A presentation-layer async state with loading, data, and error phases.
class RxAsync<T> implements Listenable, LxDisposable {
  /// Creates an async state initially in the loading phase.
  RxAsync() : _state = Rx<_RxAsyncState<T>>(const _RxAsyncState.loading());

  final Rx<_RxAsyncState<T>> _state;

  bool get isLoading => _state.value.phase == _RxAsyncPhase.loading;
  bool get hasData => _state.value.phase == _RxAsyncPhase.data;
  bool get hasError => _state.value.phase == _RxAsyncPhase.error;

  T? get value => _state.value.value;
  Object? get errorValue => _state.value.error;
  StackTrace? get stackTrace => _state.value.stackTrace;

  /// Moves this state to loading.
  void loading() => _state.value = const _RxAsyncState.loading();

  /// Moves this state to data, including when [value] is nullable.
  void data(T value) => _state.value = _RxAsyncState<T>.data(value);

  /// Moves this state to error with an optional [stackTrace].
  void error(Object error, [StackTrace? stackTrace]) =>
      _state.value = _RxAsyncState<T>.error(error, stackTrace);

  /// Runs [task], capturing its result or failure without rethrowing it.
  Future<void> guard(Future<T> Function() task) async {
    loading();
    try {
      data(await task());
    } catch (errorValue, errorStackTrace) {
      error(errorValue, errorStackTrace);
    }
  }

  /// Selects a callback for the current mutually exclusive phase.
  R when<R>({
    required R Function() loading,
    required R Function(T value) data,
    required R Function(Object error, StackTrace? stackTrace) error,
  }) {
    final state = _state.value;
    return switch (state.phase) {
      _RxAsyncPhase.loading => loading(),
      _RxAsyncPhase.data => data(state.value as T),
      _RxAsyncPhase.error => error(state.error!, state.stackTrace),
    };
  }

  @override
  void addListener(VoidCallback listener) => _state.addListener(listener);

  @override
  void removeListener(VoidCallback listener) => _state.removeListener(listener);

  @override
  void dispose() => _state.dispose();
}
