import 'package:flutter/widgets.dart';

import '../di/lemon.dart';
import 'lx_scope.dart';

/// Exposes [Lemon.root] without replacing or wrapping the application widget.
class LemonApp extends StatelessWidget {
  /// Creates a root LemonX scope around [child].
  const LemonApp({required this.child, this.bindings, super.key});

  final Widget child;
  final LxBindings? bindings;

  @override
  Widget build(BuildContext context) => LxScope(
    container: Lemon.root,
    disposeContainer: false,
    bindings: bindings,
    child: child,
  );
}
