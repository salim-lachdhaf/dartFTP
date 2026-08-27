/// Minimal logger used by the package to emit debug information.
///
/// Logging is disabled by default. Provide a subclass to redirect the output
/// (e.g. to a file or a UI) by overriding [write].
class Logger {
  /// Whether log messages are emitted.
  final bool isEnabled;

  const Logger({this.isEnabled = false});

  /// Logs [message] when logging [isEnabled].
  void log(String message) {
    if (isEnabled) write('[${DateTime.now()}] $message');
  }

  /// Writes an already formatted [message]. Override to customize the sink.
  void write(String message) => print(message);
}
