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

  test('workers can be disposed', () {
    final count = 0.obs;
    final values = <int>[];
    final worker = ever(count, values.add);

    count.value = 1;
    worker.dispose();
    count.value = 2;

    expect(values, [1]);
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
}
