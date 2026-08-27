import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart';

import '../../common/file_transfer_client.dart';
import '../../common/ftp_enums.dart';
import '../../common/ftp_exceptions.dart';
import '../../common/utils.dart';
import '../ftp_reply.dart';
import '../ftp_socket.dart';

class FTPFile {
  final FTPSocket _socket;

  FTPFile(this._socket);

  Future<bool> rename(String sOldName, String sNewName) async {
    FTPReply sResponse = await (_socket.sendCommand('RNFR $sOldName'));
    if (sResponse.code != 350) {
      return false;
    }

    sResponse = await (_socket.sendCommand('RNTO $sNewName'));
    return sResponse.isSuccessCode();
  }

  Future<bool> delete(String? sFilename) async {
    FTPReply sResponse = await (_socket.sendCommand('DELE $sFilename'));

    return sResponse.isSuccessCode();
  }

  Future<bool> exist(String sFilename) async {
    return await size(sFilename) != -1;
  }

  Future<int> size(String? sFilename) async {
    try {
      FTPReply sResponse = await (_socket.sendCommand('SIZE $sFilename'));
      if (!sResponse.isSuccessCode() &&
          _socket.transferType != TransferType.binary) {
        //check if ascii mode get refused
        //change to binary mode if ascii mode refused
        final socketTransferTypeBackup = _socket.transferType;
        await _socket.setTransferType(TransferType.binary);
        sResponse = await (_socket.sendCommand('SIZE $sFilename'));
        //back to default mode
        await _socket.setTransferType(socketTransferTypeBackup);
      }
      return int.parse(sResponse.message.replaceAll('213 ', ''));
    } catch (e) {
      return -1;
    }
  }

  Future<bool> download(
    String? sRemoteName,
    File fLocalFile, {
    FileProgress? onProgress,
  }) async {
    _socket.logger.log('Download $sRemoteName to ${fLocalFile.path}');
    await fLocalFile.parent.create(recursive: true);
    final IOSink sink = fLocalFile.openWrite(mode: FileMode.writeOnly);
    try {
      await _download(sRemoteName, sink.add, onProgress: onProgress);
    } finally {
      await sink.flush();
      await sink.close();
    }
    _socket.logger.log('File Downloaded!');
    return true;
  }

  /// Download the remote file [sRemoteName] and return its content in memory.
  Future<Uint8List> downloadToBytes(
    String? sRemoteName, {
    FileProgress? onProgress,
  }) async {
    _socket.logger.log('Download $sRemoteName to memory');
    final BytesBuilder builder = BytesBuilder(copy: false);
    await _download(sRemoteName, builder.add, onProgress: onProgress);
    _socket.logger.log('File Downloaded!');
    return builder.takeBytes();
  }

  /// Streams the remote file [sRemoteName] over a RETR data connection, handing
  /// each chunk to [onChunk] and reporting progress. Shared by [download] and
  /// [downloadToBytes] so file-based and in-memory downloads use the exact same
  /// path (and both stay streamed instead of buffering the whole payload).
  Future<void> _download(
    String? sRemoteName,
    void Function(List<int> chunk) onChunk, {
    FileProgress? onProgress,
  }) async {
    //check for file existence and init totalData to receive
    final int fileSize = await size(sRemoteName);
    if (fileSize == -1) {
      throw FTPConnectException('Remote File $sRemoteName does not exist!');
    }

    await _socket.transferData('RETR $sRemoteName', (Socket dataSocket) async {
      // Listen mode is used so we can report the downloaded amount back.
      _socket.logger.log('Start downloading...');
      var received = 0;
      await dataSocket.listen((data) {
        onChunk(data);
        if (onProgress != null) {
          received += data.length;
          onProgress(Utils.percent(received, fileSize), received, fileSize);
        }
      }).asFuture();
    });
  }

  /// Upload the in-memory bytes [data] to the current directory as [remoteName].
  Future<bool> uploadData(
    Uint8List data,
    String remoteName, {
    FileProgress? onProgress,
  }) {
    _socket.logger.log('Upload data to: $remoteName');
    return _upload(
      remoteName,
      data.length,
      Stream<List<int>>.value(data),
      onProgress: onProgress,
    );
  }

  /// Upload File [fFile] to the current directory with [remoteName] (using filename if not set)
  Future<bool> upload(
    File fFile, {
    String? remoteName,
    FileProgress? onProgress,
  }) async {
    _socket.logger.log('Upload File: ${fFile.path}');
    final String sFilename = remoteName ?? basename(fFile.path);
    return _upload(
      sFilename,
      await fFile.length(),
      fFile.openRead(),
      onProgress: onProgress,
    );
  }

  /// Streams [source] ([fileSize] bytes) to the remote file [remoteName] over a
  /// STOR data connection, reporting progress. Shared by [upload] and
  /// [uploadData] so file-based and in-memory uploads use the exact same path.
  Future<bool> _upload(
    String remoteName,
    int fileSize,
    Stream<List<int>> source, {
    FileProgress? onProgress,
  }) async {
    await _socket.transferData('STOR $remoteName', (Socket dataSocket) async {
      _socket.logger.log('Start uploading...');
      var sent = 0;

      final Stream<List<int>> readStream = source.transform(
        StreamTransformer.fromHandlers(
          handleData: (chunk, sink) {
            sink.add(chunk);
            if (onProgress != null) {
              sent += chunk.length;
              onProgress(Utils.percent(sent, fileSize), sent, fileSize);
            }
          },
        ),
      );

      await dataSocket.addStream(readStream);
      await dataSocket.flush();
    });

    _socket.logger.log('File Uploaded!');
    return true;
  }
}
