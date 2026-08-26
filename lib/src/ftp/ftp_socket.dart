import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../common/ftp_enums.dart';
import '../common/ftp_exceptions.dart';
import '../common/logger.dart';
import '../common/utils.dart';
import 'ftp_reply.dart';

class FTPSocket {
  final String host;
  final int port;
  final Logger logger;
  final int timeout;
  final SecurityType securityType;
  final bool supportIPV6;
  final ListCommand listCommand;
  final TransferMode transferMode;
  TransferType transferType;

  late RawSocket _socket;

  FTPSocket(this.host, this.port, this.securityType, this.logger, this.timeout,
      {this.supportIPV6 = false, this.listCommand = ListCommand.mlsd,
        this.transferMode = TransferMode.passive, this.transferType = TransferType.auto});

  /// Read the FTP Server response from the Stream
  ///
  /// Blocks until data is received!
  Future<FTPReply> readResponse() async {
    StringBuffer res = StringBuffer();
    await Future.doWhile(() async {
      bool dataReceivedSuccessfully = false;

      //this is used to read all data for specific command line
      while (_socket.available() > 0) {
        res.write(utf8.decode(_socket.read()!).trim());
        dataReceivedSuccessfully = true;
      }
      if (dataReceivedSuccessfully) return false;

      await Future.delayed(Duration(milliseconds: 300));
      return true;
    }).timeout(Duration(seconds: timeout), onTimeout: () {
      throw FTPConnectException('Timeout reached for Receiving response !');
    });

    String r = res.toString();
    if (r.startsWith("\n")) r = r.replaceFirst("\n", "");

    if (r.length < 3) throw FTPConnectException("Illegal Reply Exception", r);

    int? code;
    List<String> lines = r.split('\n');
    //get last code
    String? line;
    for (line in lines) {
      if (line.length >= 3) code = int.tryParse(line.substring(0, 3)) ?? code;
    }
    //multiline response
    if (line != null && line.length >= 4 && line[3] == '-') {
      return await readResponse();
    }

    if (code == null) throw FTPConnectException("Illegal Reply Exception", r);

    FTPReply reply = FTPReply(code, r);
    logger.log('< ${reply.toString()}');
    return reply;
  }

  /// Send a command [cmd] to the FTP Server.
  ///
  /// When [shouldWait] is `true` (default) it waits for and returns the server
  /// reply. When `false` it only writes the command — used for data-transfer
  /// commands (RETR/STOR/LIST) whose reply is read later, once the data socket
  /// is ready — and resolves to an empty [FTPReply].
  Future<FTPReply> sendCommand(String cmd, {bool shouldWait = true}) {
    _logCommand(cmd);
    _socket.write(utf8.encode('$cmd\r\n'));
    if (!shouldWait) return Future.value(const FTPReply(0, ''));
    return readResponse();
  }

  /// Logs a command, masking the argument of credential commands
  /// (USER/PASS/ACCT) so that secrets never leak into enabled logs.
  void _logCommand(String cmd) {
    final String keyword = cmd.split(' ').first.toUpperCase();
    if (keyword == 'PASS' || keyword == 'USER' || keyword == 'ACCT') {
      logger.log('> $keyword ******');
    } else {
      logger.log('> $cmd');
    }
  }

  /// Opens the passive-mode data connection to [host]:[port].
  ///
  /// [host] is the address the data connection must target. It is the address
  /// advertised in the `PASV` reply when available (so load-balanced servers
  /// keep the transfer on the same backend that opened the port), otherwise the
  /// control-connection host.
  ///
  /// When the control connection is secured (FTPS/FTPES) the data channel is
  /// negotiated over TLS as well (required after `PROT P`), otherwise servers
  /// reject the transfer with `425 ... TLS session of data connection not
  /// resumed`.
  ///
  /// The [timeout] passed to `Socket.connect`/`SecureSocket.connect` only guards
  /// the initial TCP attempt, *not* the TLS handshake that follows. A whole
  /// extra `.timeout(...)` therefore wraps the call so a stalled handshake (e.g.
  /// a load balancer that accepts the TCP connection but whose backend never
  /// completes TLS) fails fast instead of hanging forever.
  Future<Socket> connectDataSocket(int port) {
    final Duration duration = Duration(seconds: timeout);
    Future<Socket> connect() {
      if (securityType == SecurityType.ftp) {
        return Socket.connect(host, port, timeout: duration);
      }
      return SecureSocket.connect(
        host,
        port,
        timeout: duration,
        onBadCertificate: (certificate) => true,
      );
    }

    return connect().timeout(duration, onTimeout: () {
      throw FTPConnectException(
          'Timeout reached while opening the data connection to $host:$port !');
    });
  }

  /// Connect to the FTP Server and Login with [user] and [pass]
  Future<bool> connect(String user, String pass, {String? account}) async {
    logger.log('Connecting...');

    // A fresh control connection resets the server to its default (ASCII)
    // transfer type, so drop any cached value to force it to be re-sent.
    transferType = TransferType.auto;

    final timeout = Duration(seconds: this.timeout);

    try {
      // FTPS starts secure
      if (securityType == SecurityType.ftps) {
        _socket = await RawSecureSocket.connect(
          host,
          port,
          timeout: timeout,
          onBadCertificate: (certificate) => true,
        );
      } else {
        _socket = await RawSocket.connect(
          host,
          port,
          timeout: timeout,
        );
      }
    } catch (e) {
      throw FTPConnectException(
          'Could not connect to $host ($port)', e.toString());
    }

    logger.log('Connection established, waiting for welcome message...');
    await readResponse();

    // FTPES needs to be upgraded prior to getting a welcome
    if (securityType == SecurityType.ftpes) {
      FTPReply lResp = await sendCommand('AUTH TLS');
      if (!lResp.isSuccessCode()) {
        lResp = await sendCommand('AUTH SSL');
        if (!lResp.isSuccessCode()) {
          throw FTPConnectException(
              'FTPES cannot be applied: the server refused both AUTH TLS and AUTH SSL commands',
              lResp.message);
        }
      }

      _socket = await RawSecureSocket.secure(_socket,
          onBadCertificate: (certificate) => true);
    }

    if ([SecurityType.ftpes, SecurityType.ftps].contains(securityType)) {
      await sendCommand('PBSZ 0');
      await sendCommand('PROT P');
    }

    // Send Username
    FTPReply lResp = await sendCommand('USER $user');

    //password required
    if (lResp.code == 331) {
      lResp = await sendCommand('PASS $pass');
      if (lResp.code == 332) {
        if (account == null) throw FTPConnectException('Account required');
        lResp = await sendCommand('ACCT $account');
        if (!lResp.isSuccessCode()) {
          throw FTPConnectException('Wrong Account', lResp.message);
        }
      } else if (!lResp.isSuccessCode()) {
        throw FTPConnectException('Wrong Username/password', lResp.message);
      }
      //account required
    } else if (lResp.code == 332) {
      if (account == null) throw FTPConnectException('Account required');
      lResp = await sendCommand('ACCT $account');
      if (!lResp.isSuccessCode()) {
        throw FTPConnectException('Wrong Account', lResp.message);
      }
    } else if (!lResp.isSuccessCode()) {
      throw FTPConnectException('Wrong username $user', lResp.message);
    }

    logger.log('Connected!');
    return true;
  }

  Future<FTPReply> openDataTransferChannel() async {
    FTPReply res = FTPReply(200, "");
    if (transferMode == TransferMode.active) {
      //todo later
    } else {
      res = await sendCommand(supportIPV6 ? 'EPSV' : 'PASV');
      if (!res.isSuccessCode()) {
        throw FTPConnectException('Could not start Passive Mode', res.message);
      }
    }

    return res;
  }

  /// Runs a passive-mode data transfer for [command], centralizing the logic
  /// shared by RETR/STOR and the directory listing commands.
  ///
  /// It opens the data socket *before* issuing [command] (so servers that build
  /// the data connection eagerly don't fail with `425`), validates the
  /// preliminary reply, invokes [onData] with the connected data socket and
  /// finally validates the completion reply. The data socket is always
  /// destroyed once [onData] completes or throws.
  Future<T> transferData<T>(
    String command,
    Future<T> Function(Socket dataSocket) onData,
  ) async {
    // Enter passive mode.
    FTPReply response = await openDataTransferChannel();

    // Data transfer socket (established before issuing the command).
    final int port = Utils.parsePort(response.message, supportIPV6);
    logger.log('Opening DataSocket to Port $port');
    final Socket dataSocket = await connectDataSocket(port);

    // The command reply is handled here; the payload flows over [dataSocket].
    sendCommand(command, shouldWait: false);

    // Test if the data connection was accepted.
    response = await readResponse();
    // Some servers return two lines (e.g. 125/150 then 226) when finished.
    final bool isTransferCompleted = response.isSuccessCode();
    if (!isTransferCompleted && response.code != 125 && response.code != 150) {
      throw FTPConnectException('Connection refused. ', response.message);
    }

    final T result;
    try {
      result = await onData(dataSocket);
    } finally {
      dataSocket.destroy();
    }

    if (!isTransferCompleted) {
      // Ensure all data was transferred successfully.
      response = await readResponse();
      if (!response.isSuccessCode()) {
        throw FTPConnectException('Transfer Error.', response.message);
      }
    }

    return result;
  }

  /// Set the Transfer mode on [socket] to [mode]
  Future<void> setTransferType(TransferType pTransferType) async {
    //if we already in the same transfer type we do nothing
    if (transferType == pTransferType) return;
    switch (pTransferType) {
      case TransferType.auto:
        // Set to ASCII mode
        await sendCommand('TYPE A');
        break;
      case TransferType.ascii:
        // Set to ASCII mode
        await sendCommand('TYPE A');
        break;
      case TransferType.binary:
        // Set to BINARY mode
        await sendCommand('TYPE I');
        break;
    }
    transferType = pTransferType;
  }

  // Disconnect from the FTP Server
  Future<bool> disconnect() async {
    logger.log('Disconnecting...');

    try {
      await sendCommand('QUIT');
    } catch (ignored) {
      // Ignore
    } finally {
      try {
        await _socket.close();
        _socket.shutdown(SocketDirection.both);
      } catch (_) {
        // Ignore errors while tearing down the socket
      }
    }

    logger.log('Disconnected!');
    return true;
  }
}
