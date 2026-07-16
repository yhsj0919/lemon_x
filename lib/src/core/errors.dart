class LxError extends Error {
  LxError(this.message);
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

class LxNotFoundError extends LxError {
  LxNotFoundError(super.message);
}

class LxAlreadyRegisteredError extends LxError {
  LxAlreadyRegisteredError(super.message);
}

class LxCircularDependencyError extends LxError {
  LxCircularDependencyError(super.message);
}

class LxDisposedError extends LxError {
  LxDisposedError(super.message);
}

class LxInvalidMutationError extends LxError {
  LxInvalidMutationError(super.message);
}
