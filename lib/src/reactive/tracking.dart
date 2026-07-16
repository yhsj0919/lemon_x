import 'package:flutter/foundation.dart';

abstract interface class RxDependencyCollector {
  void dependOn(Listenable listenable);
}

RxDependencyCollector? _currentCollector;
int _mutationForbiddenDepth = 0;

T collectRxDependencies<T>(
  RxDependencyCollector collector,
  T Function() body, {
  bool forbidMutations = false,
}) {
  final previous = _currentCollector;
  _currentCollector = collector;
  if (forbidMutations) _mutationForbiddenDepth++;
  try {
    return body();
  } finally {
    if (forbidMutations) _mutationForbiddenDepth--;
    _currentCollector = previous;
  }
}

void reportRxRead(Listenable listenable) {
  _currentCollector?.dependOn(listenable);
}

bool get isRxMutationForbidden => _mutationForbiddenDepth > 0;
