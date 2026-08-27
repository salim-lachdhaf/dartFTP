import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:path/path.dart' as p;

import '../common/ftp_entry.dart';
import '../common/ftp_exceptions.dart';
import '../common/file_transfer_client.dart';
import '../common/utils.dart';

/// A simple SFTP client built on top of the pure-Dart
/// [dartssh2](https://pub.dev/packages/dartssh2) package.
///
/// It mirrors the public API of [FTPConnect] (both implement
/// [FileTransferClient]) so that switching between FTP and SFTP requires
/// minimal changes.
class SFTPConnect extends FileTransferClient {
  final String? _privateKey;
  final String? _passphrase;
  final SSHHostkeyVerifyHandler? _onVerifyHostKey;

  SSHClient? _client;
  SftpClient? _sftp;

  ///The remote directory used to resolve relative paths.
  String _currentDirectory = '.';

  /// Create an SFTP Client instance.
  ///
  /// [host]: Hostname or IP Address
  /// [port]: Port number (Defaults to 22)
  /// [user]: Username
  /// [pass]: Password (ignored when [privateKey] is provided)
  /// [privateKey]: A PEM/OpenSSH private key content, used instead of [pass]
  /// [passphrase]: The passphrase protecting [privateKey] (if any)
  /// [timeout]: Timeout in seconds for the socket/handshake/authentication
  /// [showLog]: Enable Debug Logging
  /// [logger]: custom logger
  /// [onVerifyHostKey]: optional host key verification handler. When omitted,
  /// every host key is accepted (only appropriate for trusted networks/tests).
  SFTPConnect(
    super.host, {
    super.port = 22,
    super.user = 'anonymous',
    super.pass = '',
    String? privateKey,
    String? passphrase,
    super.timeout = 30,
    super.showLog = false,
    super.logger,
    SSHHostkeyVerifyHandler? onVerifyHostKey,
  })  : _privateKey = privateKey,
        _passphrase = passphrase,
        _onVerifyHostKey = onVerifyHostKey;

  /// The underlying [SSHClient] in case advanced/native features are needed.
  /// Only available after a successful [connect].
  SSHClient? get client => _client;

  /// The underlying [SftpClient]. Only available after a successful [connect].
  SftpClient get sftpClient {
    final sftp = _sftp;
    if (sftp == null) {
      throw FTPConnectException('SFTP session is not connected. '
          'Call connect() first.');
    }
    return sftp;
  }

  ///Resolve [path] relative to the current directory when it is not absolute.
  String _resolve(String? path) {
    if (path == null || path.isEmpty) return _currentDirectory;
    if (p.posix.isAbsolute(path)) return p.posix.normalize(path);
    return p.posix.normalize(p.posix.join(_currentDirectory, path));
  }

  /// Connect to the SSH server and open an SFTP session.
  /// Returns `true` if connected successfully.
  @override
  Future<bool> connect() async {
    logger.log('Connecting...');
    final Duration duration = Duration(seconds: timeout);

    final SSHSocket socket;
    try {
      socket = await SSHSocket.connect(host, port, timeout: duration);
    } catch (e) {
      throw FTPConnectException(
          'Could not connect to $host ($port)', e.toString());
    }

    try {
      _client = SSHClient(
        socket,
        username: user,
        onVerifyHostKey: _onVerifyHostKey,
        onPasswordRequest: _privateKey == null ? () => pass : null,
        identities: _privateKey != null
            ? SSHKeyPair.fromPem(_privateKey!, _passphrase)
            : null,
        handshakeTimeout: duration,
        authTimeout: duration,
      );
      await _client!.authenticated;
      _sftp = await _client!.sftp();
    } catch (e) {
      throw FTPConnectException(
          'Could not open the SFTP session', e.toString());
    }

    logger.log('Connected!');
    return true;
  }

  /// Close the SFTP session and disconnect from the SSH server.
  /// Returns `true` if disconnected successfully.
  @override
  Future<bool> disconnect() async {
    logger.log('Disconnecting...');
    try {
      await _sftp?.close();
    } catch (_) {
      // Ignore
    }

    // Observe `done` as well: it may complete with an error while channels
    // are being torn down, and an unobserved error would escape to the zone.
    unawaited(_client?.done.catchError((_) {}));
    try {
      await _client?.close();
    } catch (_) {
      // Ignore
    }
    _sftp = null;
    _client = null;

    logger.log('Disconnected!');
    return true;
  }

  /// Returns the current working directory used to resolve relative paths.
  @override
  Future<String> currentDirectory() async => _currentDirectory;

  /// Change into the Directory [sDirectory] (relative or absolute).
  ///
  /// Use `..` to navigate back.
  /// Returns `true` if the directory exists and was changed successfully.
  @override
  Future<bool> changeDirectory(String sDirectory) async {
    final String target = _resolve(sDirectory);
    try {
      final SftpFileAttrs attrs = await sftpClient.stat(target);
      if (!attrs.isDirectory) return false;
      _currentDirectory = target;
      return true;
    } catch (e) {
      logger.log('Cannot change directory to $target: $e');
      return false;
    }
  }

  /// Returns the content of the directory [sDirectory] (defaults to current).
  @override
  Future<List<FTPEntry>> listDirectoryContent([String? sDirectory]) async {
    final String target = _resolve(sDirectory);
    final List<SftpName> content = await sftpClient.listdir(target);
    return content
        .where((SftpName e) => e.filename != '.' && e.filename != '..')
        .map((SftpName e) => FTPEntry.sftp(e))
        .toList();
  }

  /// Create a new Directory [sDirectory] in the current directory.
  /// Returns `true` if the directory was created successfully.
  @override
  Future<bool> makeDirectory(String sDirectory) async {
    try {
      await sftpClient.mkdir(_resolve(sDirectory));
      return true;
    } catch (e) {
      logger.log('Cannot create directory $sDirectory: $e');
      return false;
    }
  }

  /// Delete the empty Directory [sDirectory].
  /// Returns `true` if the directory was deleted successfully.
  @override
  Future<bool> deleteEmptyDirectory(String? sDirectory) async {
    if (sDirectory == null) return false;
    try {
      await sftpClient.rmdir(_resolve(sDirectory));
      return true;
    } catch (e) {
      logger.log('Cannot delete directory $sDirectory: $e');
      return false;
    }
  }

  /// Delete the Directory [sDirectory] and all of its content recursively.
  /// Returns `true` if the directory was deleted successfully.
  @override
  Future<bool> deleteDirectory(String sDirectory) async {
    final String target = _resolve(sDirectory);
    final List<FTPEntry> content = await listDirectoryContent(target);
    for (final FTPEntry entry in content) {
      final String childPath = p.posix.join(target, entry.name);
      if (entry.type == FTPEntryType.dir) {
        if (!await deleteDirectory(childPath)) {
          throw FTPConnectException("Couldn't delete folder ${entry.name}");
        }
      } else {
        if (!await deleteFile(childPath)) {
          throw FTPConnectException("Couldn't delete file ${entry.name}");
        }
      }
    }
    return deleteEmptyDirectory(target);
  }

  /// Delete the Directory [sDirectory] even when it is not empty.
  ///
  /// Removes all of its content recursively then the directory itself.
  /// Returns `false` (instead of throwing) when the directory does not exist
  /// or cannot be removed.
  @override
  Future<bool> deleteNonEmptyDirectory(String sDirectory) async {
    try {
      return await deleteDirectory(sDirectory);
    } catch (e) {
      logger.log('Cannot delete directory $sDirectory: $e');
      return false;
    }
  }

  /// Check the existence of the Directory [sDirectory].
  @override
  Future<bool> checkFolderExistence(String sDirectory) async {
    try {
      final SftpFileAttrs attrs = await sftpClient.stat(_resolve(sDirectory));
      return attrs.isDirectory;
    } catch (_) {
      return false;
    }
  }

  /// Create the Directory [sDirectory] if it does not already exist.
  @override
  Future<bool> createFolderIfNotExist(String sDirectory) async {
    if (await checkFolderExistence(sDirectory)) return true;
    return makeDirectory(sDirectory);
  }

  /// Rename a file (or directory) from [sOldName] to [sNewName].
  @override
  Future<bool> rename(String sOldName, String sNewName) async {
    try {
      await sftpClient.rename(_resolve(sOldName), _resolve(sNewName));
      return true;
    } catch (e) {
      logger.log('Cannot rename $sOldName to $sNewName: $e');
      return false;
    }
  }

  /// Delete the file [sFilename] from the server.
  @override
  Future<bool> deleteFile(String? sFilename) async {
    if (sFilename == null) return false;
    try {
      await sftpClient.remove(_resolve(sFilename));
      return true;
    } catch (e) {
      logger.log('Cannot delete file $sFilename: $e');
      return false;
    }
  }

  /// Check the existence of the file [sFilename] on the server.
  @override
  Future<bool> existFile(String sFilename) async {
    return await sizeFile(sFilename) != -1;
  }

  /// Returns the file [sFilename] size from server.
  /// Returns -1 if the file does not exist.
  @override
  Future<int> sizeFile(String sFilename) async {
    try {
      final SftpFileAttrs attrs = await sftpClient.stat(_resolve(sFilename));
      return attrs.size ?? -1;
    } catch (_) {
      return -1;
    }
  }

  /// Upload the File [fFile] to the current directory.
  /// If [sRemoteName] is set, it is used as the remote file name.
  @override
  Future<bool> uploadFile(
    File fFile, {
    String sRemoteName = '',
    FileProgress? onProgress,
  }) async {
    logger.log('Upload File: ${fFile.path}');
    final String remoteName =
        sRemoteName.isEmpty ? p.basename(fFile.path) : sRemoteName;
    return _upload(
      remoteName,
      await fFile.length(),
      fFile.openRead().cast<Uint8List>(),
      onProgress: onProgress,
    );
  }

  /// Download the Remote File [sRemoteName] to the local File [fFile].
  @override
  Future<bool> downloadFile(
    String? sRemoteName,
    File fFile, {
    FileProgress? onProgress,
  }) async {
    if (sRemoteName == null) {
      throw FTPConnectException('Remote file name is required');
    }
    logger.log('Download $sRemoteName to ${fFile.path}');

    await fFile.parent.create(recursive: true);
    final IOSink sink = fFile.openWrite();
    try {
      await _download(sRemoteName, sink.add, onProgress: onProgress);
    } finally {
      await sink.flush();
      await sink.close();
    }
    logger.log('File Downloaded!');
    return true;
  }

  /// Upload the in-memory bytes [data] to the current directory as [sRemoteName].
  @override
  Future<bool> uploadData(
    Uint8List data,
    String sRemoteName, {
    FileProgress? onProgress,
  }) {
    logger.log('Upload data to: $sRemoteName');
    return _upload(
      sRemoteName,
      data.length,
      Stream<Uint8List>.value(data),
      onProgress: onProgress,
    );
  }

  /// Streams [source] ([total] bytes) into the remote file [sRemoteName],
  /// reporting progress. Shared by [uploadFile] and [uploadData] so file-based
  /// and in-memory uploads use the exact same path.
  Future<bool> _upload(
    String sRemoteName,
    int total,
    Stream<Uint8List> source, {
    FileProgress? onProgress,
  }) async {
    final String remotePath = _resolve(sRemoteName);

    final SftpFile remoteFile = await sftpClient.open(
      remotePath,
      mode: SftpFileOpenMode.create |
          SftpFileOpenMode.write |
          SftpFileOpenMode.truncate,
    );
    try {
      final SftpFileWriter writer = remoteFile.write(
        source,
        onProgress: onProgress == null
            ? null
            : (int sent) => onProgress(Utils.percent(sent, total), sent, total),
      );
      await writer.done;
    } finally {
      await remoteFile.close();
    }
    logger.log('File Uploaded!');
    return true;
  }

  /// Download the Remote File [sRemoteName] and return its content in memory.
  @override
  Future<Uint8List> downloadToBytes(
    String sRemoteName, {
    FileProgress? onProgress,
  }) async {
    logger.log('Download $sRemoteName to memory');
    final BytesBuilder builder = BytesBuilder(copy: false);
    await _download(sRemoteName, builder.add, onProgress: onProgress);
    logger.log('File Downloaded!');
    return builder.takeBytes();
  }

  /// Streams the remote file [sRemoteName], handing each chunk to [onChunk] and
  /// reporting progress. Shared by [downloadFile] and [downloadToBytes] so
  /// file-based and in-memory downloads use the exact same (streamed) path.
  Future<void> _download(
    String sRemoteName,
    void Function(Uint8List chunk) onChunk, {
    FileProgress? onProgress,
  }) async {
    final String remotePath = _resolve(sRemoteName);
    final int total = await sizeFile(sRemoteName);
    if (total == -1) {
      throw FTPConnectException('Remote File $sRemoteName does not exist!');
    }

    final SftpFile remoteFile = await sftpClient.open(remotePath);
    try {
      var read = 0;
      await for (final Uint8List chunk in remoteFile.read()) {
        onChunk(chunk);
        if (onProgress != null) {
          read += chunk.length;
          onProgress(Utils.percent(read, total), read, total);
        }
      }
    } finally {
      await remoteFile.close();
    }
  }

  /// Download the Remote Directory [pRemoteDir] to the local Directory [pLocalDir].
  @override
  Future<bool> downloadDirectory(
    String pRemoteDir,
    Directory pLocalDir,
  ) {
    Future<bool> downloadDir(String remoteDir, Directory localDir) async {
      await localDir.create(recursive: true);
      final List<FTPEntry> content = await listDirectoryContent(remoteDir);
      for (final FTPEntry entry in content) {
        final String remoteChild = p.posix.join(remoteDir, entry.name);
        if (entry.type == FTPEntryType.dir) {
          await downloadDir(
              remoteChild, Directory(p.join(localDir.path, entry.name)));
        } else {
          await downloadFile(
              remoteChild, File(p.join(localDir.path, entry.name)));
        }
      }
      return true;
    }

    return downloadDir(_resolve(pRemoteDir), pLocalDir);
  }

  /// Upload the local Directory [pLocalDir] recursively into the remote
  /// directory [pRemoteDir] (created if it does not exist).
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
      final List<FileSystemEntity> entities = localDir.listSync();
      for (final FileSystemEntity entity in entities) {
        final String name = p.basename(entity.path);
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

    return uploadDir(pLocalDir, _resolve(pRemoteDir));
  }
}
