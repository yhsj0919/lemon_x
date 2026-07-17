import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Explicitly rebuilds from a single [ValueListenable].
class RxBuilder<T> extends StatelessWidget {
  /// Creates a value-listenable builder with an optional static [child].
  const RxBuilder({
    required this.listenable,
    required this.builder,
    this.child,
    super.key,
  });

  final ValueListenable<T> listenable;
  final ValueWidgetBuilder<T> builder;
  final Widget? child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<T>(
    valueListenable: listenable,
    builder: builder,
    child: child,
  );
}
