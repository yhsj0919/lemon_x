import 'package:flutter/foundation.dart';

import '../core/disposable.dart';
import '../core/errors.dart';
import 'scheduler.dart';
import 'tracking.dart';

/// A small reactive value compatible with Flutter's [ValueListenable].
class Rx<T> extends ChangeNotifier implements ValueListenable<T>, LxDisposable {
  Rx(this._value, {this.debugLabel, bool Function(T previous, T next)? equals})
    : _equals = equals ?? _defaultEquals;

  T _value;
  final bool Function(T previous, T next) _equals;
  final String? debugLabel;
  bool _disposed = false;

  static bool _defaultEquals<T>(T previous, T next) => previous == next;

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
    if (_equals(_value, next)) return;
    _value = next;
    scheduleRxNotification(this);
  }

  /// Notifies listeners even if [value] is unchanged.
  void refresh() {
    _checkNotDisposed();
    _checkCanMutate();
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

class Rxn<T> extends Rx<T?> {
  Rxn([super.value, String? debugLabel]) : super(debugLabel: debugLabel);
}

class RxInt extends Rx<int> {
  RxInt(super.value, {super.debugLabel});
}

class RxDouble extends Rx<double> {
  RxDouble(super.value, {super.debugLabel});
}

class RxBool extends Rx<bool> {
  RxBool(super.value, {super.debugLabel});

  void toggle() => value = !value;
}

class RxString extends Rx<String> {
  RxString(super.value, {super.debugLabel});
}

extension IntObsExtension on int {
  RxInt get obs => RxInt(this);
}

extension DoubleObsExtension on double {
  RxDouble get obs => RxDouble(this);
}

extension BoolObsExtension on bool {
  RxBool get obs => RxBool(this);
}

extension StringObsExtension on String {
  RxString get obs => RxString(this);
}

extension ObjectObsExtension<T> on T {
  Rx<T> get obs => Rx<T>(this);
}
