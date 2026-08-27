/// Exception thrown by every operation of this package when a request cannot be
/// completed (network error, protocol error, invalid server reply, ...).
class FTPConnectException implements Exception {
  /// A human readable description of what went wrong.
  final String message;

  /// The raw server response (when available) that caused the failure.
  final String? response;

  /// The original error that triggered this exception (when this exception
  /// wraps a lower-level failure, e.g. a socket or SSH error).
  ///
  /// Kept as the original object (rather than flattened to a `String`) so
  /// callers can inspect its runtime type, and so the original error/stack
  /// trace is not lost.
  final Object? cause;

  const FTPConnectException(this.message, [this.response, this.cause]);

  @override
  String toString() {
    final StringBuffer buffer = StringBuffer('FTPConnectException: $message');
    if (response != null) buffer.write(' (Response: $response)');
    if (cause != null) buffer.write(' (Caused by: $cause)');
    return buffer.toString();
  }
}
