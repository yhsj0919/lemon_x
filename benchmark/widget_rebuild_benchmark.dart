// ignore_for_file: avoid_print

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getx_plus/getx_plus.dart' as gx;
import 'package:lemon_x/lemon_x.dart' as lx;
import 'package:mobx/mobx.dart' as mobx;
import 'package:provider/provider.dart' as provider;
import 'package:signals_flutter/signals_flutter.dart' as signals;

const int rebuildsPerSample = 250;
const int warmupRebuilds = 20;
const int samples = 5;

final StateProvider<int> _riverpodCounter = StateProvider<int>((ref) => -1);

class _ProviderCounter extends ChangeNotifier {
  int _value = -1;
  int get value => _value;

  void setValue(int next) {
    if (_value == next) return;
    _value = next;
    notifyListeners();
  }
}

class _CounterCubit extends Cubit<int> {
  _CounterCubit() : super(-1);

  void setValue(int next) => emit(next);
}

class _ParentBuildProbe extends StatelessWidget {
  const _ParentBuildProbe({required this.onBuild, required this.child});

  final VoidCallback onBuild;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    onBuild();
    return child;
  }
}

class _WidgetCase {
  _WidgetCase({
    required this.widget,
    required this.update,
    required this.childBuilds,
    required this.parentBuilds,
    required this.dispose,
  });

  final Widget widget;
  final void Function(int value) update;
  final int Function() childBuilds;
  final int Function() parentBuilds;
  final FutureOr<void> Function() dispose;
}

typedef _WidgetCaseFactory = _WidgetCase Function();

int _median(List<int> values) {
  values.sort();
  return values[values.length ~/ 2];
}

Widget _host(Widget child) => Directionality(
  textDirection: TextDirection.ltr,
  child: Center(child: child),
);

Future<int> _updateAndPump(
  WidgetTester tester,
  _WidgetCase benchmark,
  int value,
) async {
  final buildsBefore = benchmark.childBuilds();
  benchmark.update(value);
  for (var pump = 0; pump < 3; pump++) {
    await tester.pump();
    if (benchmark.childBuilds() != buildsBefore) {
      expect(benchmark.childBuilds() - buildsBefore, 1);
      return pump + 1;
    }
  }
  fail('Widget did not rebuild within three pump cycles.');
}

_WidgetCase _lemonCase() {
  final state = lx.RxInt(-1);
  var childBuilds = 0;
  var parentBuilds = 0;
  final child = lx.Obx(() {
    childBuilds++;
    return Text('${state.value}');
  });
  return _WidgetCase(
    widget: _ParentBuildProbe(onBuild: () => parentBuilds++, child: child),
    update: (value) => state.value = value,
    childBuilds: () => childBuilds,
    parentBuilds: () => parentBuilds,
    dispose: state.dispose,
  );
}

_WidgetCase _getxCase() {
  final state = gx.RxInt(-1);
  var childBuilds = 0;
  var parentBuilds = 0;
  final child = gx.Obx(() {
    childBuilds++;
    return Text('${state.value}');
  });
  return _WidgetCase(
    widget: _ParentBuildProbe(onBuild: () => parentBuilds++, child: child),
    update: (value) => state.value = value,
    childBuilds: () => childBuilds,
    parentBuilds: () => parentBuilds,
    dispose: state.close,
  );
}

_WidgetCase _providerCase() {
  final state = _ProviderCounter();
  var childBuilds = 0;
  var parentBuilds = 0;
  final child = provider.ChangeNotifierProvider<_ProviderCounter>.value(
    value: state,
    child: provider.Consumer<_ProviderCounter>(
      builder: (context, counter, child) {
        childBuilds++;
        return Text('${counter.value}');
      },
    ),
  );
  return _WidgetCase(
    widget: _ParentBuildProbe(onBuild: () => parentBuilds++, child: child),
    update: state.setValue,
    childBuilds: () => childBuilds,
    parentBuilds: () => parentBuilds,
    dispose: state.dispose,
  );
}

_WidgetCase _blocCase() {
  final state = _CounterCubit();
  var childBuilds = 0;
  var parentBuilds = 0;
  final child = BlocBuilder<_CounterCubit, int>(
    bloc: state,
    builder: (context, value) {
      childBuilds++;
      return Text('$value');
    },
  );
  return _WidgetCase(
    widget: _ParentBuildProbe(onBuild: () => parentBuilds++, child: child),
    update: state.setValue,
    childBuilds: () => childBuilds,
    parentBuilds: () => parentBuilds,
    dispose: state.close,
  );
}

_WidgetCase _signalsCase() {
  final state = signals.signal(-1);
  var childBuilds = 0;
  var parentBuilds = 0;
  final child = signals.SignalBuilder(
    builder: (context) {
      childBuilds++;
      return Text('${state.value}');
    },
  );
  return _WidgetCase(
    widget: _ParentBuildProbe(onBuild: () => parentBuilds++, child: child),
    update: (value) => state.value = value,
    childBuilds: () => childBuilds,
    parentBuilds: () => parentBuilds,
    dispose: state.dispose,
  );
}

_WidgetCase _mobxCase() {
  final state = mobx.Observable(-1);
  final setValue = mobx.Action((int value) => state.value = value);
  var childBuilds = 0;
  var parentBuilds = 0;
  final child = Observer(
    builder: (context) {
      childBuilds++;
      return Text('${state.value}');
    },
  );
  return _WidgetCase(
    widget: _ParentBuildProbe(onBuild: () => parentBuilds++, child: child),
    update: (value) => setValue(<dynamic>[value]),
    childBuilds: () => childBuilds,
    parentBuilds: () => parentBuilds,
    dispose: () {},
  );
}

_WidgetCase _riverpodCase() {
  final container = ProviderContainer();
  final notifier = container.read(_riverpodCounter.notifier);
  var childBuilds = 0;
  var parentBuilds = 0;
  final child = UncontrolledProviderScope(
    container: container,
    child: Consumer(
      builder: (context, ref, child) {
        childBuilds++;
        return Text('${ref.watch(_riverpodCounter)}');
      },
    ),
  );
  return _WidgetCase(
    widget: _ParentBuildProbe(onBuild: () => parentBuilds++, child: child),
    update: (value) => notifier.state = value,
    childBuilds: () => childBuilds,
    parentBuilds: () => parentBuilds,
    dispose: container.dispose,
  );
}

Future<({int microseconds, int pumps})> _runSample(
  WidgetTester tester,
  _WidgetCaseFactory createCase,
) async {
  final benchmark = createCase();
  await tester.pumpWidget(_host(benchmark.widget));
  expect(benchmark.childBuilds(), 1);
  expect(benchmark.parentBuilds(), 1);

  for (var i = 0; i < warmupRebuilds; i++) {
    await _updateAndPump(tester, benchmark, i);
  }
  final buildsBeforeMeasurement = benchmark.childBuilds();
  var pumps = 0;
  final stopwatch = Stopwatch()..start();
  for (var i = 0; i < rebuildsPerSample; i++) {
    pumps += await _updateAndPump(tester, benchmark, 1000 + i);
  }
  stopwatch.stop();

  expect(benchmark.childBuilds() - buildsBeforeMeasurement, rebuildsPerSample);
  expect(benchmark.parentBuilds(), 1);
  await tester.pumpWidget(const SizedBox.shrink());
  await benchmark.dispose();
  return (microseconds: stopwatch.elapsedMicroseconds, pumps: pumps);
}

void main() {
  testWidgets('reactive widget rebuild performance', (tester) async {
    final frameworks = <String, _WidgetCaseFactory>{
      'LemonX Obx': _lemonCase,
      'GetX Plus Obx': _getxCase,
      'Provider Consumer': _providerCase,
      'BLoC BlocBuilder': _blocCase,
      'Signals SignalBuilder': _signalsCase,
      'MobX Observer': _mobxCase,
      'Riverpod Consumer': _riverpodCase,
    };
    final timings = <String, List<int>>{
      for (final name in frameworks.keys) name: <int>[],
    };
    final pumpCounts = <String, List<int>>{
      for (final name in frameworks.keys) name: <int>[],
    };

    // Warm every implementation before measuring so the first framework does
    // not pay all Flutter/JIT startup costs.
    for (final entry in frameworks.entries) {
      print('Warming ${entry.key}...');
      await _runSample(tester, entry.value);
    }
    final entries = frameworks.entries.toList();
    for (var sample = 0; sample < samples; sample++) {
      print('Measuring sample ${sample + 1}/$samples...');
      for (var offset = 0; offset < entries.length; offset++) {
        final entry = entries[(sample + offset) % entries.length];
        final result = await _runSample(tester, entry.value);
        timings[entry.key]!.add(result.microseconds);
        pumpCounts[entry.key]!.add(result.pumps);
      }
    }

    final results = <String, int>{
      for (final entry in timings.entries) entry.key: _median(entry.value),
    };
    final ranked = results.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    print('\nWidget rebuild benchmark');
    print(
      'Median of $samples samples, $rebuildsPerSample update + pump frames',
    );
    print(
      '${'rank'.padRight(6)}${'framework'.padRight(28)}'
      '${'us/rebuild'.padRight(14)}pumps/rebuild',
    );
    for (var index = 0; index < ranked.length; index++) {
      final entry = ranked[index];
      final microseconds = entry.value / rebuildsPerSample;
      final pumps = _median(pumpCounts[entry.key]!) / rebuildsPerSample;
      print(
        '${(index + 1).toString().padRight(6)}'
        '${entry.key.padRight(28)}'
        '${microseconds.toStringAsFixed(1).padRight(14)}'
        '${pumps.toStringAsFixed(2)}',
      );
    }
  });
}
