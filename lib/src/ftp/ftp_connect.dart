import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart';
import 'package:path/path.dart' as p;

import '../config/transfer_config.dart';
import '../domain/entities/ftp_entry.dart';
import '../domain/entities/ftp_reply.dart';
import '../domain/enums.dart';
import '../domain/exceptions.dart';
import '../domain/file_transfer_client.dart';
import '../domain/logger.dart';
import '../domain/progress.dart';
import '../infrastructure/io_socket_connector.dart';
import 'commands/ftp_directory_commands.dart';
import 'commands/ftp_file_commands.dart';
import 'ftp_control_connection.dart';
import 'socket_connector.dart';

/// A robust FTP / FTPS / FTPES client.
///
/// The network layer is injected through a [SocketConnector], which defaults to
/// a `dart:io` implementation. Tests provide an in-memory connector to drive the
/// real client without a live server.
///
/// The FTP protocol is a single command/single reply exchange over one control
/// connection: it has no pipelining and a real, stateful current working
/// directory on the server. Because of this, **a single [FTPConnect] instance
/// must not be used to run overlapping operations concurrently** (e.g. two
/// `Future`s awaited together): interleaved commands would desynchronize
/// command/reply matching and directory navigation regardless of what the
/// client library does internally. Await each call in turn, or use one
/// [FTPConnect] instance (and connection) per concurrent task.
///
/// None of `deleteNonEmptyDirectory`, `uploadDirectory` and
/// `downloadDirectory` navigate (`changeDirectory`) at all: they address
/// every entry by its full path, so the connection's current working
/// directory is never touched by them. `checkFolderExistence` (and
/// `createFolderIfNotExist`, which relies on it) is the one exception: it
/// does navigate internally (see its doc comment), but always restores the
/// previous working directory before returning.
class FTPConnect implements FileTransferClient {
  final String host;
  final int port;
  final String user;
  final String pass;
  final int timeout;
  final Logger logger;
  final bool supportIPV6;
  final ListCommand listCommand;
  final TransferMode transferMode;
  final TransferType transferType;
  final SecurityType securityType;

  late final FtpControlConnection _control;

  /// Create a FTP client instance.
  ///
  /// [host]: Hostname or IP Address
  /// [port]: Port number (defaults to 21 for FTP/FTPES, 990 for FTPS)
  /// [user]: Username (defaults to anonymous)
  /// [pass]: Password if not anonymous login
  /// [showLog]: Enable debug logging
  /// [timeout]: Timeout in seconds to wait for responses
  /// [connector]: Injectable network layer (defaults to `dart:io`)
  FTPConnect(
    this.host, {
    int? port,
    this.user = 'anonymous',
    this.pass = '',
    bool showLog = false,
    this.securityType = SecurityType.ftp,
    Logger? logger,
    this.timeout = 30,
    this.supportIPV6 = false,
    this.listCommand = ListCommand.mlsd,
    this.transferMode = TransferMode.passive,
    this.transferType = TransferType.auto,
    SocketConnector? connector,
  })  : port = port ?? (securityType == SecurityType.ftps ? 990 : 21),
        logger = logger ?? Logger(isEnabled: showLog) {
    _control = FtpControlConnection(
      connector: connector ?? const IOSocketConnector(),
      host: host,
      port: this.port,
      securityType: securityType,
      logger: this.logger,
      timeout: Duration(seconds: timeout),
      supportIPV6: supportIPV6,
      transferMode: transferMode,
      listCommand: listCommand,
      transferType: transferType,
    );
  }

  /// Create a FTP client from an [FtpConfig].
  ///
  /// Returns a fully-typed [FTPConnect] (implementing [FileTransferClient]), so
  /// the `dart:io` `File`/`Directory` helpers (`uploadFile`, `downloadFile`,
  /// `uploadDirectory`, `downloadDirectory`) remain available.
  factory FTPConnect.fromConfig(FtpConfig config) => FTPConnect(
        config.host,
        port: config.port,
        user: config.user,
        pass: config.pass,
        showLog: config.showLog,
        logger: config.logger,
        timeout: config.timeout,
        securityType: config.securityType,
        supportIPV6: config.supportIPV6,
        listCommand: config.listCommand,
        transferMode: config.transferMode,
        transferType: config.transferType,
      );

  FtpFileCommands get _file => FtpFileCommands(_control);

  FtpDirectoryCommands get _directory => FtpDirectoryCommands(_control);

  /// Set the current transfer type of the connection.
  Future<void> setTransferType(TransferType pTransferType) =>
      _control.setTransferType(pTransferType);

  /// Send a raw FTP command and return the reply.
  Future<FTPReply> sendCustomCommand(String pCmd) => _control.sendCommand(pCmd);

  @override
  Future<bool> connect() => _control.connect(user, pass);

  @override
  Future<bool> disconnect() => _control.disconnect();

  @override
  Future<bool> uploadFile(
    File fFile, {
    String? sRemoteName,
    FileProgress? onProgress,
  }) {
    return _file.upload(fFile, remoteName: sRemoteName, onProgress: onProgress);
  }

  @override
  Future<bool> downloadFile(
    String sRemoteName,
    File fFile, {
    FileProgress? onProgress,
  }) {
    return _file.download(sRemoteName, fFile, onProgress: onProgress);
  }

  @override
  Future<bool> uploadData(
    Uint8List data,
    String sRemoteName, {
    FileProgress? onProgress,
  }) {
    return _file.uploadData(data, sRemoteName, onProgress: onProgress);
  }

  @override
  Future<Uint8List> downloadToBytes(
    String sRemoteName, {
    FileProgress? onProgress,
  }) {
    return _file.downloadToBytes(sRemoteName, onProgress: onProgress);
  }

  @override
  Future<bool> makeDirectory(String sDirectory) =>
      _directory.makeDirectory(sDirectory);

  @override
  Future<bool> deleteDirectory(String sDirectory) =>
      _directory.deleteDirectory(sDirectory);

  @override
  Future<bool> deleteNonEmptyDirectory(String sDirectory) async {
    try {
      return await _deleteNonEmptyDirectory(sDirectory);
    } catch (e) {
      logger.log('Cannot delete directory $sDirectory: $e');
      return false;
    }
  }

  /// Recursively deletes [sDirectory] and its content by addressing every
  /// entry through its full path (`p.posix.join`), never navigating
  /// (`changeDirectory`) into it, so the connection's current working
  /// directory is left untouched throughout the whole recursion.
  Future<bool> _deleteNonEmptyDirectory(String sDirectory) async {
    final List<FTPEntry> dirContent = await listDirectoryContent(sDirectory);
    for (final FTPEntry entry in dirContent) {
      final String childPath = p.posix.join(sDirectory, entry.name);
      if (await _isDirectoryEntry(entry, childPath)) {
        if (!await _deleteNonEmptyDirectory(childPath)) {
          throw FTPConnectException("Couldn't delete folder ${entry.name}");
        }
      } else {
        if (!await deleteFile(childPath)) {
          throw FTPConnectException("Couldn't delete file ${entry.name}");
        }
      }
    }
    return deleteDirectory(sDirectory);
  }

  /// Whether [entry] (found at [childPath]) is a directory.
  ///
  /// [ListCommand.mlsd] and [ListCommand.list] both report a reliable
  /// [FTPEntry.type]. [ListCommand.nlst] only returns bare names, so every
  /// entry comes back as [FTPEntryType.unknown]; in that case this probes
  /// with `SIZE` (via [existFile]) since most servers reject `SIZE` for a
  /// directory, so a missing size is treated as "it's a directory".
  Future<bool> _isDirectoryEntry(FTPEntry entry, String childPath) async {
    switch (entry.type) {
      case FTPEntryType.dir:
        return true;
      case FTPEntryType.file:
      case FTPEntryType.link:
        return false;
      case FTPEntryType.unknown:
        return !await existFile(childPath);
    }
  }

  @override
  Future<bool> changeDirectory(String sDirectory) =>
      _directory.changeDirectory(sDirectory);

  @override
  Future<String> currentDirectory() => _directory.currentDirectory();

  @override
  Future<List<FTPEntry>> listDirectoryContent([String? sDirectory]) =>
      _directory.directoryContent(sDirectory);

  @override
  Future<bool> rename(String sOldName, String sNewName) =>
      _file.rename(sOldName, sNewName);

  @override
  Future<bool> deleteFile(String sFilename) => _file.delete(sFilename);

  @override
  Future<bool> existFile(String sFilename) => _file.exist(sFilename);

  @override
  Future<int> sizeFile(String sFilename) => _file.size(sFilename);

  @override
  Future<bool> downloadDirectory(String pRemoteDir, Directory pLocalDir) {
    Future<bool> downloadDir(String remoteDir, Directory localDir) async {
      await localDir.create(recursive: true);
      final List<FTPEntry> dirContent = await listDirectoryContent(remoteDir);
      for (final FTPEntry entry in dirContent) {
        final String childRemotePath = p.posix.join(remoteDir, entry.name);
        if (await _isDirectoryEntry(entry, childRemotePath)) {
          final Directory child =
              await Directory(join(localDir.path, entry.name))
                  .create(recursive: true);
          await downloadDir(childRemotePath, child);
        } else {
          await downloadFile(
              childRemotePath, File(join(localDir.path, entry.name)));
        }
      }
      return true;
    }

    return downloadDir(pRemoteDir, pLocalDir);
  }

  @override
  Future<bool> uploadDirectory(
    Directory pLocalDir,
    String pRemoteDir, {
    FileProgress? onProgress,
  }) {
    Future<bool> uploadDir(Directory localDir, String remoteDir) async {
      if (!await createFolderIfNotExist(remoteDir)) {
        throw FTPConnectException(
            'Cannot upload directory', 'Could not create remote $remoteDir');
      }
      for (final FileSystemEntity entity in localDir.listSync()) {
        final String name = basename(entity.path);
        final String remoteChild = p.posix.join(remoteDir, name);
        if (entity is File) {
          await uploadFile(entity,
              sRemoteName: remoteChild, onProgress: onProgress);
        } else if (entity is Directory) {
          await uploadDir(entity, remoteChild);
        }
      }
      return true;
    }

    return uploadDir(pLocalDir, pRemoteDir);
  }

  /// Checks whether [pDirectory] exists (and is a directory) using `CWD`,
  /// the one FTP command whose semantics are unambiguous and consistent
  /// across servers: it succeeds only for an existing directory and fails
  /// for a missing path or an existing file — unlike listing, which can't
  /// reliably tell "empty directory" from "missing path" (some servers
  /// answer both with a successful, empty listing) and, for
  /// [ListCommand.nlst], can't tell a file from a directory at all.
  ///
  /// This does navigate the connection: it records the current directory
  /// (`PWD`), attempts `CWD` into [pDirectory], and — when that succeeds —
  /// immediately restores the previous directory before returning, so the
  /// connection's working directory is unchanged by the time this call
  /// completes. Throws [FTPConnectException] if restoring the previous
  /// directory unexpectedly fails, rather than silently leaving the
  /// connection pointed somewhere else.
  @override
  Future<bool> checkFolderExistence(String pDirectory) async {
    final String normalized = p.posix.normalize(pDirectory);
    if (normalized == '/' || normalized == '.' || normalized.isEmpty) {
      return true;
    }
    final String previousDirectory = await currentDirectory();
    final bool exists = await changeDirectory(pDirectory);
    if (exists && !await changeDirectory(previousDirectory)) {
      throw FTPConnectException(
          'checkFolderExistence could not restore the previous working '
          'directory',
          previousDirectory);
    }
    return exists;
  }

  @override
  Future<bool> createFolderIfNotExist(String pDirectory) async {
    if (await checkFolderExistence(pDirectory)) return true;
    return makeDirectory(pDirectory);
  }
}
