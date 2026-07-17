import 'dart:collection';

import 'rx.dart';

/// A list whose mutating operations notify reactive listeners.
class RxList<E> extends Rx<List<E>> with ListMixin<E> {
  RxList([Iterable<E> initial = const []]) : super(List<E>.of(initial));

  List<E> get _list => value;

  @override
  int get length => _list.length;

  @override
  set length(int value) {
    if (_list.length == value) return;
    _list.length = value;
    markChanged();
  }

  @override
  E operator [](int index) => _list[index];

  @override
  void operator []=(int index, E value) {
    if (_list[index] == value) return;
    _list[index] = value;
    markChanged();
  }

  @override
  void add(E element) {
    _list.add(element);
    markChanged();
  }

  @override
  void addAll(Iterable<E> iterable) {
    final values = iterable.toList();
    if (values.isEmpty) return;
    _list.addAll(values);
    markChanged();
  }

  @override
  void insert(int index, E element) {
    _list.insert(index, element);
    markChanged();
  }

  @override
  void insertAll(int index, Iterable<E> iterable) {
    final values = iterable.toList();
    if (values.isEmpty) return;
    _list.insertAll(index, values);
    markChanged();
  }

  @override
  E removeAt(int index) {
    final result = _list.removeAt(index);
    markChanged();
    return result;
  }

  @override
  void removeRange(int start, int end) {
    if (start == end) return;
    _list.removeRange(start, end);
    markChanged();
  }

  @override
  void replaceRange(int start, int end, Iterable<E> newContents) {
    final values = newContents.toList();
    if (start == end && values.isEmpty) return;
    _list.replaceRange(start, end, values);
    markChanged();
  }

  @override
  void setAll(int index, Iterable<E> iterable) {
    final values = iterable.toList();
    if (values.isEmpty) return;
    _list.setAll(index, values);
    markChanged();
  }

  @override
  bool remove(Object? element) {
    final removed = _list.remove(element);
    if (removed) markChanged();
    return removed;
  }

  @override
  void clear() {
    if (_list.isEmpty) return;
    _list.clear();
    markChanged();
  }

  @override
  void sort([int Function(E a, E b)? compare]) {
    _list.sort(compare);
    markChanged();
  }

  @override
  void removeWhere(bool Function(E element) test) {
    final before = length;
    _list.removeWhere(test);
    if (length != before) markChanged();
  }

  @override
  void retainWhere(bool Function(E element) test) {
    final before = length;
    _list.retainWhere(test);
    if (length != before) markChanged();
  }
}

/// A map whose mutating operations notify reactive listeners.
class RxMap<K, V> extends Rx<Map<K, V>> with MapMixin<K, V> {
  RxMap([Map<K, V>? initial]) : super(Map<K, V>.of(initial ?? const {}));

  Map<K, V> get _map => value;

  @override
  Iterable<K> get keys => _map.keys;

  @override
  V? operator [](Object? key) => _map[key];

  @override
  void operator []=(K key, V value) {
    if (_map.containsKey(key) && _map[key] == value) return;
    _map[key] = value;
    markChanged();
  }

  @override
  V? remove(Object? key) {
    if (!_map.containsKey(key)) return null;
    final result = _map.remove(key);
    markChanged();
    return result;
  }

  @override
  void clear() {
    if (_map.isEmpty) return;
    _map.clear();
    markChanged();
  }

  @override
  void addAll(Map<K, V> other) {
    if (other.isEmpty) return;
    var changed = false;
    for (final entry in other.entries) {
      if (!_map.containsKey(entry.key) || _map[entry.key] != entry.value) {
        changed = true;
        break;
      }
    }
    _map.addAll(other);
    if (changed) markChanged();
  }

  @override
  void addEntries(Iterable<MapEntry<K, V>> newEntries) {
    final entries = newEntries.toList();
    if (entries.isEmpty) return;
    _map.addEntries(entries);
    markChanged();
  }

  @override
  void removeWhere(bool Function(K key, V value) test) {
    final before = _map.length;
    _map.removeWhere(test);
    if (_map.length != before) markChanged();
  }

  @override
  void updateAll(V Function(K key, V value) update) {
    if (_map.isEmpty) return;
    _map.updateAll(update);
    markChanged();
  }
}

/// A set whose mutating operations notify reactive listeners.
class RxSet<E> extends Rx<Set<E>> with SetMixin<E> {
  RxSet([Iterable<E> initial = const {}]) : super(Set<E>.of(initial));

  Set<E> get _set => value;

  @override
  bool add(E value) {
    final changed = _set.add(value);
    if (changed) markChanged();
    return changed;
  }

  @override
  bool contains(Object? element) => _set.contains(element);

  @override
  Iterator<E> get iterator => _set.iterator;

  @override
  int get length => _set.length;

  @override
  E? lookup(Object? element) => _set.lookup(element);

  @override
  bool remove(Object? value) {
    final changed = _set.remove(value);
    if (changed) markChanged();
    return changed;
  }

  @override
  void addAll(Iterable<E> elements) {
    final before = _set.length;
    _set.addAll(elements);
    if (_set.length != before) markChanged();
  }

  @override
  void removeAll(Iterable<Object?> elements) {
    final before = _set.length;
    _set.removeAll(elements);
    if (_set.length != before) markChanged();
  }

  @override
  void retainAll(Iterable<Object?> elements) {
    final before = _set.length;
    _set.retainAll(elements);
    if (_set.length != before) markChanged();
  }

  @override
  void clear() {
    if (_set.isEmpty) return;
    _set.clear();
    markChanged();
  }

  @override
  Set<E> toSet() => Set<E>.of(_set);
}

extension ListObsExtension<E> on List<E> {
  /// Copies this list into a reactive [RxList].
  RxList<E> get obs => RxList<E>(this);
}

extension MapObsExtension<K, V> on Map<K, V> {
  /// Copies this map into a reactive [RxMap].
  RxMap<K, V> get obs => RxMap<K, V>(this);
}

extension SetObsExtension<E> on Set<E> {
  /// Copies this set into a reactive [RxSet].
  RxSet<E> get obs => RxSet<E>(this);
}
