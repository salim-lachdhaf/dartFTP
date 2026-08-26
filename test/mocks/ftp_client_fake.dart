import 'dart:io';
import 'dart:typed_data';

import 'package:ftpconnect/ftpconnect.dart';
import 'package:path/path.dart' as p;

import 'virtual_file_system.dart';

/// Offline mock of an FTP [FileTransferClient].
///
/// It extends [FileTransferClient] and reproduces the exact behavior of the
/// real `FTPConnect` (same success/failure results and the same quirks, e.g.
/// [checkFolderExistence] navigating into the directory as a side effect),
/// but is backed by an in-memory [VirtualFileSystem] so the full client
/// contract can be unit-tested without any network access.
class FtpClientForTest extends FileTransferClient {
  final VirtualFileSystem fs;

  /// When `true`, [connect] throws to let tests cover the failed-connect path.
  final bool throwOnConnect;

  bool _connected = false;
  String _cwd = '/';

  FtpClientForTest({
    String host = 'localhost',
    int port = 21,
    super.user = 'anonymous',
    super.pass = '',
    super.showLog = false,
    this.throwOnConnect = false,
    VirtualFileSystem? fs,
  })  : fs = fs ?? VirtualFileSystem(),
        super(host, port: port);

  bool get isConnected => _connected;

  String _resolve(String? path) {
    if (path == null || path.isEmpty) return _cwd;
    return p.posix
        .normalize(p.posix.isAbsolute(path) ? path : p.posix.join(_cwd, path));
  }

  void _report(FileProgress? onProgress, int total) {
    if (onProgress == null) return;
    if (total <= 0) {
      onProgress(100, 0, total);
      return;
    }
    int sent = 0;
    const int chunk = 1024;
    while (sent < total) {
      sent = (sent + chunk).clamp(0, total);
      final double percent =
          double.parse(((sent / total) * 100).toStringAsFixed(2));
      onProgress(percent > 100 ? 100 : percent, sent, total);
    }
  }

  @override
  Future<bool> connect() async {
    logger.log('Connecting...');
    if (throwOnConnect) {
      throw FTPConnectException('Could not connect to $host ($port)');
    }
    _connected = true;
    _cwd = '/';
    logger.log('Connected!');
    return true;
  }

  @override
  Future<bool> disconnect() async {
    _connected = false;
    logger.log('Disconnected!');
    return true;
  }

  @override
  Future<bool> uploadFile(
    File fFile, {
    String? sRemoteName,
    FileProgress? onProgress,
  }) async {
    final String remoteName = (sRemoteName == null || sRemoteName.isEmpty)
        ? p.basename(fFile.path)
        : sRemoteName;
    final List<int> bytes = await fFile.readAsBytes();
    if (!fs.writeFile(_resolve(remoteName), bytes)) return false;
    _report(onProgress, bytes.length);
    return true;
  }

  @override
  Future<bool> downloadFile(
    String sRemoteName,
    File fFile, {
    FileProgress? onProgress,
  }) async {
    final List<int>? bytes = fs.readFile(_resolve(sRemoteName));
    if (bytes == null) {
      throw FTPConnectException('Remote File $sRemoteName does not exist!');
    }
    await fFile.parent.create(recursive: true);
    await fFile.writeAsBytes(bytes);
    _report(onProgress, bytes.length);
    return true;
  }

  @override
  Future<bool> uploadData(
    Uint8List data,
    String sRemoteName, {
    FileProgress? onProgress,
  }) async {
    if (!fs.writeFile(_resolve(sRemoteName), data)) return false;
    _report(onProgress, data.length);
    return true;
  }

  @override
  Future<Uint8List> downloadToBytes(
    String sRemoteName, {
    FileProgress? onProgress,
  }) async {
    final List<int>? bytes = fs.readFile(_resolve(sRemoteName));
    if (bytes == null) {
      throw FTPConnectException('Remote File $sRemoteName does not exist!');
    }
    _report(onProgress, bytes.length);
    return Uint8List.fromList(bytes);
  }

  @override
  Future<bool> makeDirectory(String sDirectory) async {
    return fs.createDirectory(_resolve(sDirectory));
  }

  @override
  Future<bool> deleteEmptyDirectory(String sDirectory) async {
    return fs.removeEmptyDirectory(_resolve(sDirectory));
  }

  @override
  Future<bool> deleteDirectory(String sDirectory) async {
    final String currentDir = await currentDirectory();
    if (!await changeDirectory(sDirectory)) {
      throw FTPConnectException("Couldn't change directory to $sDirectory");
    }
    final List<FTPEntry> dirContent = await listDirectoryContent();
    for (final FTPEntry entry in dirContent) {
      if (entry.type == FTPEntryType.file) {
        if (!await deleteFile(entry.name)) {
          throw FTPConnectException("Couldn't delete file ${entry.name}");
        }
      } else {
        if (!await deleteDirectory(entry.name)) {
          throw FTPConnectException("Couldn't delete folder ${entry.name}");
        }
      }
    }
    await changeDirectory(currentDir);
    return deleteEmptyDirectory(sDirectory);
  }

  @override
  Future<bool> deleteNonEmptyDirectory(String sDirectory) async {
    try {
      return await deleteDirectory(sDirectory);
    } catch (e) {
      logger.log('Cannot delete directory $sDirectory: $e');
      return false;
    }
  }

  @override
  Future<bool> changeDirectory(String sDirectory) async {
    final String target = _resolve(sDirectory);
    if (fs.isDirectory(target)) {
      _cwd = target;
      return true;
    }
    return false;
  }

  @override
  Future<String> currentDirectory() async => _cwd;

  @override
  Future<List<FTPEntry>> listDirectoryContent([String? sDirectory]) async {
    final String dir = sDirectory == null ? _cwd : _resolve(sDirectory);
    return fs.list(dir).map((VfsEntry e) {
      final String type = e.isDirectory ? 'dir' : 'file';
      return FTPEntry.parse(
          'Type=$type;Size=${e.size}; ${e.name}', ListCommand.mlsd);
    }).toList();
  }

  @override
  Future<bool> rename(String sOldName, String sNewName) async {
    return fs.rename(_resolve(sOldName), _resolve(sNewName));
  }

  @override
  Future<bool> deleteFile(String sFilename) async {
    return fs.removeFile(_resolve(sFilename));
  }

  @override
  Future<bool> existFile(String sFilename) async {
    return await sizeFile(sFilename) != -1;
  }

  @override
  Future<int> sizeFile(String sFilename) async {
    return fs.fileSize(_resolve(sFilename)) ?? -1;
  }

  /// Mirrors `FTPConnect.checkFolderExistence`, which delegates to
  /// [changeDirectory] and therefore navigates into the folder as a side
  /// effect when it exists.
  @override
  Future<bool> checkFolderExistence(String pDirectory) async {
    return changeDirectory(pDirectory);
  }

  @override
  Future<bool> createFolderIfNotExist(String pDirectory) async {
    if (!await checkFolderExistence(pDirectory)) {
      return makeDirectory(pDirectory);
    }
    return true;
  }

  @override
  Future<bool> downloadDirectory(String pRemoteDir, Directory pLocalDir) {
    Future<bool> downloadDir(String remoteDir, Directory localDir) async {
      await localDir.create(recursive: true);
      if (!await changeDirectory(remoteDir)) {
        throw FTPConnectException('Cannot download directory',
            '$remoteDir not found or inaccessible !');
      }
      final List<FTPEntry> dirContent = await listDirectoryContent();
      for (final FTPEntry entry in dirContent) {
        if (entry.type == FTPEntryType.file) {
          await downloadFile(
              entry.name, File(p.join(localDir.path, entry.name)));
        } else if (entry.type == FTPEntryType.dir) {
          final Directory child =
              await Directory(p.join(localDir.path, entry.name))
                  .create(recursive: true);
          await downloadDir(entry.name, child);
          await changeDirectory('..');
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
      final String currentDir = await currentDirectory();
      if (!await createFolderIfNotExist(remoteDir)) {
        throw FTPConnectException(
            'Cannot upload directory', 'Could not create remote $remoteDir');
      }
      if (!await changeDirectory(remoteDir)) {
        throw FTPConnectException('Cannot upload directory',
            '$remoteDir not found or inaccessible !');
      }
      for (final FileSystemEntity entity in localDir.listSync()) {
        final String name = p.basename(entity.path);
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
}
