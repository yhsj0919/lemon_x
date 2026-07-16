import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

class RxBuilder<T> extends StatelessWidget {
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
