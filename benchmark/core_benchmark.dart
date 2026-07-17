// ignore_for_file: avoid_print, curly_braces_in_flow_control_structures

import 'dart:typed_data';

import 'package:getx_plus/getx_plus.dart' as gx;
import 'package:lemon_x/lemon_x.dart' as lx;
import 'package:flutter_test/flutter_test.dart';

const int operations = 1000000;
const int samples = 9;
const int readPoolSize = 1024;
const int readIndexCount = 4096;
int _sink = 0;

class _Service {
  const _Service(this.id);
  final int id;
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

double _nsPerOp(int microseconds, int count) => microseconds * 1000 / count;

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

void _row(String name, int lemonUs, int getxUs, int count) {
  final lemonNs = _nsPerOp(lemonUs, count);
  final getxNs = _nsPerOp(getxUs, count);
  final ratio = getxNs / lemonNs;
  print(
    '${name.padRight(25)} '
    '${lemonNs.toStringAsFixed(1).padLeft(12)} '
    '${getxNs.toStringAsFixed(1).padLeft(12)} '
    '${ratio.toStringAsFixed(2).padLeft(9)}x',
  );
}

void main() {
  test('core performance comparison', _runBenchmark);
}

Future<void> _runBenchmark() async {
  lx.LxDiagnostics.enabled = false;
  print('Dart VM core benchmark (median of $samples, $operations operations)');
  print('Lower is better. Ratio = getx_plus / lemon_x.');
  print(
    'benchmark'.padRight(25) +
        'lemon ns/op'.padLeft(12) +
        'getx ns/op'.padLeft(13) +
        'ratio'.padLeft(10),
  );

  final readIndices = _createReadIndices();
  final lemonRead = List<lx.RxInt>.generate(
    readPoolSize,
    (i) => lx.RxInt(i * 2 + 1),
  );
  final getxRead = List<gx.RxInt>.generate(
    readPoolSize,
    (i) => gx.RxInt(i * 2 + 1),
  );
  _row(
    'Rx value read',
    _sample(() {
      var total = 0;
      for (var i = 0; i < operations; i++) {
        total += lemonRead[readIndices[i & (readIndexCount - 1)]].value;
      }
      _sink ^= total;
    }),
    _sample(() {
      var total = 0;
      for (var i = 0; i < operations; i++) {
        total += getxRead[readIndices[i & (readIndexCount - 1)]].value;
      }
      _sink ^= total;
    }),
    operations,
  );

  final lemonWrite = lx.RxInt(0);
  final getxWrite = gx.RxInt(0);
  _row(
    'Rx write (no listener)',
    _sample(() {
      for (var i = 0; i < operations; i++) lemonWrite.value = i;
      _sink ^= lemonWrite.value;
    }),
    _sample(() {
      for (var i = 0; i < operations; i++) getxWrite.value = i;
      _sink ^= getxWrite.value;
    }),
    operations,
  );

  var lemonEvents = 0;
  var getxEvents = 0;
  final lemonNotify = lx.RxInt(-1)..addListener(() => lemonEvents++);
  final getxNotify = gx.RxInt(-1);
  void onGetxNotify() => getxEvents++;
  getxNotify.addListener(onGetxNotify);
  _row(
    'Rx write (1 listener)',
    _sample(() {
      for (var i = 0; i < operations; i++) lemonNotify.value = i;
      _sink ^= lemonEvents;
    }),
    _sample(() {
      for (var i = 0; i < operations; i++) getxNotify.value = i;
      _sink ^= getxEvents;
    }),
    operations,
  );
  getxNotify.removeListener(onGetxNotify);

  final lemonContainer = lx.LxContainer()
    ..putInstance<_Service>(const _Service(7));
  gx.Get.put<_Service>(const _Service(7));
  _row(
    'DI find singleton',
    _sample(() {
      var total = 0;
      for (var i = 0; i < operations; i++) {
        total += lemonContainer.find<_Service>().id;
      }
      _sink ^= total;
    }),
    _sample(() {
      var total = 0;
      for (var i = 0; i < operations; i++) {
        total += gx.Get.find<_Service>().id;
      }
      _sink ^= total;
    }),
    operations,
  );

  lx.Lemon.putInstance<_Service>(const _Service(7), permanent: true);
  _row(
    'DI global find',
    _sample(() {
      var total = 0;
      for (var i = 0; i < operations; i++) {
        total += lx.Lemon.find<_Service>().id;
      }
      _sink ^= total;
    }),
    _sample(() {
      var total = 0;
      for (var i = 0; i < operations; i++) {
        total += gx.Get.find<_Service>().id;
      }
      _sink ^= total;
    }),
    operations,
  );

  const allocationCount = 100000;
  _row(
    'Rx object allocation',
    _sample(() {
      final values = <lx.RxInt>[];
      for (var i = 0; i < allocationCount; i++) {
        values.add(lx.RxInt(i));
      }
      _sink ^= values.last.value;
    }),
    _sample(() {
      final values = <gx.RxInt>[];
      for (var i = 0; i < allocationCount; i++) {
        values.add(gx.RxInt(i));
      }
      _sink ^= values.last.value;
    }),
    allocationCount,
  );

  await lemonContainer.dispose();
  await lx.Lemon.dispose();
  gx.Get.delete<_Service>(force: true);
  for (final value in lemonRead) value.dispose();
  lemonWrite.dispose();
  lemonNotify.dispose();
  for (final value in getxRead) value.close();
  getxWrite.close();
  getxNotify.close();

  const scopeCycles = 10000;
  final lifecycleWatch = Stopwatch()..start();
  for (var i = 0; i < scopeCycles; i++) {
    final scope = lx.LxContainer(parent: lx.Lemon.root);
    scope.put(() => _Service(i));
    await scope.dispose();
  }
  lifecycleWatch.stop();
  if (lx.Lemon.contains<_Service>()) {
    throw StateError('Scope lifecycle benchmark left a global registration.');
  }
  final lifecycleNs = _nsPerOp(
    lifecycleWatch.elapsedMicroseconds,
    scopeCycles,
  ).toStringAsFixed(1).padLeft(12);
  print('${'DI scope create/dispose'.padRight(25)}$lifecycleNs lemon ns/cycle');
  await lx.Lemon.dispose();
  print('checksum: $_sink');
}
