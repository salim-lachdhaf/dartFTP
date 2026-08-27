import 'dart:async';
import 'dart:convert';

import '../../domain/entities/ftp_entry.dart';
import '../../domain/entities/ftp_reply.dart';
import '../../domain/enums.dart';
import '../../domain/exceptions.dart';
import '../ftp_control_connection.dart';
import '../socket_connector.dart';

/// Directory-level FTP operations (MKD/RMD/CWD/PWD/LIST-MLSD-NLST).
class FtpDirectoryCommands {
  final FtpControlConnection _control;

  FtpDirectoryCommands(this._control);

  Future<bool> makeDirectory(String sName) async {
    final FTPReply reply = await _control.sendCommand('MKD $sName');
    return reply.isSuccessCode();
  }

  Future<bool> deleteDirectory(String sName) async {
    final FTPReply reply = await _control.sendCommand('RMD $sName');
    return reply.isSuccessCode();
  }

  Future<bool> changeDirectory(String sName) async {
    final FTPReply reply = await _control.sendCommand('CWD $sName');
    return reply.isSuccessCode();
  }

  Future<String> currentDirectory() async {
    final FTPReply reply = await _control.sendCommand('PWD');
    if (!reply.isSuccessCode()) {
      throw FTPConnectException(
          'Failed to get current working directory', reply.message);
    }
    final int iStart = reply.message.indexOf('"') + 1;
    final int iEnd = reply.message.lastIndexOf('"');
    return reply.message.substring(iStart, iEnd);
  }

  Future<List<FTPEntry>> directoryContent([String? sDirectory]) async {
    final String command = sDirectory == null
        ? _control.listCommand.command
        : '${_control.listCommand.command} $sDirectory';

    final List<int> listing = await _control.transferData(command,
        (RawSocketConnection dataSocket) async {
      final List<int> data = <int>[];
      await dataSocket.inbound.listen(data.addAll).asFuture<void>();
      return data;
    });

    final List<FTPEntry> entries = <FTPEntry>[];
    for (final String line in utf8.decode(listing).split('\n')) {
      if (line.trim().isNotEmpty) {
        entries.add(
            FTPEntry.parse(line.replaceAll('\r', ''), _control.listCommand));
      }
    }
    return entries;
  }
}
