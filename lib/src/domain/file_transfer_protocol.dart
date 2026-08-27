import 'dart:typed_data';

import 'entities/ftp_entry.dart';
import 'progress.dart';

/// The web-safe core contract shared by every file-transfer client of this
/// package ([FTPConnect], [SFTPConnect] and the web `FtpWebClient`).
///
/// It only exposes byte/path oriented operations, so it contains **no**
/// `dart:io` types and compiles on every platform (including the web).
///
/// The `dart:io` `File`/`Directory` convenience helpers live on the
/// `FileTransferClient` sub-interface, which is only available on native
/// platforms.
///
/// **Concurrency:** each implementation wraps a single stateful connection or
/// session (an FTP control connection, an SFTP session, or a remote HTTP
/// session) with its own server-side current working directory. Calls on a
/// single instance must be awaited sequentially rather than run concurrently;
/// use a separate instance (and connection) per concurrent task instead.
abstract class FileTransferProtocol {
  /// Connect to the server (and authenticate).
  /// Returns `true` if connected successfully.
  Future<bool> connect();

  /// Disconnect from the server.
  /// Returns `true` if disconnected successfully.
  Future<bool> disconnect();

  /// Upload the in-memory bytes [data] to the current directory using
  /// [sRemoteName] as the remote file name.
  Future<bool> uploadData(
    Uint8List data,
    String sRemoteName, {
    FileProgress? onProgress,
  });

  /// Download the Remote File [sRemoteName] and return its content in memory.
  Future<Uint8List> downloadToBytes(
    String sRemoteName, {
    FileProgress? onProgress,
  });

  /// Create a new Directory [sDirectory] in the current directory.
  Future<bool> makeDirectory(String sDirectory);

  /// Delete the empty Directory [sDirectory].
  Future<bool> deleteDirectory(String sDirectory);

  /// Delete the Directory [sDirectory] and all of its content recursively,
  /// even when it is not empty.
  ///
  /// Returns `false` (instead of throwing) when the directory does not exist or
  /// cannot be removed.
  Future<bool> deleteNonEmptyDirectory(String sDirectory);

  /// Change into the Directory [sDirectory].
  Future<bool> changeDirectory(String sDirectory);

  /// Returns the current working directory.
  Future<String> currentDirectory();

  /// Returns the detailed content of the current directory (or [sDirectory]).
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
