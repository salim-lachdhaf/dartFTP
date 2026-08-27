/// A single reply returned by an FTP server.
///
/// It is composed of a 3-digit status [code] and the associated [message].
class FTPReply {
  final int _code;
  final String _message;

  const FTPReply(this._code, this._message);

  /// The 3-digit FTP status code (e.g. 220, 331, 550).
  int get code => _code;

  /// The textual message returned by the server.
  String get message => _message;

  /// Whether this reply is a positive completion reply (a 2xx code).
  bool isSuccessCode() => _code >= 200 && _code < 300;

  @override
  String toString() => 'FTPReply = [code=$_code, message=$_message]';
}
