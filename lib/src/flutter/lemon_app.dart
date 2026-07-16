import 'package:flutter/widgets.dart';

import '../di/lemon.dart';
import 'lx_scope.dart';

class LemonApp extends StatelessWidget {
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
