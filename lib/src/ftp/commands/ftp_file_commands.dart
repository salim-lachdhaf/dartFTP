import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart';

import '../../domain/entities/ftp_reply.dart';
import '../../domain/enums.dart';
import '../../domain/exceptions.dart';
import '../../domain/progress.dart';
import '../../utils/utils.dart';
import '../ftp_control_connection.dart';
import '../socket_connector.dart';

/// File-level FTP operations (RETR/STOR/DELE/SIZE/RNFR-RNTO).
class FtpFileCommands {
  final FtpControlConnection _control;

  FtpFileCommands(this._control);

  Future<bool> rename(String sOldName, String sNewName) async {
    FTPReply reply = await _control.sendCommand('RNFR $sOldName');
    if (reply.code != 350) return false;
    reply = await _control.sendCommand('RNTO $sNewName');
    return reply.isSuccessCode();
  }

  Future<bool> delete(String sFilename) async {
    final FTPReply reply = await _control.sendCommand('DELE $sFilename');
    return reply.isSuccessCode();
  }

  Future<bool> exist(String sFilename) async => await size(sFilename) != -1;

  Future<int> size(String sFilename) async {
    try {
      FTPReply reply = await _control.sendCommand('SIZE $sFilename');
      if (!reply.isSuccessCode() &&
          _control.transferType != TransferType.binary) {
        // Some servers reject SIZE in ASCII mode; retry in binary.
        final TransferType backup = _control.transferType;
        await _control.setTransferType(TransferType.binary);
        reply = await _control.sendCommand('SIZE $sFilename');
        await _control.setTransferType(backup);
      }
      if (!reply.isSuccessCode()) return -1;
      return int.parse(reply.message.replaceAll('213 ', '').trim());
    } catch (_) {
      return -1;
    }
  }

  Future<bool> download(
    String sRemoteName,
    File fLocalFile, {
    FileProgress? onProgress,
  }) async {
    _control.logger.log('Download $sRemoteName to ${fLocalFile.path}');
    await fLocalFile.parent.create(recursive: true);
    final IOSink sink = fLocalFile.openWrite(mode: FileMode.writeOnly);
    try {
      await _download(sRemoteName, sink.add, onProgress: onProgress);
    } finally {
      await sink.flush();
      await sink.close();
    }
    _control.logger.log('File Downloaded!');
    return true;
  }

  Future<Uint8List> downloadToBytes(
    String sRemoteName, {
    FileProgress? onProgress,
  }) async {
    _control.logger.log('Download $sRemoteName to memory');
    final BytesBuilder builder = BytesBuilder(copy: false);
    await _download(sRemoteName, builder.add, onProgress: onProgress);
    _control.logger.log('File Downloaded!');
    return builder.takeBytes();
  }

  Future<void> _download(
    String sRemoteName,
    void Function(List<int> chunk) onChunk, {
    FileProgress? onProgress,
  }) async {
    final int fileSize = await size(sRemoteName);
    if (fileSize == -1) {
      throw FTPConnectException('Remote File $sRemoteName does not exist!');
    }

    await _control.transferData('RETR $sRemoteName',
        (RawSocketConnection dataSocket) async {
      _control.logger.log('Start downloading...');
      int received = 0;
      await dataSocket.inbound.listen((chunk) {
        onChunk(chunk);
        if (onProgress != null) {
          received += chunk.length;
          onProgress(Utils.percent(received, fileSize), received, fileSize);
        }
      }).asFuture<void>();
    });
  }

  Future<bool> uploadData(
    Uint8List data,
    String remoteName, {
    FileProgress? onProgress,
  }) {
    _control.logger.log('Upload data to: $remoteName');
    return _upload(
      remoteName,
      data.length,
      Stream<List<int>>.value(data),
      onProgress: onProgress,
    );
  }

  Future<bool> upload(
    File fFile, {
    String? remoteName,
    FileProgress? onProgress,
  }) async {
    _control.logger.log('Upload File: ${fFile.path}');
    final String sFilename = remoteName ?? basename(fFile.path);
    return _upload(
      sFilename,
      await fFile.length(),
      fFile.openRead(),
      onProgress: onProgress,
    );
  }

  Future<bool> _upload(
    String remoteName,
    int fileSize,
    Stream<List<int>> source, {
    FileProgress? onProgress,
  }) async {
    await _control.transferData('STOR $remoteName',
        (RawSocketConnection dataSocket) async {
      _control.logger.log('Start uploading...');
      int sent = 0;
      await for (final List<int> chunk in source) {
        dataSocket.add(chunk);
        if (onProgress != null) {
          sent += chunk.length;
          onProgress(Utils.percent(sent, fileSize), sent, fileSize);
        }
      }
      await dataSocket.flush();
    });

    _control.logger.log('File Uploaded!');
    return true;
  }
}
