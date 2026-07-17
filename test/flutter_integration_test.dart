import 'dart:async';

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

class _RouteOwnedPage extends StatefulWidget {
  const _RouteOwnedPage({required this.onCreated});

  final void Function(_PageController controller) onCreated;

  @override
  State<_RouteOwnedPage> createState() => _RouteOwnedPageState();
}

class _RouteOwnedPageState extends State<_RouteOwnedPage> {
  final controller = Lemon.put(_PageController.new);

  @override
  void initState() {
    super.initState();
    widget.onCreated(controller);
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

class _DialogController extends LxController {}

class _AmbientPageBody extends StatelessWidget {
  const _AmbientPageBody({required this.onBuild});

  final void Function(_PageController controller) onBuild;

  @override
  Widget build(BuildContext context) {
    final controller = Lemon.put(_PageController.new);
    onBuild(controller);
    return const SizedBox();
  }
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

  testWidgets('LxPage owns Lemon.put and tolerates repeated builds', (
    tester,
  ) async {
    final controllers = <_PageController>[];
    Widget page() => LxPage(child: _AmbientPageBody(onBuild: controllers.add));

    await tester.pumpWidget(page());
    await tester.pumpWidget(page());

    expect(controllers, hasLength(2));
    expect(identical(controllers.first, controllers.last), isTrue);
    expect(identical(Lemon.find<_PageController>(), controllers.first), isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(controllers.first.isDisposed, isTrue);
    expect(Lemon.contains<_PageController>(), isFalse);
  });

  testWidgets('route observer owns field-initialized Lemon.put', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    late _PageController controller;
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        navigatorObservers: [LemonRouteObserver()],
        home: const SizedBox(),
      ),
    );

    navigatorKey.currentState!.push<void>(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/login'),
        builder: (_) =>
            _RouteOwnedPage(onCreated: (value) => controller = value),
      ),
    );
    await tester.pumpAndSettle();

    expect(identical(Lemon.find<_PageController>(), controller), isTrue);
    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    await tester.pump();
    expect(controller.isDisposed, isTrue);
    expect(Lemon.contains<_PageController>(), isFalse);
  });

  testWidgets('route owner calls onReady once after its first frame', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    late _ReadyController controller;
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        navigatorObservers: [LemonRouteObserver()],
        home: const SizedBox(),
      ),
    );
    navigatorKey.currentState!.push<void>(
      MaterialPageRoute<void>(
        builder: (_) {
          controller = Lemon.put(_ReadyController.new);
          return const SizedBox();
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.readyCalls, 1);
    await tester.pump();
    expect(controller.readyCalls, 1);
    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
  });

  testWidgets('dialog finds page controller and owns its own put', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    late _PageController pageController;
    late _PageController foundFromDialog;
    late _DialogController dialogController;
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        navigatorObservers: [LemonRouteObserver()],
        home: const SizedBox(),
      ),
    );
    navigatorKey.currentState!.push<void>(
      MaterialPageRoute<void>(
        builder: (_) =>
            _RouteOwnedPage(onCreated: (value) => pageController = value),
      ),
    );
    await tester.pumpAndSettle();

    final pageContext = tester.element(find.byType(_RouteOwnedPage));
    unawaited(
      showDialog<void>(
        context: pageContext,
        builder: (_) {
          foundFromDialog = Lemon.find<_PageController>();
          dialogController = Lemon.put(_DialogController.new);
          return const SizedBox();
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(identical(foundFromDialog, pageController), isTrue);
    expect(dialogController.isDisposed, isFalse);
    await expectLater(
      Lemon.remove<_PageController>(),
      throwsA(isA<LxOwnershipError>()),
    );
    expect(pageController.isDisposed, isFalse);
    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    await tester.pump();
    expect(dialogController.isDisposed, isTrue);
    expect(pageController.isDisposed, isFalse);

    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
  });

  testWidgets('route replacement creates a new canonical controller', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    late _PageController first;
    late _PageController second;
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        navigatorObservers: [LemonRouteObserver()],
        home: const SizedBox(),
      ),
    );
    navigatorKey.currentState!.push<void>(
      MaterialPageRoute<void>(
        builder: (_) => _RouteOwnedPage(onCreated: (value) => first = value),
      ),
    );
    await tester.pumpAndSettle();

    navigatorKey.currentState!.pushReplacement<void, void>(
      MaterialPageRoute<void>(
        builder: (_) => _RouteOwnedPage(onCreated: (value) => second = value),
      ),
    );
    await tester.pumpAndSettle();

    expect(first.isDisposed, isTrue);
    expect(identical(first, second), isFalse);
    expect(identical(Lemon.find<_PageController>(), second), isTrue);
    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
  });

  testWidgets(
    'popped route releases canonical before its exit transition completes',
    (tester) async {
      final navigatorKey = GlobalKey<NavigatorState>();
      late _PageController first;
      late _PageController second;
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          navigatorObservers: [LemonRouteObserver()],
          home: const SizedBox(),
        ),
      );

      PageRoute<void> page(void Function(_PageController) onCreated) =>
          PageRouteBuilder<void>(
            transitionDuration: const Duration(milliseconds: 300),
            reverseTransitionDuration: const Duration(milliseconds: 300),
            pageBuilder: (_, _, _) => _RouteOwnedPage(onCreated: onCreated),
          );

      navigatorKey.currentState!.push<void>(page((value) => first = value));
      await tester.pumpAndSettle();

      navigatorKey.currentState!.pop();
      expect(Lemon.contains<_PageController>(), isFalse);
      expect(first.isDisposed, isFalse);

      navigatorKey.currentState!.push<void>(page((value) => second = value));
      await tester.pump();

      expect(identical(first, second), isFalse);
      expect(identical(Lemon.find<_PageController>(), second), isTrue);
      expect(second.isDisposed, isFalse);

      await tester.pumpAndSettle();
      expect(first.isDisposed, isTrue);
      expect(second.isDisposed, isFalse);

      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
    },
  );

  testWidgets('removing a route disposes its page owner', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    late _PageController controller;
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        navigatorObservers: [LemonRouteObserver()],
        home: const SizedBox(),
      ),
    );
    final route = MaterialPageRoute<void>(
      builder: (_) => _RouteOwnedPage(onCreated: (value) => controller = value),
    );
    navigatorKey.currentState!.push<void>(route);
    await tester.pumpAndSettle();

    navigatorKey.currentState!.removeRoute(route);
    await tester.pump();

    expect(controller.isDisposed, isTrue);
    expect(Lemon.contains<_PageController>(), isFalse);
  });

  testWidgets('separate observers isolate multiple Navigator lifetimes', (
    tester,
  ) async {
    final leftKey = GlobalKey<NavigatorState>();
    final rightKey = GlobalKey<NavigatorState>();
    Navigator navigator(GlobalKey<NavigatorState> key) => Navigator(
      key: key,
      observers: [LemonRouteObserver()],
      onGenerateRoute: (_) =>
          MaterialPageRoute<void>(builder: (_) => const SizedBox()),
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          children: [
            Expanded(child: navigator(leftKey)),
            Expanded(child: navigator(rightKey)),
          ],
        ),
      ),
    );
    late _PageController left;
    late _PageController right;
    leftKey.currentState!.push<void>(
      MaterialPageRoute<void>(
        builder: (_) {
          left = Lemon.put(_PageController.new, tag: 'left');
          return const SizedBox();
        },
      ),
    );
    await tester.pumpAndSettle();
    rightKey.currentState!.push<void>(
      MaterialPageRoute<void>(
        builder: (_) {
          right = Lemon.put(_PageController.new, tag: 'right');
          return const SizedBox();
        },
      ),
    );
    await tester.pumpAndSettle();

    leftKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(left.isDisposed, isTrue);
    expect(right.isDisposed, isFalse);

    rightKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(right.isDisposed, isTrue);
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
