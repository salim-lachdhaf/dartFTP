import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../domain/entities/ftp_entry.dart';
import '../domain/enums.dart';
import '../domain/exceptions.dart';
import '../domain/logger.dart';
import '../sftp/sftp_adapter.dart';

/// Default [SftpConnector] backed by the `dartssh2` package.
class Dartssh2SftpConnector implements SftpConnector {
  const Dartssh2SftpConnector();

  @override
  Future<SftpAdapter> connect(SftpConnectionConfig config) async {
    final SSHSocket socket;
    try {
      socket = await SSHSocket.connect(config.host, config.port,
          timeout: config.timeout);
    } catch (e) {
      throw FTPConnectException(
          'Could not connect to ${config.host} (${config.port})',
          e.toString(),
          e);
    }

    SSHClient? client;
    try {
      client = SSHClient(
        socket,
        username: config.user,
        onVerifyHostKey: config.onVerifyHostKey,
        onPasswordRequest: config.privateKey == null ? () => config.pass : null,
        identities: config.privateKey != null
            ? SSHKeyPair.fromPem(config.privateKey!, config.passphrase)
            : null,
        handshakeTimeout: config.timeout,
        authTimeout: config.timeout,
      );
      await client.authenticated;
      final SftpClient sftp = await client.sftp();
      return _Dartssh2SftpAdapter(client, sftp, config.logger);
    } catch (e) {
      // Avoid leaking the socket/SSH session on a failed handshake, auth or
      // SFTP-channel setup: SSHClient.close() also tears down the socket it
      // wraps, so only fall back to closing the raw socket when the client
      // itself was never constructed.
      if (client != null) {
        unawaited(client.close().catchError((_) {}));
      } else {
        socket.destroy();
      }
      throw FTPConnectException(
          'Could not open the SFTP session', e.toString(), e);
    }
  }
}

class _Dartssh2SftpAdapter implements SftpAdapter {
  final SSHClient _client;
  final SftpClient _sftp;
  final Logger _logger;

  _Dartssh2SftpAdapter(this._client, this._sftp, this._logger);

  @override
  Future<SftpFileStat> stat(String path) async {
    final SftpFileAttrs attrs = await _sftp.stat(path);
    return SftpFileStat(
      isDirectory: attrs.isDirectory,
      isSymbolicLink: attrs.isSymbolicLink,
      size: attrs.size,
    );
  }

  @override
  Future<List<FTPEntry>> listdir(String path) async {
    final List<SftpName> content = await _sftp.listdir(path);
    return content
        .where((SftpName e) => e.filename != '.' && e.filename != '..')
        .map(_toEntry)
        .toList();
  }

  static FTPEntry _toEntry(SftpName file) {
    final SftpFileAttrs attr = file.attr;
    final FTPEntryType type = attr.isDirectory
        ? FTPEntryType.dir
        : attr.isSymbolicLink
            ? FTPEntryType.link
            : FTPEntryType.file;
    final DateTime? modifyTime = attr.modifyTime != null
        ? DateTime.fromMillisecondsSinceEpoch(attr.modifyTime! * 1000)
        : null;
    final String? mode = attr.mode?.toString();

    return FTPEntry.details(
      name: file.filename,
      type: type,
      modifyTime: modifyTime,
      size: attr.size,
      permission: mode,
      mode: mode,
      gid: attr.groupID,
      uid: attr.userID,
    );
  }

  @override
  Future<void> mkdir(String path) => _sftp.mkdir(path);

  @override
  Future<void> rmdir(String path) => _sftp.rmdir(path);

  @override
  Future<void> remove(String path) => _sftp.remove(path);

  @override
  Future<void> rename(String from, String to) => _sftp.rename(from, to);

  @override
  Future<void> writeFile(
    String path,
    Stream<Uint8List> data, {
    void Function(int totalSent)? onProgress,
  }) async {
    final SftpFile remoteFile = await _sftp.open(
      path,
      mode: SftpFileOpenMode.create |
          SftpFileOpenMode.write |
          SftpFileOpenMode.truncate,
    );
    try {
      final SftpFileWriter writer =
          remoteFile.write(data, onProgress: onProgress);
      await writer.done;
    } finally {
      await remoteFile.close();
    }
  }

  @override
  Stream<Uint8List> readFile(String path) async* {
    final SftpFile remoteFile = await _sftp.open(path);
    try {
      yield* remoteFile.read();
    } finally {
      await remoteFile.close();
    }
  }

  @override
  Future<void> close() async {
    try {
      await _sftp.close();
    } catch (e) {
      _logger.log('Error while closing the SFTP client (ignored): $e');
    }
    unawaited(_client.done.catchError((_) {}));
    try {
      await _client.close();
    } catch (e) {
      _logger.log('Error while closing the SSH client (ignored): $e');
    }
  }
}
