// ignore_for_file: prefer_initializing_formals

import 'package:flutter/foundation.dart';

import '../core/disposable.dart';
import '../core/errors.dart';
import 'scheduler.dart';
import 'tracking.dart';

/// A small reactive value compatible with Flutter's [ValueListenable].
class Rx<T> extends ChangeNotifier implements ValueListenable<T>, LxDisposable {
  /// Creates a reactive value with optional debug labeling and equality logic.
  // The public parameter intentionally omits the private-field underscore.
  Rx(this._value, {this.debugLabel, bool Function(T previous, T next)? equals})
    : _equals = equals;

  T _value;
  // Keep the default equality path direct. Calling a stored generic closure on
  // every assignment is measurably more expensive than `==` on the VM.
  final bool Function(T previous, T next)? _equals;
  final String? debugLabel;
  bool _disposed = false;

  bool get isDisposed => _disposed;

  @override
  T get value {
    _checkNotDisposed();
    reportRxRead(this);
    return _value;
  }

  set value(T next) {
    _checkNotDisposed();
    _checkCanMutate();
    final equals = _equals;
    if (equals == null ? _value == next : equals(_value, next)) return;
    _value = next;
    // Most model-side writes have no active observer. Avoid entering the
    // batching/ChangeNotifier path until somebody actually subscribes.
    if (!hasListeners) return;
    scheduleRxNotification(this);
  }

  /// Notifies listeners even if [value] is unchanged.
  void refresh() {
    _checkNotDisposed();
    _checkCanMutate();
    if (!hasListeners) return;
    scheduleRxNotification(this);
  }

  @protected
  void markChanged() => refresh();

  @internal
  void notifyNow() => notifyListeners();

  void _checkNotDisposed() {
    if (_disposed) {
      throw LxDisposedError(
        'Rx${debugLabel == null ? '' : ' ($debugLabel)'} is disposed.',
      );
    }
  }

  void _checkCanMutate() {
    if (isRxMutationForbidden) {
      throw LxInvalidMutationError(
        'Cannot mutate Rx${debugLabel == null ? '' : ' ($debugLabel)'} '
        'while building Obx or computing RxComputed.',
      );
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    super.dispose();
  }

  @override
  String toString() => '$value';
}

/// A nullable reactive value.
class Rxn<T> extends Rx<T?> {
  Rxn([super.value, String? debugLabel]) : super(debugLabel: debugLabel);
}

/// A reactive integer.
class RxInt extends Rx<int> {
  RxInt(super.value, {super.debugLabel});
}

/// A reactive double.
class RxDouble extends Rx<double> {
  RxDouble(super.value, {super.debugLabel});
}

/// A reactive boolean.
class RxBool extends Rx<bool> {
  RxBool(super.value, {super.debugLabel});

  void toggle() => value = !value;
}

/// A reactive string.
class RxString extends Rx<String> {
  RxString(super.value, {super.debugLabel});
}

extension IntObsExtension on int {
  /// Wraps this integer in an [RxInt].
  RxInt get obs => RxInt(this);
}

extension DoubleObsExtension on double {
  /// Wraps this double in an [RxDouble].
  RxDouble get obs => RxDouble(this);
}

extension BoolObsExtension on bool {
  /// Wraps this boolean in an [RxBool].
  RxBool get obs => RxBool(this);
}

extension StringObsExtension on String {
  /// Wraps this string in an [RxString].
  RxString get obs => RxString(this);
}

extension ObjectObsExtension<T> on T {
  /// Wraps this value in a generic [Rx].
  Rx<T> get obs => Rx<T>(this);
}
