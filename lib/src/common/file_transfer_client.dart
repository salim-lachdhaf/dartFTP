import 'dart:io';
import 'dart:typed_data';

import 'ftp_entry.dart';
import 'logger.dart';

/// Progress callback used by upload/download operations.
///
/// [progressInPercent] is the completed percentage (0 -> 100),
/// [totalTransferred] the number of bytes transferred so far and [fileSize] the
/// total size of the file in bytes.
typedef FileProgress = void Function(
    double progressInPercent, int totalTransferred, int fileSize);

/// Common base shared by every file transfer client of this package
/// (currently [FTPConnect] and [SFTPConnect]).
///
/// It centralizes the connection settings common to all clients (host, port,
/// credentials, timeout and logger) through a single constructor, and declares
/// the shared method contract so that switching between FTP and SFTP only
/// requires changing the instantiated class.
abstract class FileTransferClient {
  /// Hostname or IP Address of the server.
  final String host;

  /// Port number of the server.
  final int port;

  /// Username used to authenticate.
  final String user;

  /// Password used to authenticate.
  final String pass;

  /// Timeout in seconds to wait for the connection/responses.
  final int timeout;

  /// Logger used to emit debug information.
  final Logger logger;

  /// Base constructor centralizing the connection settings shared by every
  /// client. Subclasses forward their own defaults through `super`.
  FileTransferClient(
    this.host, {
    required this.port,
    this.user = 'anonymous',
    this.pass = '',
    this.timeout = 30,
    bool showLog = false,
    Logger? logger,
  }) : logger = logger ?? Logger(isEnabled: showLog);

  /// Connect to the server (and authenticate).
  /// Returns `true` if connected successfully.
  Future<bool> connect();

  /// Disconnect from the server.
  /// Returns `true` if disconnected successfully.
  Future<bool> disconnect();

  /// Upload the File [fFile] to the current directory.
  /// If [sRemoteName] is set it is used as the remote file name otherwise the original file name is used.
  Future<bool> uploadFile(
    File fFile, {
    String sRemoteName,
    FileProgress? onProgress,
  });

  /// Download the Remote File [sRemoteName] to the local File [fFile].
  Future<bool> downloadFile(
    String sRemoteName,
    File fFile, {
    FileProgress? onProgress,
  });

  /// Upload the in-memory bytes [data] to the current directory using
  /// [sRemoteName] as the remote file name.
  ///
  /// Useful when the payload is generated on the fly and never touches the
  /// local file system.
  Future<bool> uploadData(
    Uint8List data,
    String sRemoteName, {
    FileProgress? onProgress,
  });

  /// Download the Remote File [sRemoteName] and return its content in memory
  /// as a [Uint8List] instead of writing it to a local file.
  Future<Uint8List> downloadToBytes(
    String sRemoteName, {
    FileProgress? onProgress,
  });

  /// Upload the local Directory [pLocalDir] recursively into the remote
  /// directory [pRemoteDir] (created if it does not exist).
  Future<bool> uploadDirectory(
    Directory pLocalDir,
    String pRemoteDir, {
    FileProgress? onProgress,
  });

  /// Download the Remote Directory [pRemoteDir] to the local Directory [pLocalDir].
  Future<bool> downloadDirectory(
    String pRemoteDir,
    Directory pLocalDir,
  );

  /// Create a new Directory [sDirectory] in the current directory.
  Future<bool> makeDirectory(String sDirectory);

  /// Delete the empty Directory [sDirectory].
  Future<bool> deleteEmptyDirectory(String sDirectory);

  /// Delete the Directory [sDirectory] and all of its content recursively.
  Future<bool> deleteDirectory(String sDirectory);

  /// Delete the Directory [sDirectory] even when it is not empty.
  ///
  /// Removes all of its content recursively and then the directory itself.
  /// Returns `false` (instead of throwing) when the directory does not exist
  /// or cannot be removed.
  Future<bool> deleteNonEmptyDirectory(String sDirectory);

  /// Change into the Directory [sDirectory].
  Future<bool> changeDirectory(String sDirectory);

  /// Returns the current working directory.
  Future<String> currentDirectory();

  /// Returns the detailed content of the current directory.
  Future<List<FTPEntry>> listDirectoryContent([String? sDirectory]);

  /// Rename a file (or directory) from [sOldName] to [sNewName].
  Future<bool> rename(String sOldName, String sNewName);

  /// Delete the file [sFilename] from the server.
  Future<bool> deleteFile(String sFilename);

  /// Check the existence of the file [sFilename] on the server.
  Future<bool> existFile(String sFilename);

  /// Returns the file [sFilename] size from server, or -1 if it does not exist.
  Future<int> sizeFile(String sFilename);

  /// Check the existence of the Directory [pDirectory].
  Future<bool> checkFolderExistence(String pDirectory);

  /// Create the Directory [pDirectory] if it does not already exist.
  Future<bool> createFolderIfNotExist(String pDirectory);
}
