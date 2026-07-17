import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lemon_x/lemon_x.dart';

void main() {
  test('Rx notifies only when value changes', () {
    final count = 0.obs;
    var calls = 0;
    count.addListener(() => calls++);

    count.value = 1;
    count.value = 1;

    expect(count.value, 1);
    expect(calls, 1);
  });

  test(
    'Rx refreshes, supports custom equality, and rejects disposed access',
    () {
      final value = Rx<String>(
        'LEMON',
        equals: (previous, next) =>
            previous.toLowerCase() == next.toLowerCase(),
      );
      var calls = 0;
      value.addListener(() => calls++);

      value.value = 'lemon';
      expect(calls, 0);
      value.refresh();
      expect(calls, 1);
      value.dispose();

      expect(() => value.value, throwsA(isA<LxDisposedError>()));
      expect(() => value.value = 'x', throwsA(isA<LxDisposedError>()));
    },
  );

  test('rxBatch emits once per changed Rx', () {
    final count = 0.obs;
    var calls = 0;
    count.addListener(() => calls++);

    rxBatch(() {
      count.value = 1;
      count.value = 2;
    });

    expect(count.value, 2);
    expect(calls, 1);
  });

  test('nested batch restores scheduling and flushes after an exception', () {
    final value = 0.obs;
    final seen = <int>[];
    value.addListener(() => seen.add(value.value));

    expect(
      () => rxBatch(() {
        value.value = 1;
        rxBatch(() => value.value = 2);
        throw StateError('stop');
      }),
      throwsStateError,
    );
    value.value = 3;

    expect(seen, [2, 3]);
  });

  test('listener can remove itself during notification', () {
    final value = 0.obs;
    var calls = 0;
    late VoidCallback listener;
    listener = () {
      calls++;
      value.removeListener(listener);
    };
    value.addListener(listener);

    value.value = 1;
    value.value = 2;

    expect(calls, 1);
  });

  test('RxComputed caches and invalidates', () {
    final price = 10.obs;
    final quantity = 2.obs;
    var computations = 0;
    final total = RxComputed(() {
      computations++;
      return price.value * quantity.value;
    });

    expect(total.value, 20);
    expect(total.value, 20);
    expect(computations, 1);
    quantity.value = 3;
    expect(total.value, 30);
    expect(computations, 2);
  });

  test('RxComputed rejects mutations while calculating', () {
    final count = 0.obs;
    final invalid = RxComputed(() {
      count.value++;
      return count.value;
    });

    expect(() => invalid.value, throwsA(isA<LxInvalidMutationError>()));
  });

  test('RxComputed supports chains and dynamic dependencies', () {
    final useFirst = true.obs;
    final first = 2.obs;
    final second = 10.obs;
    final selected = RxComputed(
      () => useFirst.value ? first.value : second.value,
    );
    final doubled = RxComputed(() => selected.value * 2);

    expect(doubled.value, 4);
    useFirst.value = false;
    expect(doubled.value, 20);
    first.value = 3;
    expect(doubled.value, 20);
    second.value = 11;
    expect(doubled.value, 22);
  });

  test('RxComputed detects cycles and can retry after computation failure', () {
    late RxComputed<int> left;
    late RxComputed<int> right;
    left = RxComputed(() => right.value + 1, debugLabel: 'left');
    right = RxComputed(() => left.value + 1, debugLabel: 'right');
    expect(() => left.value, throwsA(isA<LxCircularDependencyError>()));

    var fail = true;
    final retryable = RxComputed(() {
      if (fail) throw StateError('first');
      return 7;
    });
    expect(() => retryable.value, throwsStateError);
    fail = false;
    expect(retryable.value, 7);
  });

  test('reactive collections notify once per operation', () {
    final items = <int>[].obs;
    final map = <String, int>{}.obs;
    final set = <int>{}.obs;
    var calls = 0;
    var mapCalls = 0;
    var setCalls = 0;
    items.addListener(() => calls++);
    map.addListener(() => mapCalls++);
    set.addListener(() => setCalls++);

    items.addAll([3, 1, 2]);
    items.sort();
    map.addAll({'one': 1, 'two': 2});
    set.addAll([1, 2, 3]);

    expect(items, [1, 2, 3]);
    expect(calls, 2);
    expect(mapCalls, 1);
    expect(setCalls, 1);
  });

  test('reactive list covers common mutable operations', () {
    final list = RxList<int>([1, 2, 3]);
    var calls = 0;
    list.addListener(() => calls++);

    list[0] = 1;
    list[0] = 4;
    list.insert(1, 5);
    list.insertAll(2, [6, 7]);
    expect(list.removeAt(0), 4);
    list.removeRange(0, 1);
    list.replaceRange(0, 1, [8, 9]);
    list.setAll(0, [10, 11]);
    expect(list.remove(3), isTrue);
    list.addAll(const []);
    list.replaceAll([12, 13]);
    list.replaceAll(list);
    list.replaceAll(list.where((value) => value.isEven));
    list.removeWhere((value) => value == 9);
    list.retainWhere((value) => value >= 10);
    list.length = 1;
    list.clear();

    expect(list, isEmpty);
    expect(calls, 11);
  });

  test('RxList replaceAll replaces contents with one notification', () {
    final list = RxList<int>([1, 2, 3]);
    var calls = 0;
    list.addListener(() => calls++);

    list.replaceAll([4, 5]);
    expect(list, [4, 5]);
    expect(calls, 1);

    list.replaceAll([4, 5]);
    list.replaceAll(list);
    expect(calls, 1);

    list.replaceAll(const []);
    expect(list, isEmpty);
    expect(calls, 2);
  });

  test('RxList reorder helpers mutate with one notification', () {
    final list = RxList<int>([1, 2, 3, 4]);
    var calls = 0;
    list.addListener(() => calls++);

    list.reverse();
    expect(list, [4, 3, 2, 1]);
    expect(calls, 1);

    list.swap(0, 3);
    expect(list, [1, 3, 2, 4]);
    expect(calls, 2);

    list.move(1, 3);
    expect(list, [1, 2, 4, 3]);
    expect(calls, 3);

    list.shuffle(Random(7));
    expect(list, hasLength(4));
    expect(list.toSet(), {1, 2, 3, 4});
    expect(calls, 4);

    list.swap(2, 2);
    list.move(1, 1);
    expect(calls, 4);
  });

  test('reactive map and set cover common mutable operations', () {
    final map = RxMap<String, int>({'a': 1});
    final set = RxSet<int>([1, 2]);
    var mapCalls = 0;
    var setCalls = 0;
    map.addListener(() => mapCalls++);
    set.addListener(() => setCalls++);

    map['a'] = 1;
    map['b'] = 2;
    map.addEntries(const [MapEntry('c', 3)]);
    map.updateAll((key, value) => value + 1);
    map.removeWhere((key, value) => key == 'c');
    expect(map.remove('missing'), isNull);
    expect(map.remove('a'), 2);
    map.clear();

    expect(set.contains(1), isTrue);
    expect(set.lookup(2), 2);
    expect(set.toSet(), {1, 2});
    set.add(2);
    set.add(3);
    set.addAll([3, 4]);
    set.removeAll([1]);
    set.retainAll([2, 4]);
    expect(set.remove(9), isFalse);
    expect(set.remove(2), isTrue);
    set.clear();

    expect(map, isEmpty);
    expect(set, isEmpty);
    expect(mapCalls, 6);
    expect(setCalls, 6);
  });

  test('workers can be disposed', () {
    final count = 0.obs;
    final values = <int>[];
    final worker = ever(count, values.add);

    count.value = 1;
    worker.dispose();
    count.value = 2;

    expect(values, [1]);
  });

  test('once, debounce, and interval honor cancellation', () async {
    final value = 0.obs;
    final onceValues = <int>[];
    final debounced = <int>[];
    final intervals = <int>[];
    final onceWorker = once(value, onceValues.add);
    final debounceWorker = debounce(
      value,
      debounced.add,
      time: const Duration(milliseconds: 5),
    );
    final intervalWorker = interval(
      value,
      intervals.add,
      time: const Duration(milliseconds: 5),
    );

    value.value = 1;
    value.value = 2;
    debounceWorker.dispose();
    intervalWorker.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(onceValues, [1]);
    expect(debounced, isEmpty);
    expect(intervals, [1]);
    expect(onceWorker.isDisposed, isTrue);
  });

  test('effect tracks dependencies and cleans up', () async {
    final count = 0.obs;
    final values = <int>[];
    var cleanups = 0;
    final effect = rxEffect(() {
      values.add(count.value);
      return () {
        cleanups++;
      };
    });

    count.value = 1;
    await Future<void>.delayed(Duration.zero);
    await effect.dispose();
    count.value = 2;
    await Future<void>.delayed(Duration.zero);

    expect(values, [0, 1]);
    expect(cleanups, 2);
  });

  test(
    'effect serializes async cleanup and coalesces a pending rerun',
    () async {
      final value = 0.obs;
      final cleanupGate = Completer<void>();
      final runs = <int>[];
      var cleanupRunning = 0;
      var maxCleanupRunning = 0;
      final effect = rxEffect(() {
        final current = value.value;
        runs.add(current);
        return () async {
          cleanupRunning++;
          if (cleanupRunning > maxCleanupRunning) {
            maxCleanupRunning = cleanupRunning;
          }
          if (current == 0) await cleanupGate.future;
          cleanupRunning--;
        };
      });

      value.value = 1;
      await Future<void>.delayed(Duration.zero);
      value.value = 2;
      cleanupGate.complete();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(runs, [0, 2]);
      expect(maxCleanupRunning, 1);
      await effect.dispose();
    },
  );

  test(
    'RxAsync keeps three states distinct and supports nullable data',
    () async {
      final state = RxAsync<String?>();
      var notifications = 0;
      state.addListener(() => notifications++);

      expect(state.isLoading, isTrue);
      state.data(null);
      expect(state.hasData, isTrue);
      expect(state.value, isNull);
      expect(
        state.when(
          loading: () => 'loading',
          data: (value) => 'data:$value',
          error: (error, stack) => 'error',
        ),
        'data:null',
      );

      final trace = StackTrace.current;
      state.error(StateError('failed'), trace);
      expect(state.hasError, isTrue);
      expect(state.errorValue, isA<StateError>());
      expect(state.stackTrace, same(trace));

      await state.guard(() async => 'ok');
      expect(state.hasData, isTrue);
      expect(state.value, 'ok');
      await state.guard(() async => throw ArgumentError('bad'));
      expect(state.hasError, isTrue);
      expect(state.errorValue, isA<ArgumentError>());
      expect(notifications, 6);
      state.dispose();
    },
  );
}
