import 'dart:async';
import 'dart:collection';

import 'package:flutter/widgets.dart';

import '../di/container.dart';
import '../di/lemon.dart';
import '../di/page_owner.dart';

/// Optional Navigator adapter that gives [Lemon.put] a Route-owned lifetime.
///
/// Create a separate observer for each Navigator.
class LemonRouteObserver extends NavigatorObserver {
  final Map<Route<dynamic>, LxPageOwner> _owners =
      HashMap<Route<dynamic>, LxPageOwner>.identity();

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _ownerFor(route).activate();
  }

  @override
  void didChangeTop(Route<dynamic> topRoute, Route<dynamic>? previousTopRoute) {
    _ownerFor(topRoute).activate();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _retire(route, waitForTransition: true);
    if (previousRoute != null) _ownerFor(previousRoute).activate();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _retire(route, waitForTransition: false);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute != null) {
      _retire(oldRoute, waitForTransition: false);
    }
    if (newRoute != null) _ownerFor(newRoute).activate();
  }

  LxPageOwner _ownerFor(Route<dynamic> route) => _owners.putIfAbsent(route, () {
    final owner = LxPageOwner.route(
      root: Lemon.root,
      debugLabel:
          'route-${route.settings.name ?? route.runtimeType}-'
          '${identityHashCode(route)}',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (owner.container.state == LxContainerState.active) {
        owner.container.markReady();
      }
    });
    return owner;
  });

  void _retire(Route<dynamic> route, {required bool waitForTransition}) {
    final owner = _owners.remove(route);
    if (owner == null) return;
    // Make the outgoing Route's registrations unavailable immediately. Their
    // object disposal may still wait for the exit transition so the outgoing
    // widget tree can finish animating with live instances.
    owner.retire();
    final disposal = waitForTransition && route is TransitionRoute<dynamic>
        ? route.completed.then<void>((_) => owner.dispose())
        : owner.dispose();
    unawaited(
      disposal.catchError((Object error, StackTrace stack) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'lemon_x',
            context: ErrorDescription(
              'while disposing a Route-owned LemonX page scope',
            ),
          ),
        );
      }),
    );
  }
}
