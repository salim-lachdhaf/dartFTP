import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../common/ftp_entry.dart';
import '../../common/ftp_enums.dart';
import '../../common/ftp_exceptions.dart';
import '../ftp_reply.dart';
import '../ftp_socket.dart';

class FTPDirectory {
  final FTPSocket _socket;

  FTPDirectory(this._socket);

  Future<bool> makeDirectory(String sName) async {
    FTPReply sResponse = await (_socket.sendCommand('MKD $sName'));

    return sResponse.isSuccessCode();
  }

  Future<bool> deleteEmptyDirectory(String? sName) async {
    FTPReply sResponse = await (_socket.sendCommand('RMD $sName'));

    return sResponse.isSuccessCode();
  }

  Future<bool> changeDirectory(String? sName) async {
    FTPReply sResponse = await (_socket.sendCommand('CWD $sName'));

    return sResponse.isSuccessCode();
  }

  Future<String> currentDirectory() async {
    FTPReply sResponse = await _socket.sendCommand('PWD');
    if (!sResponse.isSuccessCode()) {
      throw FTPConnectException(
          'Failed to get current working directory', sResponse.message);
    }

    int iStart = sResponse.message.indexOf('"') + 1;
    int iEnd = sResponse.message.lastIndexOf('"');

    return sResponse.message.substring(iStart, iEnd);
  }

  Future<List<FTPEntry>> directoryContent([String? sDirectory]) async {
    final String listCommand = _socket.listCommand.describeEnum;
    final String command =
        sDirectory == null ? listCommand : '$listCommand $sDirectory';

    final List<int> lstDirectoryListing =
        await _socket.transferData(command, (Socket dataSocket) async {
      final List<int> data = [];
      await dataSocket.listen((Uint8List chunk) {
        data.addAll(chunk);
      }).asFuture();
      return data;
    });

    // Convert the listing response into FTPEntry objects.
    List<FTPEntry> lstFTPEntries = <FTPEntry>[];
    utf8.decode(lstDirectoryListing).split('\n').forEach((line) {
      if (line.trim().isNotEmpty) {
        lstFTPEntries.add(
          FTPEntry.parse(line.replaceAll('\r', ""), _socket.listCommand),
        );
      }
    });

    return lstFTPEntries;
  }
}
