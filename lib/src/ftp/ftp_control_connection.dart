import 'dart:async';
import 'dart:convert';

import '../domain/entities/ftp_reply.dart';
import '../domain/enums.dart';
import '../domain/exceptions.dart';
import '../domain/logger.dart';
import '../utils/utils.dart';
import 'ftp_response_reader.dart';
import 'socket_connector.dart';

/// Owns the FTP control channel: it connects, authenticates, sends commands,
/// reads replies and drives passive-mode data transfers.
///
/// All network access goes through the injected [SocketConnector], which is what
/// makes the whole FTP client testable.
class FtpControlConnection {
  final SocketConnector connector;
  final String host;
  final int port;
  final SecurityType securityType;
  final Logger logger;
  final Duration timeout;
  final bool supportIPV6;
  final TransferMode transferMode;
  final ListCommand listCommand;

  TransferType transferType;

  RawSocketConnection? _control;
  FtpResponseReader? _reader;

  FtpControlConnection({
    required this.connector,
    required this.host,
    required this.port,
    required this.securityType,
    required this.logger,
    required this.timeout,
    this.supportIPV6 = false,
    this.transferMode = TransferMode.passive,
    this.listCommand = ListCommand.mlsd,
    this.transferType = TransferType.auto,
  });

  RawSocketConnection get _controlOrThrow {
    final RawSocketConnection? control = _control;
    if (control == null) {
      throw const FTPConnectException('Not connected. Call connect() first.');
    }
    return control;
  }

  /// Reads the next reply from the control connection.
  Future<FTPReply> readResponse() => _reader!.readReply();

  /// Sends [cmd] to the server.
  ///
  /// When [shouldWait] is `true` (default) it waits for and returns the reply.
  /// When `false` it only writes the command (used for data-transfer commands
  /// whose reply is read later) and resolves to an empty [FTPReply].
  Future<FTPReply> sendCommand(String cmd, {bool shouldWait = true}) {
    _logCommand(cmd);
    _controlOrThrow.add(utf8.encode('$cmd\r\n'));
    if (!shouldWait) return Future.value(const FTPReply(0, ''));
    return readResponse();
  }

  void _logCommand(String cmd) {
    final String keyword = cmd.split(' ').first.toUpperCase();
    if (keyword == 'PASS' || keyword == 'USER' || keyword == 'ACCT') {
      logger.log('> $keyword ******');
    } else {
      logger.log('> $cmd');
    }
  }

  /// Connect to the FTP server and log in with [user] / [pass].
  Future<bool> connect(String user, String pass, {String? account}) async {
    logger.log('Connecting...');

    // A fresh control connection resets the server to its default (ASCII)
    // transfer type, so drop any cached value to force it to be re-sent.
    transferType = TransferType.auto;

    try {
      _control = await connector.connect(
        host,
        port,
        secure: controlStartsSecure(securityType),
        timeout: timeout,
      );
    } catch (e) {
      throw FTPConnectException(
          'Could not connect to $host ($port)', e.toString(), e);
    }
    _reader = FtpResponseReader(_control!, logger, timeout);

    try {
      logger.log('Connection established, waiting for welcome message...');
      await readResponse();

      // FTPES upgrades an initially plain connection to TLS.
      if (securityType == SecurityType.ftpes) {
        FTPReply reply = await sendCommand('AUTH TLS');
        if (!reply.isSuccessCode()) {
          reply = await sendCommand('AUTH SSL');
          if (!reply.isSuccessCode()) {
            throw FTPConnectException(
                'FTPES cannot be applied: the server refused both AUTH TLS '
                'and AUTH SSL commands',
                reply.message);
          }
        }
        _control = await _controlOrThrow.secure();
        await _reader!.dispose();
        _reader = FtpResponseReader(_control!, logger, timeout);
      }

      if (securityType != SecurityType.ftp) {
        await sendCommand('PBSZ 0');
        await sendCommand('PROT P');
      }

      await _login(user, pass, account);
    } catch (e) {
      // Don't leak the control socket when the welcome message, TLS
      // handshake or login fails partway through: tear it down so a caller
      // that retries connect() doesn't pile up dangling sockets.
      await _teardown();
      rethrow;
    }

    logger.log('Connected!');
    return true;
  }

  Future<void> _teardown() async {
    try {
      await _reader?.dispose();
      await _control?.close();
    } catch (e) {
      logger.log('Error while tearing down the socket (ignored): $e');
    }
    _control = null;
    _reader = null;
  }

  Future<void> _login(String user, String pass, String? account) async {
    FTPReply reply = await sendCommand('USER $user');

    if (reply.code == 331) {
      reply = await sendCommand('PASS $pass');
      if (reply.code == 332) {
        await _account(account);
      } else if (!reply.isSuccessCode()) {
        throw FTPConnectException('Wrong Username/password', reply.message);
      }
    } else if (reply.code == 332) {
      await _account(account);
    } else if (!reply.isSuccessCode()) {
      throw FTPConnectException('Wrong username $user', reply.message);
    }
  }

  Future<void> _account(String? account) async {
    if (account == null) throw const FTPConnectException('Account required');
    final FTPReply reply = await sendCommand('ACCT $account');
    if (!reply.isSuccessCode()) {
      throw FTPConnectException('Wrong Account', reply.message);
    }
  }

  /// Enters passive mode, returning the corresponding reply.
  Future<FTPReply> _openPassiveMode() async {
    if (transferMode == TransferMode.active) {
      throw const FTPConnectException('Active transfer mode is not supported');
    }
    final FTPReply reply = await sendCommand(supportIPV6 ? 'EPSV' : 'PASV');
    if (!reply.isSuccessCode()) {
      throw FTPConnectException('Could not start Passive Mode', reply.message);
    }
    return reply;
  }

  Future<RawSocketConnection> _connectDataSocket(
      String dataHost, int dataPort) {
    return connector
        .connect(
      dataHost,
      dataPort,
      secure: dataIsSecure(securityType),
      timeout: timeout,
    )
        .timeout(timeout, onTimeout: () {
      throw FTPConnectException(
          'Timeout reached while opening the data connection to '
          '$dataHost:$dataPort !');
    });
  }

  /// Runs a passive-mode data transfer for [command].
  ///
  /// It opens the data socket before issuing [command] (so servers that build
  /// the data connection eagerly don't fail with `425`), validates the
  /// preliminary reply, invokes [onData] with the connected data socket and
  /// finally validates the completion reply. The data socket is always destroyed
  /// once [onData] completes or throws.
  Future<T> transferData<T>(
    String command,
    Future<T> Function(RawSocketConnection dataSocket) onData,
  ) async {
    FTPReply response = await _openPassiveMode();

    final int dataPort = Utils.parsePort(response.message, supportIPV6);
    final String dataHost =
        (!supportIPV6 ? Utils.parseHostPASV(response.message) : null) ?? host;
    logger.log('Opening DataSocket to $dataHost:$dataPort');
    final RawSocketConnection dataSocket =
        await _connectDataSocket(dataHost, dataPort);

    // The command reply is read here; the payload flows over [dataSocket].
    await sendCommand(command, shouldWait: false);

    response = await readResponse();
    final bool isTransferCompleted = response.isSuccessCode();
    if (!isTransferCompleted && response.code != 125 && response.code != 150) {
      dataSocket.destroy();
      throw FTPConnectException('Connection refused. ', response.message);
    }

    final T result;
    try {
      result = await onData(dataSocket);
    } finally {
      dataSocket.destroy();
    }

    if (!isTransferCompleted) {
      response = await readResponse();
      if (!response.isSuccessCode()) {
        throw FTPConnectException('Transfer Error.', response.message);
      }
    }

    return result;
  }

  /// Set the transfer representation to [pTransferType].
  Future<void> setTransferType(TransferType pTransferType) async {
    if (transferType == pTransferType) return;
    switch (pTransferType) {
      case TransferType.auto:
      case TransferType.ascii:
        await sendCommand('TYPE A');
        break;
      case TransferType.binary:
        await sendCommand('TYPE I');
        break;
    }
    transferType = pTransferType;
  }

  /// Disconnect from the FTP server.
  Future<bool> disconnect() async {
    logger.log('Disconnecting...');
    try {
      await sendCommand('QUIT');
    } catch (e) {
      logger.log('QUIT command failed (ignored): $e');
    } finally {
      await _teardown();
    }
    logger.log('Disconnected!');
    return true;
  }
}
