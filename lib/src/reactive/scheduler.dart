import 'rx.dart';

int _batchDepth = 0;
final Set<Rx<dynamic>> _pending = <Rx<dynamic>>{};

bool get isRxBatching => _batchDepth > 0;

void scheduleRxNotification(Rx<dynamic> rx) {
  if (_batchDepth > 0) {
    _pending.add(rx);
  } else {
    rx.notifyNow();
  }
}

/// Groups listener notifications while keeping value writes synchronous.
T rxBatch<T>(T Function() body) {
  _batchDepth++;
  try {
    return body();
  } finally {
    _batchDepth--;
    if (_batchDepth == 0 && _pending.isNotEmpty) {
      final pending = List<Rx<dynamic>>.of(_pending);
      _pending.clear();
      for (final rx in pending) {
        if (!rx.isDisposed) rx.notifyNow();
      }
    }
  }
}
