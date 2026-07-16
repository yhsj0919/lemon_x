import 'dart:async';

import 'container.dart';

class Lemon {
  Lemon._();

  static LxContainer _root = LxContainer(debugLabel: 'root');
  static LxContainer get root => _root;

  static T put<T>(
    LxFactory<T> builder, {
    Object? tag,
    LxDisposer<T>? dispose,
  }) => _root.put(builder, tag: tag, dispose: dispose);

  static T putInstance<T>(T instance, {Object? tag, bool owned = false}) =>
      _root.putInstance(instance, tag: tag, owned: owned);

  static void lazyPut<T>(LxFactory<T> builder, {Object? tag}) =>
      _root.lazyPut(builder, tag: tag);

  static void factory<T>(LxFactory<T> builder, {Object? tag}) =>
      _root.factory(builder, tag: tag);

  static Future<T> putAsync<T>(LxAsyncFactory<T> builder, {Object? tag}) =>
      _root.putAsync(builder, tag: tag);

  static T find<T>({Object? tag}) => _root.find<T>(tag: tag);
  static Future<T> findAsync<T>({Object? tag}) => _root.findAsync<T>(tag: tag);

  static bool contains<T>({Object? tag}) => _root.contains<T>(tag: tag);

  static Future<bool> remove<T>({Object? tag}) => _root.remove<T>(tag: tag);

  static Future<void> reset() => _root.reset();

  static Future<void> dispose() async {
    final previous = _root;
    _root = LxContainer(debugLabel: 'root');
    await previous.dispose();
  }
}
