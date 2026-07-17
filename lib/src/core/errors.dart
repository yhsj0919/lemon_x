/// Base class for typed LemonX usage errors.
class LxError extends Error {
  LxError(this.message);
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// Thrown when a dependency cannot be found in the current scope chain.
class LxNotFoundError extends LxError {
  LxNotFoundError(super.message);
}

/// Thrown when a registration conflicts with an existing registration.
class LxAlreadyRegisteredError extends LxError {
  LxAlreadyRegisteredError(super.message);
}

/// Thrown when a reactive or dependency graph contains a cycle.
class LxCircularDependencyError extends LxError {
  LxCircularDependencyError(super.message);
}

/// Thrown when an operation targets an object that has been disposed.
class LxDisposedError extends LxError {
  LxDisposedError(super.message);
}

/// Thrown when reactive state is mutated from a read-only collection phase.
class LxInvalidMutationError extends LxError {
  LxInvalidMutationError(super.message);
}
