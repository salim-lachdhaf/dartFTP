import 'dart:io';

import 'file_transfer_protocol.dart';
import 'progress.dart';

/// The native (`dart:io`) file-transfer contract implemented by [FTPConnect]
/// and [SFTPConnect].
///
/// It extends the web-safe [FileTransferProtocol] with `File`/`Directory`
/// convenience helpers that only make sense on platforms with a local file
/// system (i.e. everything except the web).
///
/// Switching between FTP and SFTP only requires changing the instantiated
/// class. Connection settings are held by the concrete implementations.
abstract class FileTransferClient implements FileTransferProtocol {
  /// Upload the File [fFile] to the current directory.
  /// If [sRemoteName] is set it is used as the remote file name, otherwise the
  /// original file name is used.
  Future<bool> uploadFile(
    File fFile, {
    String? sRemoteName,
    FileProgress? onProgress,
  });

  /// Download the Remote File [sRemoteName] to the local File [fFile].
  Future<bool> downloadFile(
    String sRemoteName,
    File fFile, {
    FileProgress? onProgress,
  });

  /// Upload the local Directory [pLocalDir] recursively into the remote
  /// directory [pRemoteDir] (created if it does not exist).
  Future<bool> uploadDirectory(
    Directory pLocalDir,
    String pRemoteDir, {
    FileProgress? onProgress,
  });

  /// Download the Remote Directory [pRemoteDir] to the local Directory
  /// [pLocalDir].
  Future<bool> downloadDirectory(String pRemoteDir, Directory pLocalDir);
}
