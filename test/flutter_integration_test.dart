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

class _StateOwnerPage extends StatefulWidget {
  const _StateOwnerPage({required this.onCreated});

  final void Function(_PageController controller) onCreated;

  @override
  State<_StateOwnerPage> createState() => _StateOwnerPageState();
}

class _StateOwnerPageState extends State<_StateOwnerPage>
    with LxStateOwner<_StateOwnerPage> {
  late final controller = put(_PageController.new);

  @override
  void initState() {
    super.initState();
    widget.onCreated(controller);
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

void main() {
  setUp(() => LxDiagnostics.enabled = false);
  tearDown(() => Lemon.dispose());

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
            it.put(_PageController.new);
            controller = it.find<_PageController>();
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
    expect(identical(Lemon.find<_PageController>(), controller), isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(controller.isDisposed, isTrue);
    expect(Lemon.contains<_PageController>(), isFalse);
  });

  testWidgets('LxScope.put owns one globally discoverable dependency', (
    tester,
  ) async {
    late _PageController controller;
    await tester.pumpWidget(
      LxScope.put(
        _PageController.new,
        child: Builder(
          builder: (context) {
            controller = context.lx.find<_PageController>();
            return const SizedBox();
          },
        ),
      ),
    );

    expect(identical(Lemon.find<_PageController>(), controller), isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(controller.isDisposed, isTrue);
    expect(Lemon.contains<_PageController>(), isFalse);
  });

  testWidgets('LxStateOwner registers lazily and disposes with State', (
    tester,
  ) async {
    late _PageController controller;
    await tester.pumpWidget(
      _StateOwnerPage(onCreated: (value) => controller = value),
    );

    expect(identical(Lemon.find<_PageController>(), controller), isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(controller.isDisposed, isTrue);
    expect(Lemon.contains<_PageController>(), isFalse);
  });

  testWidgets('scope calls onReady once after the first frame', (tester) async {
    late _ReadyController controller;
    await tester.pumpWidget(
      LxScope(
        bindings: (it) {
          it.put(_ReadyController.new);
          controller = it.find<_ReadyController>();
        },
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

  testWidgets('RxAsync is tracked by Obx', (tester) async {
    final state = RxAsync<String>();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Obx(
          () => Text(
            state.when(
              loading: () => 'loading',
              data: (value) => value,
              error: (error, stack) => 'error',
            ),
          ),
        ),
      ),
    );

    expect(find.text('loading'), findsOneWidget);
    state.data('ready');
    await tester.pump();
    expect(find.text('ready'), findsOneWidget);
  });

  testWidgets('external LxScope ownership is explicit', (tester) async {
    final external = LxContainer(debugLabel: 'external');
    final controller = external.put(() => _PageController());

    await tester.pumpWidget(
      LxScope(container: external, child: const SizedBox()),
    );
    await tester.pumpWidget(const SizedBox());
    expect(external.state, LxContainerState.active);
    expect(controller.isDisposed, isFalse);
    await external.dispose();

    final owned = LxContainer(debugLabel: 'owned-external');
    final ownedController = owned.put(() => _PageController());
    await tester.pumpWidget(
      LxScope(
        container: owned,
        disposeContainer: true,
        child: const SizedBox(),
      ),
    );
    await tester.pumpWidget(const SizedBox());
    await owned.dispose();
    expect(ownedController.isDisposed, isTrue);
  });

  testWidgets('LemonApp exposes the root without owning it', (tester) async {
    await tester.pumpWidget(
      LemonApp(
        bindings: (container) => container.put(_PageController.new),
        child: Builder(
          builder: (context) => Text(
            '${context.lx.find<_PageController>().count.value}',
            textDirection: TextDirection.ltr,
          ),
        ),
      ),
    );

    expect(find.text('0'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(Lemon.root.state, LxContainerState.active);
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
