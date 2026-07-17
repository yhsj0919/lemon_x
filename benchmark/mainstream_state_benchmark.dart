// ignore_for_file: avoid_print, curly_braces_in_flow_control_structures

import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getx_plus/getx_plus.dart' as gx;
import 'package:lemon_x/lemon_x.dart' as lx;
import 'package:mobx/mobx.dart' as mobx;
import 'package:signals_flutter/signals_flutter.dart' as signals;

const int operations = 100000;
const int readOperations = 200000;
const int allocationOperations = 20000;
const int samples = 5;
const int readPoolSize = 1024;
const int readIndexCount = 4096;
int _sink = 0;

final StateProvider<int> _riverpodCounter = StateProvider<int>((ref) => 0);
final StateProviderFamily<int, int> _riverpodRead =
    StateProvider.family<int, int>((ref, index) => index * 2 + 1);

class _ProviderCounter extends ChangeNotifier {
  _ProviderCounter([this._value = 0]);

  int _value;
  int get value => _value;

  set value(int next) {
    if (_value == next) return;
    _value = next;
    notifyListeners();
  }
}

class _CounterCubit extends Cubit<int> {
  _CounterCubit([super.initialState = 0]);

  void setValue(int value) => emit(value);
}

int _median(List<int> values) {
  values.sort();
  return values[values.length ~/ 2];
}

Uint16List _createReadIndices() {
  final indices = Uint16List(readIndexCount);
  var state = 0x9e3779b9;
  for (var i = 0; i < indices.length; i++) {
    state ^= state << 13;
    state ^= state >>> 17;
    state ^= state << 5;
    indices[i] = state & (readPoolSize - 1);
  }
  return indices;
}

int _measure(void Function() body) {
  final stopwatch = Stopwatch()..start();
  body();
  stopwatch.stop();
  return stopwatch.elapsedMicroseconds;
}

int _sample(void Function() body) {
  for (var i = 0; i < 3; i++) {
    body();
  }
  return _median(List<int>.generate(samples, (_) => _measure(body)));
}

void _printResult(String scenario, Map<String, int> timings, int count) {
  final ranked = timings.entries.toList()
    ..sort((a, b) => a.value.compareTo(b.value));
  print('\n$scenario (lower is better)');
  print('${'rank'.padRight(6)}${'framework'.padRight(26)}ns/op');
  for (var index = 0; index < ranked.length; index++) {
    final entry = ranked[index];
    final ns = entry.value * 1000 / count;
    print(
      '${(index + 1).toString().padRight(6)}'
      '${entry.key.padRight(26)}${ns.toStringAsFixed(1)}',
    );
  }
}

void main() {
  test(
    'mainstream state-management core performance',
    _runBenchmark,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

Future<void> _runBenchmark() async {
  print('Mainstream state benchmark: median of $samples samples');
  print('State writes always use a different integer value.');

  final readIndices = _createReadIndices();
  final baselineRead = List<int>.generate(readPoolSize, (i) => i * 2 + 1);
  final lemonRead = List<lx.RxInt>.generate(
    readPoolSize,
    (i) => lx.RxInt(i * 2 + 1),
  );
  final getxRead = List<gx.RxInt>.generate(
    readPoolSize,
    (i) => gx.RxInt(i * 2 + 1),
  );
  final providerRead = List<_ProviderCounter>.generate(
    readPoolSize,
    (i) => _ProviderCounter(i * 2 + 1),
  );
  final cubitRead = List<_CounterCubit>.generate(
    readPoolSize,
    (i) => _CounterCubit(i * 2 + 1),
  );
  final signalsRead = List<signals.FlutterSignal<int>>.generate(
    readPoolSize,
    (i) => signals.signal(i * 2 + 1),
  );
  final mobxRead = List<mobx.Observable<int>>.generate(
    readPoolSize,
    (i) => mobx.Observable(i * 2 + 1),
  );
  final riverpodReadContainer = ProviderContainer();

  _printResult('State read', {
    'List<int> baseline': _sample(() {
      var total = 0;
      for (var i = 0; i < readOperations; i++) {
        total += baselineRead[readIndices[i & (readIndexCount - 1)]];
      }
      _sink ^= total;
    }),
    'LemonX': _sample(() {
      var total = 0;
      for (var i = 0; i < readOperations; i++) {
        total += lemonRead[readIndices[i & (readIndexCount - 1)]].value;
      }
      _sink ^= total;
    }),
    'GetX Plus': _sample(() {
      var total = 0;
      for (var i = 0; i < readOperations; i++) {
        total += getxRead[readIndices[i & (readIndexCount - 1)]].value;
      }
      _sink ^= total;
    }),
    'Provider/ChangeNotifier': _sample(() {
      var total = 0;
      for (var i = 0; i < readOperations; i++) {
        total += providerRead[readIndices[i & (readIndexCount - 1)]].value;
      }
      _sink ^= total;
    }),
    'BLoC/Cubit': _sample(() {
      var total = 0;
      for (var i = 0; i < readOperations; i++) {
        total += cubitRead[readIndices[i & (readIndexCount - 1)]].state;
      }
      _sink ^= total;
    }),
    'Signals': _sample(() {
      var total = 0;
      for (var i = 0; i < readOperations; i++) {
        total += signalsRead[readIndices[i & (readIndexCount - 1)]].value;
      }
      _sink ^= total;
    }),
    'MobX': _sample(() {
      var total = 0;
      for (var i = 0; i < readOperations; i++) {
        total += mobxRead[readIndices[i & (readIndexCount - 1)]].value;
      }
      _sink ^= total;
    }),
    'Riverpod container.read': _sample(() {
      var total = 0;
      for (var i = 0; i < readOperations; i++) {
        final index = readIndices[i & (readIndexCount - 1)];
        total += riverpodReadContainer.read(_riverpodRead(index));
      }
      _sink ^= total;
    }),
  }, readOperations);

  final lemonWrite = lx.RxInt(-1);
  final getxWrite = gx.RxInt(-1);
  final providerWrite = _ProviderCounter(-1);
  final cubitWrite = _CounterCubit(-1);
  final signalsWrite = signals.signal(-1);
  final mobxWrite = mobx.Observable(-1);
  final riverpodWriteContainer = ProviderContainer();
  final riverpodWrite = riverpodWriteContainer.read(_riverpodCounter.notifier);

  _printResult('State write, no listener', {
    'LemonX': _sample(() {
      for (var i = 0; i < operations; i++) lemonWrite.value = i;
      _sink ^= lemonWrite.value;
    }),
    'GetX Plus': _sample(() {
      for (var i = 0; i < operations; i++) getxWrite.value = i;
      _sink ^= getxWrite.value;
    }),
    'Provider/ChangeNotifier': _sample(() {
      for (var i = 0; i < operations; i++) providerWrite.value = i;
      _sink ^= providerWrite.value;
    }),
    'BLoC/Cubit': _sample(() {
      for (var i = 0; i < operations; i++) cubitWrite.setValue(i);
      _sink ^= cubitWrite.state;
    }),
    'Signals': _sample(() {
      for (var i = 0; i < operations; i++) signalsWrite.value = i;
      _sink ^= signalsWrite.value;
    }),
    'MobX': _sample(() {
      for (var i = 0; i < operations; i++) mobxWrite.value = i;
      _sink ^= mobxWrite.value;
    }),
    'Riverpod StateProvider': _sample(() {
      for (var i = 0; i < operations; i++) riverpodWrite.state = i;
      _sink ^= riverpodWrite.state;
    }),
  }, operations);

  var lemonEvents = 0;
  var getxEvents = 0;
  var providerEvents = 0;
  var cubitEvents = 0;
  var signalsEvents = 0;
  var mobxEvents = 0;
  var riverpodEvents = 0;

  final lemonNotify = lx.RxInt(-1)..addListener(() => lemonEvents++);
  final getxNotify = gx.RxInt(-1);
  void onGetxNotify() => getxEvents++;
  getxNotify.addListener(onGetxNotify);
  final providerNotify = _ProviderCounter(-1)
    ..addListener(() => providerEvents++);
  final cubitNotify = _CounterCubit(-1);
  final cubitSubscription = cubitNotify.stream.listen((_) => cubitEvents++);
  final signalsNotify = signals.signal(-1)..addListener(() => signalsEvents++);
  final mobxNotify = mobx.Observable(-1);
  final setMobxNotify = mobx.Action((int value) => mobxNotify.value = value);
  final mobxDispose = mobx.reaction<int>(
    (_) => mobxNotify.value,
    (_) => mobxEvents++,
  );
  final riverpodNotifyContainer = ProviderContainer();
  final riverpodNotify = riverpodNotifyContainer.read(
    _riverpodCounter.notifier,
  );
  final riverpodSubscription = riverpodNotifyContainer.listen<int>(
    _riverpodCounter,
    (_, _) => riverpodEvents++,
  );

  _printResult('State write, one listener', {
    'LemonX': _sample(() {
      for (var i = 0; i < operations; i++) lemonNotify.value = i;
      _sink ^= lemonEvents;
    }),
    'GetX Plus': _sample(() {
      for (var i = 0; i < operations; i++) getxNotify.value = i;
      _sink ^= getxEvents;
    }),
    'Provider/ChangeNotifier': _sample(() {
      for (var i = 0; i < operations; i++) providerNotify.value = i;
      _sink ^= providerEvents;
    }),
    'BLoC/Cubit emit*': _sample(() {
      for (var i = 0; i < operations; i++) cubitNotify.setValue(i);
      _sink ^= cubitEvents;
    }),
    'Signals': _sample(() {
      for (var i = 0; i < operations; i++) signalsNotify.value = i;
      _sink ^= signalsEvents;
    }),
    'MobX': _sample(() {
      for (var i = 0; i < operations; i++) setMobxNotify(<dynamic>[i]);
      _sink ^= mobxEvents;
    }),
    'Riverpod StateProvider': _sample(() {
      for (var i = 0; i < operations; i++) riverpodNotify.state = i;
      _sink ^= riverpodEvents;
    }),
  }, operations);
  print(
    '* Cubit stream delivery is asynchronous; its timed value measures emit/enqueue.',
  );

  _printResult('State object allocation', {
    'LemonX': _sample(() {
      final values = <lx.RxInt>[];
      for (var i = 0; i < allocationOperations; i++) {
        values.add(lx.RxInt(i));
      }
      _sink ^= values.last.value;
    }),
    'GetX Plus': _sample(() {
      final values = <gx.RxInt>[];
      for (var i = 0; i < allocationOperations; i++) {
        values.add(gx.RxInt(i));
      }
      _sink ^= values.last.value;
    }),
    'Provider/ChangeNotifier': _sample(() {
      final values = <_ProviderCounter>[];
      for (var i = 0; i < allocationOperations; i++) {
        values.add(_ProviderCounter(i));
      }
      _sink ^= values.last.value;
    }),
    'BLoC/Cubit': _sample(() {
      final values = <_CounterCubit>[];
      for (var i = 0; i < allocationOperations; i++) {
        values.add(_CounterCubit(i));
      }
      _sink ^= values.last.state;
    }),
    'Signals': _sample(() {
      final values = <signals.FlutterSignal<int>>[];
      for (var i = 0; i < allocationOperations; i++) {
        values.add(signals.signal(i));
      }
      _sink ^= values.last.value;
    }),
    'MobX': _sample(() {
      final values = <mobx.Observable<int>>[];
      for (var i = 0; i < allocationOperations; i++) {
        values.add(mobx.Observable(i));
      }
      _sink ^= values.last.value;
    }),
  }, allocationOperations);

  // Let Cubit's asynchronous stream deliver the queued state events before
  // validating that every benchmark really had an active subscriber.
  await Future<void>.delayed(Duration.zero);
  expect(lemonEvents, greaterThan(0));
  expect(getxEvents, greaterThan(0));
  expect(providerEvents, greaterThan(0));
  expect(cubitEvents, greaterThan(0));
  expect(signalsEvents, greaterThan(0));
  expect(mobxEvents, greaterThan(0));
  expect(riverpodEvents, greaterThan(0));

  getxNotify.removeListener(onGetxNotify);
  await cubitSubscription.cancel();
  mobxDispose();
  riverpodSubscription.close();
  for (final value in lemonRead) value.dispose();
  lemonWrite.dispose();
  lemonNotify.dispose();
  for (final value in getxRead) value.close();
  getxWrite.close();
  getxNotify.close();
  for (final value in providerRead) value.dispose();
  providerWrite.dispose();
  providerNotify.dispose();
  for (final value in cubitRead) await value.close();
  for (final value in signalsRead) value.dispose();
  await cubitWrite.close();
  await cubitNotify.close();
  riverpodReadContainer.dispose();
  riverpodWriteContainer.dispose();
  riverpodNotifyContainer.dispose();
  print('\nchecksum: $_sink');
}
