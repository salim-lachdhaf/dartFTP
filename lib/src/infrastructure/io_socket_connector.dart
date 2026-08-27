import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../ftp/socket_connector.dart';

/// Default [SocketConnector] backed by `dart:io` sockets.
class IOSocketConnector implements SocketConnector {
  const IOSocketConnector();

  @override
  Future<RawSocketConnection> connect(
    String host,
    int port, {
    required bool secure,
    required Duration timeout,
  }) async {
    final Socket socket = secure
        ? await SecureSocket.connect(
            host,
            port,
            timeout: timeout,
            onBadCertificate: (_) => true,
          )
        : await Socket.connect(host, port, timeout: timeout);
    return _IOSocketConnection(socket);
  }
}

/// A [RawSocketConnection] wrapping a `dart:io` [Socket].
///
/// Inbound bytes are re-published through a broadcast controller so the FTP
/// response reader (and, for FTPES, the secured connection) can subscribe
/// independently.
class _IOSocketConnection implements RawSocketConnection {
  Socket _socket;
  late StreamSubscription<Uint8List> _subscription;
  final StreamController<Uint8List> _controller =
      StreamController<Uint8List>.broadcast();

  _IOSocketConnection(this._socket) {
    _subscription = _socket.listen(
      _controller.add,
      onError: _controller.addError,
      onDone: _controller.close,
      cancelOnError: false,
    );
  }

  @override
  Stream<Uint8List> get inbound => _controller.stream;

  @override
  void add(List<int> data) => _socket.add(data);

  @override
  Future<void> flush() => _socket.flush();

  @override
  Future<RawSocketConnection> secure() async {
    // Hand the existing subscription over to SecureSocket so it can take over
    // the raw byte stream for the TLS handshake (FTPES `AUTH TLS`).
    // `SecureSocket.secure` detaches the socket's existing subscription
    // internally, so no handoff argument is required here.
    final SecureSocket secured = await SecureSocket.secure(
      _socket,
      onBadCertificate: (_) => true,
    );
    _socket = secured;
    return _IOSocketConnection(secured);
  }

  @override
  Future<void> close() async {
    try {
      await _subscription.cancel();
    } catch (_) {
      // Ignore
    }
    try {
      await _socket.close();
    } catch (_) {
      // Ignore
    }
    _socket.destroy();
  }

  @override
  void destroy() => _socket.destroy();
}
