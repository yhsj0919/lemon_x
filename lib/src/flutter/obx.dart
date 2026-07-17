import 'package:flutter/widgets.dart';

import '../reactive/tracking.dart';

/// Rebuilds its builder when any reactive value read by it changes.
class Obx extends StatefulWidget {
  /// Creates an automatically tracked reactive builder.
  const Obx(this.builder, {super.key});
  final Widget Function() builder;

  @override
  State<Obx> createState() => _ObxState();
}

class _ObxState extends State<Obx> implements RxDependencyCollector {
  Set<Listenable> _dependencies = <Listenable>{};
  Set<Listenable>? _collecting;

  @override
  void dependOn(Listenable listenable) => _collecting?.add(listenable);

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final next = <Listenable>{};
    _collecting = next;
    late Widget result;
    try {
      result = collectRxDependencies(
        this,
        widget.builder,
        forbidMutations: true,
      );
    } finally {
      _collecting = null;
    }
    for (final dependency in _dependencies) {
      if (!next.contains(dependency)) {
        dependency.removeListener(_changed);
      }
    }
    for (final dependency in next) {
      if (!_dependencies.contains(dependency)) {
        dependency.addListener(_changed);
      }
    }
    _dependencies = next;
    return result;
  }

  @override
  void dispose() {
    for (final dependency in _dependencies) {
      dependency.removeListener(_changed);
    }
    _dependencies.clear();
    super.dispose();
  }
}
