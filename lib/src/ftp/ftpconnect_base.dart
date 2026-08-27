import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart';

import '../common/file_transfer_client.dart';
import '../common/ftp_entry.dart';
import '../common/ftp_enums.dart';
import '../common/ftp_exceptions.dart';
import 'commands/directory.dart';
import 'commands/file.dart';
import 'ftp_reply.dart';
import 'ftp_socket.dart';

class FTPConnect extends FileTransferClient {
  late FTPSocket _socket;
  final bool supportIPV6;
  final ListCommand listCommand;
  final TransferMode transferMode;
  final TransferType transferType;

  /// Create a FTP Client instance
  ///
  /// [host]: Hostname or IP Address
  /// [port]: Port number (Defaults to 21 for FTP and FTPES, 990 for FTPS)
  /// [user]: Username (Defaults to anonymous)
  /// [pass]: Password if not anonymous login
  /// [debug]: Enable Debug Logging
  /// [timeout]: Timeout in seconds to wait for responses
  FTPConnect(
    super.host, {
    int? port,
    super.user,
    super.pass,
    super.showLog,
    SecurityType securityType = SecurityType.ftp,
    super.logger,
    super.timeout,
    this.supportIPV6 = false,
    this.listCommand = ListCommand.mlsd,
    this.transferMode = TransferMode.passive,
    this.transferType = TransferType.auto,
  }) : super(
          port: port ?? (securityType == SecurityType.ftps ? 990 : 21),
        ) {
    _socket = FTPSocket(
      host,
      this.port,
      securityType,
      logger,
      timeout,
      supportIPV6: supportIPV6,
      listCommand: listCommand,
      transferMode: transferMode,
      transferType: transferType,
    );
  }

  /// Set current transfer type of connection
  ///
  /// Supported types are: [TransferType.auto], [TransferType.ascii], [TransferType.binary],
  Future<void> setTransferType(TransferType pTransferType) async {
    if (_socket.transferType == pTransferType) return;
    await _socket.setTransferType(pTransferType);
  }

  /// Connect to the FTP Server
  /// return true if we are connected successfully
  @override
  Future<bool> connect() => _socket.connect(user, pass);

  /// Disconnect from the FTP Server
  /// return true if we are disconnected successfully
  @override
  Future<bool> disconnect() => _socket.disconnect();

  Future<FTPReply> sendCustomCommand(String pCmd) => _socket.sendCommand(pCmd);

  /// Upload the File [fFile] to the current directory
  @override
  Future<bool> uploadFile(
    File fFile, {
    String? sRemoteName,
    FileProgress? onProgress,
  }) {
    return FTPFile(_socket).upload(
      fFile,
      remoteName: sRemoteName,
      onProgress: onProgress,
    );
  }

  /// Download the Remote File [sRemoteName] to the local File [fFile]
  @override
  Future<bool> downloadFile(
    String sRemoteName,
    File fFile, {
    FileProgress? onProgress,
  }) {
    return FTPFile(_socket)
        .download(sRemoteName, fFile, onProgress: onProgress);
  }

  /// Upload the in-memory bytes [data] to the current directory as [sRemoteName]
  @override
  Future<bool> uploadData(
    Uint8List data,
    String sRemoteName, {
    FileProgress? onProgress,
  }) {
    return FTPFile(_socket).uploadData(
      data,
      sRemoteName,
      onProgress: onProgress,
    );
  }

  /// Download the Remote File [sRemoteName] and return its content in memory
  @override
  Future<Uint8List> downloadToBytes(
    String sRemoteName, {
    FileProgress? onProgress,
  }) {
    return FTPFile(_socket)
        .downloadToBytes(sRemoteName, onProgress: onProgress);
  }

  /// Create a new Directory with the Name of [sDirectory] in the current directory.
  ///
  /// Returns `true` if the directory was created successfully
  /// Returns `false` if the directory could not be created or already exists
  @override
  Future<bool> makeDirectory(String sDirectory) {
    return FTPDirectory(_socket).makeDirectory(sDirectory);
  }

  /// Deletes the Directory with the Name of [sDirectory] in the current directory.
  ///
  /// Returns `true` if the directory was deleted successfully
  /// Returns `false` if the directory could not be deleted or does not nexist
  @override
  Future<bool> deleteEmptyDirectory(String sDirectory) {
    return FTPDirectory(_socket).deleteEmptyDirectory(sDirectory);
  }

  /// Deletes the Directory with the Name of [sDirectory] in the current directory.
  ///
  /// Returns `true` if the directory was deleted successfully
  /// Returns `false` if the directory could not be deleted or does not nexist
  /// THIS USEFUL TO DELETE NON EMPTY DIRECTORY
  @override
  Future<bool> deleteDirectory(String sDirectory) async {
    String currentDir = await currentDirectory();
    if (!await changeDirectory(sDirectory)) {
      throw FTPConnectException("Couldn't change directory to $sDirectory");
    }
    List<FTPEntry> dirContent = await listDirectoryContent();
    await Future.forEach(dirContent, (FTPEntry entry) async {
      if (entry.type == FTPEntryType.file) {
        if (!await deleteFile(entry.name)) {
          throw FTPConnectException("Couldn't delete file ${entry.name}");
        }
      } else {
        if (!await deleteDirectory(entry.name)) {
          throw FTPConnectException("Couldn't delete folder ${entry.name}");
        }
      }
    });
    await changeDirectory(currentDir);
    return await deleteEmptyDirectory(sDirectory);
  }

  /// Deletes the Directory [sDirectory] even when it is not empty.
  ///
  /// Removes all of its content recursively then the directory itself.
  /// Returns `false` (instead of throwing) when the directory does not exist
  /// or cannot be removed.
  @override
  Future<bool> deleteNonEmptyDirectory(String sDirectory) async {
    try {
      return await deleteDirectory(sDirectory);
    } catch (e) {
      _socket.logger.log('Cannot delete directory $sDirectory: $e');
      return false;
    }
  }

  /// Change into the Directory with the Name of [sDirectory] within the current directory.
  ///
  /// Use `..` to navigate back
  /// Returns `true` if the directory was changed successfully
  /// Returns `false` if the directory could not be changed (does not exist, no permissions or another error)
  @override
  Future<bool> changeDirectory(String sDirectory) {
    return FTPDirectory(_socket).changeDirectory(sDirectory);
  }

  /// Returns the current directory
  @override
  Future<String> currentDirectory() {
    return FTPDirectory(_socket).currentDirectory();
  }

  /// Returns the content of the current directory
  /// [cmd] refer to the used command for the server, there is servers working
  /// with MLSD and other with LIST
  @override
  Future<List<FTPEntry>> listDirectoryContent([String? sDirectory]) {
    return FTPDirectory(_socket).directoryContent(sDirectory);
  }

  /// Rename a file (or directory) from [sOldName] to [sNewName]
  @override
  Future<bool> rename(String sOldName, String sNewName) {
    return FTPFile(_socket).rename(sOldName, sNewName);
  }

  /// Delete the file [sFilename] from the server
  @override
  Future<bool> deleteFile(String sFilename) {
    return FTPFile(_socket).delete(sFilename);
  }

  /// check the existence of  the file [sFilename] from the server
  @override
  Future<bool> existFile(String sFilename) {
    return FTPFile(_socket).exist(sFilename);
  }

  /// returns the file [sFilename] size from server,
  /// returns -1 if file does not exist
  @override
  Future<int> sizeFile(String sFilename) {
    return FTPFile(_socket).size(sFilename);
  }

  /// Download the Remote Directory [pRemoteDir] to the local File [pLocalDir]
  @override
  Future<bool> downloadDirectory(String pRemoteDir, Directory pLocalDir) {
    Future<bool> downloadDir(String pRemoteDir, Directory pLocalDir) async {
      await pLocalDir.create(recursive: true);

      //read remote directory content
      if (!await changeDirectory(pRemoteDir)) {
        throw FTPConnectException('Cannot download directory',
            '$pRemoteDir not found or inaccessible !');
      }
      List<FTPEntry> dirContent = await listDirectoryContent();
      await Future.forEach(dirContent, (FTPEntry entry) async {
        if (entry.type == FTPEntryType.file) {
          File localFile = File(join(pLocalDir.path, entry.name));
          await downloadFile(entry.name, localFile);
        } else if (entry.type == FTPEntryType.dir) {
          //create a local directory
          var localDir = await Directory(join(pLocalDir.path, entry.name))
              .create(recursive: true);
          await downloadDir(entry.name, localDir);
          //back to current folder
          await changeDirectory('..');
        }
      });
      return true;
    }

    return downloadDir(pRemoteDir, pLocalDir);
  }

  /// Upload the local Directory [pLocalDir] recursively into the remote
  /// directory [pRemoteDir] (created if it does not exist).
  @override
  Future<bool> uploadDirectory(
    Directory pLocalDir,
    String pRemoteDir, {
    FileProgress? onProgress,
  }) async {
    Future<bool> uploadDir(Directory localDir, String remoteDir) async {
      final String currentDir = await currentDirectory();
      if (!await createFolderIfNotExist(remoteDir)) {
        throw FTPConnectException(
            'Cannot upload directory', 'Could not create remote $remoteDir');
      }
      if (!await changeDirectory(remoteDir)) {
        throw FTPConnectException('Cannot upload directory',
            '$remoteDir not found or inaccessible !');
      }

      final List<FileSystemEntity> entities = localDir.listSync();
      for (final FileSystemEntity entity in entities) {
        final String name = basename(entity.path);
        if (entity is File) {
          await uploadFile(entity, sRemoteName: name, onProgress: onProgress);
        } else if (entity is Directory) {
          await uploadDir(entity, name);
        }
      }

      await changeDirectory(currentDir);
      return true;
    }

    return uploadDir(pLocalDir, pRemoteDir);
  }

  /// check the existence of the Directory with the Name of [pDirectory].
  ///
  /// Returns `true` if the directory was changed successfully
  /// Returns `false` if the directory could not be changed (does not exist, no permissions or another error)
  @override
  Future<bool> checkFolderExistence(String pDirectory) {
    return changeDirectory(pDirectory);
  }

  /// Create a new Directory with the Name of [pDirectory] in the current directory if it does not exist.
  ///
  /// Returns `true` if the directory exists or was created successfully
  /// Returns `false` if the directory not found and could not be created
  @override
  Future<bool> createFolderIfNotExist(String pDirectory) async {
    if (!await checkFolderExistence(pDirectory)) {
      return makeDirectory(pDirectory);
    }
    return true;
  }
}
