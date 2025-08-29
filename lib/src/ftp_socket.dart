import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '/src/ftp_reply.dart';
import '../ftpconnect.dart';

class FTPSocket {
  final String host;
  final int port;
  final Logger logger;
  final int timeout;
  final SecurityType securityType;
  late RawSocket _socket;
  TransferMode transferMode = TransferMode.passive;
  TransferType _transferType = TransferType.auto;
  ListCommand listCommand = ListCommand.mlsd;
  bool supportIPV6 = false;

  FTPSocket(this.host, this.port, this.securityType, this.logger, this.timeout);

  /// Set current transfer type of socket
  ///
  /// Supported types are: [TransferType.auto], [TransferType.ascii], [TransferType.binary],
  TransferType get transferType => _transferType;

  /// Read the FTP Server response from the Stream
  ///
  /// Blocks until data is received!
  Future<FTPReply> readResponse() async {
    StringBuffer res = StringBuffer();
    await Future.doWhile(() async {
      bool dataReceivedSuccessfully = false;

      //this is used to read all data for specific command line
      while (_socket.available() > 0) {
        res.write(Utf8Codec().decode(_socket.read()!).trim());
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

  /// Send a command [cmd] to the FTP Server
  /// if [waitResponse] the function waits for the reply, other wise return ''
  Future<FTPReply> sendCommand(String cmd) {
    logger.log('> $cmd');
    _socket.write(Utf8Codec().encode('$cmd\r\n'));

    return readResponse();
  }

  /// Send a command [cmd] to the FTP Server
  /// if [waitResponse] the function waits for the reply, other wise return ''
  void sendCommandWithoutWaitingResponse(String cmd) async {
    logger.log('> $cmd');
    _socket.write(Utf8Codec().encode('$cmd\r\n'));
  }

  /// Connect to the FTP Server and Login with [user] and [pass]
  Future<bool> connect(String user, String pass, {String? account}) async {
    logger.log('Connecting...');

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

  /// Set the Transfer mode on [socket] to [mode]
  Future<void> setTransferType(TransferType pTransferType) async {
    //if we already in the same transfer type we do nothing
    if (_transferType == pTransferType) return;
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
    _transferType = pTransferType;
  }

  // Disconnect from the FTP Server
  Future<bool> disconnect() async {
    logger.log('Disconnecting...');

    try {
      await sendCommand('QUIT');
    } catch (ignored) {
      // Ignore
    } finally {
      await _socket.close();
      _socket.shutdown(SocketDirection.both);
    }

    logger.log('Disconnected!');
    return true;
  }
}
