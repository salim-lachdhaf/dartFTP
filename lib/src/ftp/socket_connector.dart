import 'dart:typed_data';

import '../domain/enums.dart';

/// A duplex byte connection used by the FTP client for both the control channel
/// and the data channels.
///
/// This is the abstraction that makes the FTP client testable: the real
/// implementation wraps a `dart:io` socket, while tests provide an in-memory
/// fake that speaks the FTP protocol.
abstract class RawSocketConnection {
  /// A broadcast stream of the bytes received from the peer.
  Stream<Uint8List> get inbound;

  /// Write [data] to the peer.
  void add(List<int> data);

  /// Flush any buffered outgoing data.
  Future<void> flush();

  /// Upgrade this connection to TLS (used for the FTPES `AUTH TLS` handshake).
  ///
  /// Returns the secured connection (which may be a new instance).
  Future<RawSocketConnection> secure();

  /// Gracefully close the connection.
  Future<void> close();

  /// Forcibly destroy the connection, releasing its resources immediately.
  void destroy();
}

/// Creates [RawSocketConnection]s for the FTP client.
///
/// The control connection and every data connection are obtained through this
/// factory, so injecting a fake connector replaces all network I/O.
abstract class SocketConnector {
  /// Open a connection to [host]:[port].
  ///
  /// When [secure] is `true` the connection is negotiated over TLS from the
  /// start (FTPS / secured data channels).
  Future<RawSocketConnection> connect(
    String host,
    int port, {
    required bool secure,
    required Duration timeout,
  });
}

/// Convenience helper mapping a [SecurityType] to whether the initial control
/// connection must start secured.
bool controlStartsSecure(SecurityType type) => type == SecurityType.ftps;

/// Convenience helper mapping a [SecurityType] to whether data channels must be
/// secured (true for both FTPS and FTPES once `PROT P` is negotiated).
bool dataIsSecure(SecurityType type) => type != SecurityType.ftp;
