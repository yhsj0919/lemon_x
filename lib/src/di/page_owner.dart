import 'container.dart';

enum LxPageOwnerKind { route, widget }

/// Internal single-owner lifetime used by route and Widget page adapters.
///
/// This file is intentionally not exported from the package API.
class LxPageOwner {
  LxPageOwner.route({required LxContainer root, required String debugLabel})
    : kind = LxPageOwnerKind.route,
      routeParent = null,
      container = LxContainer(parent: root, debugLabel: debugLabel);

  LxPageOwner.widget({required LxContainer root, required String debugLabel})
    : kind = LxPageOwnerKind.widget,
      routeParent = LxPageOwners.currentRouteOwner,
      container = LxContainer(parent: root, debugLabel: debugLabel);

  final LxPageOwnerKind kind;
  final LxPageOwner? routeParent;
  final LxContainer container;
  bool _active = false;

  bool get isActive => _active && container.state == LxContainerState.active;

  void activate() => LxPageOwners.activate(this);

  void deactivate() => LxPageOwners.deactivate(this);

  Future<void> dispose() async {
    deactivate();
    await container.dispose();
  }
}

/// Selects the active page owner without requiring a BuildContext at put time.
class LxPageOwners {
  LxPageOwners._();

  static final List<LxPageOwner> _widgetOwners = <LxPageOwner>[];
  static LxPageOwner? _currentRouteOwner;

  static LxPageOwner? get currentRouteOwner {
    final route = _currentRouteOwner;
    if (route != null && !route.isActive) _currentRouteOwner = null;
    return _currentRouteOwner;
  }

  static LxContainer? get current {
    _widgetOwners.removeWhere((owner) => !owner.isActive);
    final route = currentRouteOwner;
    for (final owner in _widgetOwners.reversed) {
      if (identical(owner.routeParent, route)) return owner.container;
    }
    return route?.container;
  }

  static void activate(LxPageOwner owner) {
    if (owner.container.state != LxContainerState.active) {
      throw StateError('Cannot activate a disposed page owner.');
    }
    owner._active = true;
    if (owner.kind == LxPageOwnerKind.route) {
      final previous = _currentRouteOwner;
      if (previous != null && !identical(previous, owner)) {
        previous._active = false;
      }
      _currentRouteOwner = owner;
      return;
    }
    _widgetOwners.removeWhere((entry) => identical(entry, owner));
    _widgetOwners.add(owner);
  }

  static void deactivate(LxPageOwner owner) {
    owner._active = false;
    if (owner.kind == LxPageOwnerKind.route) {
      if (identical(_currentRouteOwner, owner)) _currentRouteOwner = null;
    } else {
      _widgetOwners.removeWhere((entry) => identical(entry, owner));
    }
  }

  static void reset() {
    _currentRouteOwner?._active = false;
    _currentRouteOwner = null;
    for (final owner in _widgetOwners) {
      owner._active = false;
    }
    _widgetOwners.clear();
  }
}
