import 'dart:io';

import 'package:ftpconnect/ftpconnect.dart';
import 'package:path/path.dart';

import 'commands/directory.dart';
import 'commands/file.dart';
import 'ftp_reply.dart';
import 'ftp_socket.dart';
import 'utils.dart';

class FTPConnect {
  final String _user;
  final String _pass;
  late FTPSocket _socket;

  /// Create a FTP Client instance
  ///
  /// [host]: Hostname or IP Address
  /// [port]: Port number (Defaults to 21 for FTP and FTPES, 990 for FTPS)
  /// [user]: Username (Defaults to anonymous)
  /// [pass]: Password if not anonymous login
  /// [debug]: Enable Debug Logging
  /// [timeout]: Timeout in seconds to wait for responses
  FTPConnect(String host,
      {int? port,
      String user = 'anonymous',
      String pass = '',
      bool showLog = false,
      SecurityType securityType = SecurityType.FTP,
      Logger? logger,
      int timeout = 30,
      Duration sendingResponseDelay = const Duration(milliseconds: 300)})
      : _user = user,
        _pass = pass {
    port ??= securityType == SecurityType.FTPS ? 990 : 21;
    _socket = FTPSocket(
      host,
      port,
      securityType,
      logger != null ? logger : Logger(isEnabled: showLog),
      timeout,
      sendingResponseDelay: sendingResponseDelay,
    );
  }

  set transferMode(TransferMode pTransferMode) {
    _socket.transferMode = pTransferMode;
  }

  set listCommand(ListCommand pListCommand) {
    _socket.listCommand = pListCommand;
  }

  set supportIPV6(bool pSupportIPV6) => _socket.supportIPV6 = pSupportIPV6;

  /// Set current transfer type of connection
  ///
  /// Supported types are: [TransferType.auto], [TransferType.ascii], [TransferType.binary],
  Future<void> setTransferType(TransferType pTransferType) async {
    if (_socket.transferType == pTransferType) return;
    await _socket.setTransferType(pTransferType);
  }

  /// Connect to the FTP Server
  /// return true if we are connected successfully
  Future<bool> connect() => _socket.connect(_user, _pass);

  /// Disconnect from the FTP Server
  /// return true if we are disconnected successfully
  Future<bool> disconnect() => _socket.disconnect();

  Future<FTPReply> sendCustomCommand(String pCmd) => _socket.sendCommand(pCmd);

  /// Upload the File [fFile] to the current directory
  Future<bool> uploadFile(
    File fFile, {
    String sRemoteName = '',
    FileProgress? onProgress,
  }) {
    return FTPFile(_socket).upload(
      fFile,
      remoteName: sRemoteName,
      onProgress: onProgress,
    );
  }

  /// Download the Remote File [sRemoteName] to the local File [fFile]
  Future<bool> downloadFile(
    String? sRemoteName,
    File fFile, {
    FileProgress? onProgress,
  }) {
    return FTPFile(_socket)
        .download(sRemoteName, fFile, onProgress: onProgress);
  }

  /// Create a new Directory with the Name of [sDirectory] in the current directory.
  ///
  /// Returns `true` if the directory was created successfully
  /// Returns `false` if the directory could not be created or already exists
  Future<bool> makeDirectory(String sDirectory) {
    return FTPDirectory(_socket).makeDirectory(sDirectory);
  }

  /// Deletes the Directory with the Name of [sDirectory] in the current directory.
  ///
  /// Returns `true` if the directory was deleted successfully
  /// Returns `false` if the directory could not be deleted or does not nexist
  Future<bool> deleteEmptyDirectory(String? sDirectory) {
    return FTPDirectory(_socket).deleteEmptyDirectory(sDirectory);
  }

  /// Deletes the Directory with the Name of [sDirectory] in the current directory.
  ///
  /// Returns `true` if the directory was deleted successfully
  /// Returns `false` if the directory could not be deleted or does not nexist
  /// THIS USEFUL TO DELETE NON EMPTY DIRECTORY
  Future<bool> deleteDirectory(String sDirectory) async {
    String currentDir = await this.currentDirectory();
    if (!await this.changeDirectory(sDirectory)) {
      throw FTPCannotChangeDirectoryException(
          "Couldn't change directory to $sDirectory");
    }
    List<FTPEntry> dirContent = await this.listDirectoryContent();
    await Future.forEach(dirContent, (FTPEntry entry) async {
      if (entry.type == FTPEntryType.FILE) {
        if (!await deleteFile(entry.name)) {
          throw FTPCannotDeleteFileException(
              "Couldn't delete file ${entry.name}");
        }
      } else {
        if (!await deleteDirectory(entry.name)) {
          throw FTPCannotDeleteFolderException(
              "Couldn't delete folder ${entry.name}");
        }
      }
    });
    await this.changeDirectory(currentDir);
    return await deleteEmptyDirectory(sDirectory);
  }

  /// Change into the Directory with the Name of [sDirectory] within the current directory.
  ///
  /// Use `..` to navigate back
  /// Returns `true` if the directory was changed successfully
  /// Returns `false` if the directory could not be changed (does not exist, no permissions or another error)
  Future<bool> changeDirectory(String? sDirectory) {
    return FTPDirectory(_socket).changeDirectory(sDirectory);
  }

  /// Returns the current directory
  Future<String> currentDirectory() {
    return FTPDirectory(_socket).currentDirectory();
  }

  /// Returns the content of the current directory
  /// [cmd] refer to the used command for the server, there is servers working
  /// with MLSD and other with LIST
  Future<List<FTPEntry>> listDirectoryContent() {
    return FTPDirectory(_socket).directoryContent();
  }

  /// Returns the content names of the current directory
  /// [cmd] refer to the used command for the server, there is servers working
  /// with MLSD and other with LIST for detailed content
  Future<List<String>> listDirectoryContentOnlyNames() {
    return FTPDirectory(_socket).directoryContentNames();
  }

  /// Rename a file (or directory) from [sOldName] to [sNewName]
  Future<bool> rename(String sOldName, String sNewName) {
    return FTPFile(_socket).rename(sOldName, sNewName);
  }

  /// Delete the file [sFilename] from the server
  Future<bool> deleteFile(String? sFilename) {
    return FTPFile(_socket).delete(sFilename);
  }

  /// check the existence of  the file [sFilename] from the server
  Future<bool> existFile(String sFilename) {
    return FTPFile(_socket).exist(sFilename);
  }

  /// returns the file [sFilename] size from server,
  /// returns -1 if file does not exist
  Future<int> sizeFile(String sFilename) {
    return FTPFile(_socket).size(sFilename);
  }

  /// Upload the File [fileToUpload] to the current directory
  /// if [pRemoteName] is not setted the remote file will take take the same local name
  /// [pRetryCount] number of attempts
  ///
  /// this strategy can be used when we don't need to go step by step
  /// (connect -> upload -> disconnect) or there is a need for a number of attemps
  /// in case of a poor connexion for example
  Future<bool> uploadFileWithRetry(
    File fileToUpload, {
    String pRemoteName = '',
    int pRetryCount = 1,
    FileProgress? onProgress,
  }) {
    Future<bool> uploadFileRetry() async {
      bool res = await this.uploadFile(
        fileToUpload,
        sRemoteName: pRemoteName,
        onProgress: onProgress,
      );
      return res;
    }

    return Utils.retryAction(() => uploadFileRetry(), pRetryCount);
  }

  /// Download the Remote File [pRemoteName] to the local File [pLocalFile]
  /// [pRetryCount] number of attempts
  ///
  /// this strategy can be used when we don't need to go step by step
  /// (connect -> download -> disconnect) or there is a need for a number of attempts
  /// in case of a poor connexion for example
  Future<bool> downloadFileWithRetry(
    String pRemoteName,
    File pLocalFile, {
    int pRetryCount = 1,
    FileProgress? onProgress,
  }) {
    Future<bool> downloadFileRetry() async {
      bool res = await this.downloadFile(
        pRemoteName,
        pLocalFile,
        onProgress: onProgress,
      );
      return res;
    }

    return Utils.retryAction(() => downloadFileRetry(), pRetryCount);
  }

  /// Download the Remote Directory [pRemoteDir] to the local File [pLocalDir]
  /// [pRetryCount] number of attempts
  Future<bool> downloadDirectory(String pRemoteDir, Directory pLocalDir,
      {int pRetryCount = 1}) {
    Future<bool> downloadDir(String? pRemoteDir, Directory pLocalDir) async {
      await pLocalDir.create(recursive: true);

      //read remote directory content
      if (!await this.changeDirectory(pRemoteDir)) {
        throw FTPCannotDownloadException('Cannot download directory',
            '$pRemoteDir not found or inaccessible !');
      }
      List<FTPEntry> dirContent = await this.listDirectoryContent();
      await Future.forEach(dirContent, (FTPEntry entry) async {
        if (entry.type == FTPEntryType.FILE) {
          File localFile = File(join(pLocalDir.path, entry.name));
          await downloadFile(entry.name, localFile);
        } else if (entry.type == FTPEntryType.DIR) {
          //create a local directory
          var localDir = await Directory(join(pLocalDir.path, entry.name))
              .create(recursive: true);
          await downloadDir(entry.name, localDir);
          //back to current folder
          await this.changeDirectory('..');
        }
      });
      return true;
    }

    Future<bool> downloadDirRetry() async {
      bool res = await downloadDir(pRemoteDir, pLocalDir);
      return res;
    }

    return Utils.retryAction(() => downloadDirRetry(), pRetryCount);
  }

  /// check the existence of the Directory with the Name of [pDirectory].
  ///
  /// Returns `true` if the directory was changed successfully
  /// Returns `false` if the directory could not be changed (does not exist, no permissions or another error)
  Future<bool> checkFolderExistence(String pDirectory) {
    return this.changeDirectory(pDirectory);
  }

  /// Create a new Directory with the Name of [pDirectory] in the current directory if it does not exist.
  ///
  /// Returns `true` if the directory exists or was created successfully
  /// Returns `false` if the directory not found and could not be created
  Future<bool> createFolderIfNotExist(String pDirectory) async {
    if (!await checkFolderExistence(pDirectory)) {
      return this.makeDirectory(pDirectory);
    }
    return true;
  }
}

///Note that [LIST] and [MLSD] return content detailed
///BUT [NLST] return only dir/file names inside the given directory
enum ListCommand { NLST, LIST, MLSD }

enum TransferType { auto, ascii, binary }

enum TransferMode { active, passive }

enum SecurityType { FTP, FTPS, FTPES }

extension CommandListTypeEnum on ListCommand {
  String get describeEnum =>
      this.toString().substring(this.toString().indexOf('.') + 1);
}
