final class RemoteException implements Exception {
  final String _description;
  final StackTrace stackTrace;

  RemoteException(String description, String stackDescription)
    : _description = description,
      stackTrace = StackTrace.fromString(stackDescription);

  @override
  String toString() => _description;
}
