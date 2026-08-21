/// @docImport "dart:isolate";
library;

/// A class that represents an exception that occurred in a remote task
/// invocation.
///
/// This class is used to wrap exceptions that occur in an isolate invocation,
/// where normal exceptions can't travel across isolate boundaries.
///
/// This is a substitute for the normal [RemoteError] class, which is used for
/// this exact purpose. Other than this, it cannot be caught in a normal
/// try/catch block without linter warnings.
final class RemoteException implements Exception {
  final String _description;
  final StackTrace stackTrace;

  RemoteException(String description, String stackDescription)
    : _description = description,
      stackTrace = StackTrace.fromString(stackDescription);

  @override
  String toString() => _description;
}
