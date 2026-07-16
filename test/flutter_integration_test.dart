import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lemon_x/lemon_x.dart';

class _PageController extends LxController {
  final count = 0.obs;
}

class _ReadyController extends LxController {
  var readyCalls = 0;

  @override
  void onReady() => readyCalls++;
}

void main() {
  setUp(() => LxDiagnostics.enabled = false);

  testWidgets('Obx tracks values and rebuilds', (tester) async {
    final count = 0.obs;
    var builds = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Obx(() {
          builds++;
          return Text('${count.value}');
        }),
      ),
    );

    expect(find.text('0'), findsOneWidget);
    count.value = 1;
    await tester.pump();
    expect(find.text('1'), findsOneWidget);
    expect(builds, 2);
  });

  testWidgets('Obx switches dynamic dependencies', (tester) async {
    final useFirst = true.obs;
    final first = 1.obs;
    final second = 2.obs;

    await tester.pumpWidget(
      MaterialApp(
        home: Obx(() => Text('${useFirst.value ? first.value : second.value}')),
      ),
    );
    useFirst.value = false;
    await tester.pump();
    first.value = 3;
    await tester.pump();
    expect(find.text('2'), findsOneWidget);
    second.value = 4;
    await tester.pump();
    expect(find.text('4'), findsOneWidget);
  });

  testWidgets('LxScope exposes and disposes its controller', (tester) async {
    late _PageController controller;

    await tester.pumpWidget(
      MaterialApp(
        home: LxScope(
          bindings: (it) {
            controller = it.put(() => _PageController());
          },
          child: Builder(
            builder: (context) {
              final current = context.lx.find<_PageController>();
              return Obx(() => Text('${current.count.value}'));
            },
          ),
        ),
      ),
    );

    expect(controller.isDisposed, isFalse);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(controller.isDisposed, isTrue);
  });

  testWidgets('scope calls onReady once after the first frame', (tester) async {
    late _ReadyController controller;
    await tester.pumpWidget(
      LxScope(
        bindings: (it) => controller = it.put(() => _ReadyController()),
        child: const SizedBox(),
      ),
    );
    await tester.pump();

    expect(controller.readyCalls, 1);
    await tester.pump();
    expect(controller.readyCalls, 1);
  });

  testWidgets('RxBuilder interoperates through ValueListenable', (
    tester,
  ) async {
    final count = 0.obs;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RxBuilder<int>(
          listenable: count,
          builder: (_, value, child) => Text('$value'),
        ),
      ),
    );

    count.value = 3;
    await tester.pump();
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('workers honor time and cancellation', (tester) async {
    final value = 0.obs;
    final debounced = <int>[];
    final intervals = <int>[];
    final debounceWorker = debounce(
      value,
      debounced.add,
      time: const Duration(milliseconds: 100),
    );
    final intervalWorker = interval(
      value,
      intervals.add,
      time: const Duration(milliseconds: 100),
    );

    value.value = 1;
    value.value = 2;
    await tester.pump(const Duration(milliseconds: 100));
    expect(debounced, [2]);
    expect(intervals, [1]);

    debounceWorker.dispose();
    intervalWorker.dispose();
  });
}
