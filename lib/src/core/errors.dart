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

/// Thrown when a caller attempts to remove a dependency owned by another scope.
class LxOwnershipError extends LxError {
  LxOwnershipError(super.message);
}

/// Thrown when a page-owned registration has no active page lifetime.
class LxNoPageScopeError extends LxError {
  LxNoPageScopeError(super.message);
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
