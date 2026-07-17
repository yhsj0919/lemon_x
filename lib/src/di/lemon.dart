import 'dart:async';

import 'container.dart';
import 'errors.dart';
import 'page_owner.dart';

/// Convenience access to the application-wide root [LxContainer].
class Lemon {
  Lemon._();

  static LxContainer _root = LxContainer(debugLabel: 'root');
  static LxContainer get root => _root;

  /// Registers an eager singleton in the current page owner.
  ///
  /// Set [permanent] to register in the application root. Without an active
  /// Route observer or `LxPage`-backed owner, non-permanent registration throws
  /// [LxNoPageScopeError].
  static T put<T>(
    LxFactory<T> builder, {
    Object? tag,
    bool permanent = false,
    LxDisposer<T>? dispose,
  }) => _target<T>(permanent).put(builder, tag: tag, dispose: dispose);

  static T putInstance<T>(
    T instance, {
    Object? tag,
    bool owned = false,
    bool permanent = false,
    LxDisposer<T>? dispose,
  }) => _target<T>(
    permanent,
  ).putInstance(instance, tag: tag, owned: owned, dispose: dispose);

  static void lazyPut<T>(
    LxFactory<T> builder, {
    Object? tag,
    bool permanent = false,
    LxDisposer<T>? dispose,
  }) => _target<T>(permanent).lazyPut(builder, tag: tag, dispose: dispose);

  static void factory<T>(
    LxFactory<T> builder, {
    Object? tag,
    bool permanent = false,
  }) => _target<T>(permanent).factory(builder, tag: tag);

  static Future<T> putAsync<T>(
    LxAsyncFactory<T> builder, {
    Object? tag,
    bool permanent = false,
    LxDisposer<T>? dispose,
  }) => _target<T>(permanent).putAsync(builder, tag: tag, dispose: dispose);

  static T find<T>({Object? tag}) => _root.findGlobal<T>(tag: tag);
  static Future<T> findAsync<T>({Object? tag}) =>
      _root.findAsyncGlobal<T>(tag: tag);

  static bool contains<T>({Object? tag}) => _root.containsGlobal<T>(tag: tag);

  /// Removes a root registration or one owned by the current page.
  static Future<bool> remove<T>({Object? tag}) =>
      _root.removeGlobal<T>(tag: tag, requester: LxPageOwners.current);

  static Future<void> reset() => _root.reset();

  static Future<void> dispose() async {
    final previous = _root;
    LxPageOwners.reset();
    _root = LxContainer(debugLabel: 'root');
    await previous.dispose();
  }

  static LxContainer _target<T>(bool permanent) {
    if (permanent) return _root;
    final page = LxPageOwners.current;
    if (page != null) return page;
    throw LxNoPageScopeError(
      '$T has no active page owner. Install LemonRouteObserver, wrap the '
      'page with LxPage, or use permanent: true.',
    );
  }
}
