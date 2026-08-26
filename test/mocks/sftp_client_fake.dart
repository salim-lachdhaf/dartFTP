import 'dart:io';
import 'dart:typed_data';

import 'package:ftpconnect/ftpconnect.dart';
import 'package:path/path.dart' as p;

import 'virtual_file_system.dart';

/// Offline mock of an SFTP [FileTransferClient].
///
/// It extends [FileTransferClient] and reproduces the exact behavior of the
/// real `SFTPConnect` (relative paths resolved against a `.`-based working
/// directory, `stat`-based existence checks with no directory side effects,
/// recursive deletes/downloads using absolute paths), but is backed by an
/// in-memory [VirtualFileSystem] so the full client contract can be
/// unit-tested without any network access.
class SftpClientForTest extends FileTransferClient {
  final VirtualFileSystem fs;

  /// When `true`, [connect] throws to let tests cover the failed-connect path.
  final bool throwOnConnect;

  bool _connected = false;
  String _currentDirectory = '.';

  SftpClientForTest({
    String host = 'localhost',
    int port = 22,
    super.user = 'anonymous',
    super.pass = '',
    super.showLog = false,
    this.throwOnConnect = false,
    VirtualFileSystem? fs,
  })  : fs = fs ?? VirtualFileSystem(),
        super(host, port: port);

  bool get isConnected => _connected;

  String _resolve(String? path) {
    final String base = _currentDirectory == '.' ? '/' : _currentDirectory;
    if (path == null || path.isEmpty) return base;
    return p.posix
        .normalize(p.posix.isAbsolute(path) ? path : p.posix.join(base, path));
  }

  void _report(FileProgress? onProgress, int total) {
    if (onProgress == null) return;
    if (total <= 0) {
      onProgress(100, 0, total);
      return;
    }
    int done = 0;
    const int chunk = 1024;
    while (done < total) {
      done = (done + chunk).clamp(0, total);
      final double percent =
          double.parse(((done / total) * 100).toStringAsFixed(2));
      onProgress(percent > 100 ? 100 : percent, done, total);
    }
  }

  @override
  Future<bool> connect() async {
    logger.log('Connecting...');
    if (throwOnConnect) {
      throw FTPConnectException('Could not connect to $host ($port)');
    }
    _connected = true;
    _currentDirectory = '.';
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
  Future<String> currentDirectory() async => _currentDirectory;

  @override
  Future<bool> changeDirectory(String sDirectory) async {
    final String target = _resolve(sDirectory);
    if (!fs.isDirectory(target)) return false;
    _currentDirectory = target;
    return true;
  }

  @override
  Future<List<FTPEntry>> listDirectoryContent([String? sDirectory]) async {
    final String target = _resolve(sDirectory);
    return fs.list(target).map((VfsEntry e) {
      final String type = e.isDirectory ? 'dir' : 'file';
      return FTPEntry.parse(
          'Type=$type;Size=${e.size}; ${e.name}', ListCommand.mlsd);
    }).toList();
  }

  @override
  Future<bool> makeDirectory(String sDirectory) async {
    return fs.createDirectory(_resolve(sDirectory));
  }

  @override
  Future<bool> deleteEmptyDirectory(String? sDirectory) async {
    if (sDirectory == null) return false;
    return fs.removeEmptyDirectory(_resolve(sDirectory));
  }

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
  Future<bool> checkFolderExistence(String sDirectory) async {
    return fs.isDirectory(_resolve(sDirectory));
  }

  @override
  Future<bool> createFolderIfNotExist(String sDirectory) async {
    if (await checkFolderExistence(sDirectory)) return true;
    return makeDirectory(sDirectory);
  }

  @override
  Future<bool> rename(String sOldName, String sNewName) async {
    return fs.rename(_resolve(sOldName), _resolve(sNewName));
  }

  @override
  Future<bool> deleteFile(String? sFilename) async {
    if (sFilename == null) return false;
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

  @override
  Future<bool> uploadFile(
    File fFile, {
    String sRemoteName = '',
    FileProgress? onProgress,
  }) async {
    final String remoteName =
        sRemoteName.isEmpty ? p.basename(fFile.path) : sRemoteName;
    final List<int> bytes = await fFile.readAsBytes();
    if (!fs.writeFile(_resolve(remoteName), bytes)) return false;
    _report(onProgress, bytes.length);
    return true;
  }

  @override
  Future<bool> downloadFile(
    String? sRemoteName,
    File fFile, {
    FileProgress? onProgress,
  }) async {
    if (sRemoteName == null) {
      throw FTPConnectException('Remote file name is required');
    }
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
  Future<bool> downloadDirectory(String pRemoteDir, Directory pLocalDir) {
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
