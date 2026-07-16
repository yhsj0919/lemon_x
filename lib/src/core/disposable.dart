import 'dart:async';

/// A resource that can be released synchronously or asynchronously.
abstract interface class LxDisposable {
  FutureOr<void> dispose();
}
