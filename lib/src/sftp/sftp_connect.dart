import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart' show SSHHostkeyVerifyHandler;
import 'package:path/path.dart' as p;

import '../config/transfer_config.dart';
import '../domain/entities/ftp_entry.dart';
import '../domain/enums.dart';
import '../domain/exceptions.dart';
import '../domain/file_transfer_client.dart';
import '../domain/logger.dart';
import '../domain/progress.dart';
import '../infrastructure/dartssh2_sftp_adapter.dart';
import '../utils/utils.dart';
import 'sftp_adapter.dart';

/// A simple SFTP client.
///
/// It mirrors the public API of [FTPConnect] (both implement
/// [FileTransferClient]). The SSH/SFTP stack is injected through a
/// [SftpConnector] (defaulting to a `dartssh2` implementation), which makes the
/// real client testable with an in-memory adapter.
class SFTPConnect implements FileTransferClient {
  final String host;
  final int port;
  final String user;
  final String pass;
  final int timeout;
  final Logger logger;
  final String? _privateKey;
  final String? _passphrase;
  final SSHHostkeyVerifyHandler? _onVerifyHostKey;
  final SftpConnector _connector;

  SftpAdapter? _adapter;

  /// The remote directory used to resolve relative paths.
  String _currentDirectory = '.';

  /// Create an SFTP client instance.
  ///
  /// [host]: Hostname or IP Address
  /// [port]: Port number (defaults to 22)
  /// [user]: Username
  /// [pass]: Password (ignored when [privateKey] is provided)
  /// [privateKey]: A PEM/OpenSSH private key content, used instead of [pass]
  /// [passphrase]: The passphrase protecting [privateKey] (if any)
  /// [timeout]: Timeout in seconds for the socket/handshake/authentication
  /// [showLog]: Enable debug logging
  /// [onVerifyHostKey]: optional host key verification handler
  /// [connector]: Injectable SSH/SFTP stack (defaults to `dartssh2`)
  SFTPConnect(
    this.host, {
    this.port = 22,
    this.user = 'anonymous',
    this.pass = '',
    String? privateKey,
    String? passphrase,
    this.timeout = 30,
    bool showLog = false,
    Logger? logger,
    SSHHostkeyVerifyHandler? onVerifyHostKey,
    SftpConnector? connector,
  })  : _privateKey = privateKey,
        _passphrase = passphrase,
        _onVerifyHostKey = onVerifyHostKey,
        logger = logger ?? Logger(isEnabled: showLog),
        _connector = connector ?? const Dartssh2SftpConnector();

  /// Create an SFTP client from an [SftpConfig].
  ///
  /// Returns a fully-typed [SFTPConnect] (implementing [FileTransferClient]), so
  /// the `dart:io` `File`/`Directory` helpers remain available.
  factory SFTPConnect.fromConfig(SftpConfig config) => SFTPConnect(
        config.host,
        port: config.port ?? 22,
        user: config.user,
        pass: config.pass,
        privateKey: config.privateKey,
        passphrase: config.passphrase,
        timeout: config.timeout,
        showLog: config.showLog,
        logger: config.logger,
      );

  SftpAdapter get _sftp {
    final SftpAdapter? adapter = _adapter;
    if (adapter == null) {
      throw const FTPConnectException(
          'SFTP session is not connected. Call connect() first.');
    }
    return adapter;
  }

  /// Resolve [path] relative to the current directory when it is not absolute.
  String _resolve(String? path) {
    if (path == null || path.isEmpty) {
      return _currentDirectory;
    }

    if (p.posix.isAbsolute(path)) {
      return p.posix.normalize(path);
    }

    return p.posix.normalize(
      p.posix.join(_currentDirectory, path),
    );
  }

  @override
  Future<bool> connect() async {
    logger.log('Connecting...');
    // A new session has its own server-side cwd; drop any path resolved
    // against a previous session so relative paths start fresh.
    _currentDirectory = '.';
    _adapter = await _connector.connect(SftpConnectionConfig(
      host: host,
      port: port,
      user: user,
      pass: pass,
      privateKey: _privateKey,
      passphrase: _passphrase,
      timeout: Duration(seconds: timeout),
      onVerifyHostKey: _onVerifyHostKey,
      logger: logger,
    ));
    logger.log('Connected!');
    return true;
  }

  @override
  Future<bool> disconnect() async {
    logger.log('Disconnecting...');
    try {
      await _adapter?.close();
    } catch (e) {
      logger.log('Error while closing the SFTP session (ignored): $e');
    }
    _adapter = null;
    _currentDirectory = '.';
    logger.log('Disconnected!');
    return true;
  }

  @override
  Future<String> currentDirectory() async => _currentDirectory;

  @override
  Future<bool> changeDirectory(String sDirectory) async {
    final String target = _resolve(sDirectory);
    try {
      final SftpFileStat stat = await _sftp.stat(target);
      if (!stat.isDirectory) return false;
      _currentDirectory = target;
      return true;
    } catch (e) {
      logger.log('Cannot change directory to $target: $e');
      return false;
    }
  }

  @override
  Future<List<FTPEntry>> listDirectoryContent([String? sDirectory]) {
    return _sftp.listdir(_resolve(sDirectory));
  }

  @override
  Future<bool> makeDirectory(String sDirectory) async {
    try {
      await _sftp.mkdir(_resolve(sDirectory));
      return true;
    } catch (e) {
      logger.log('Cannot create directory $sDirectory: $e');
      return false;
    }
  }

  @override
  Future<bool> deleteDirectory(String sDirectory) async {
    try {
      await _sftp.rmdir(_resolve(sDirectory));
      return true;
    } catch (e) {
      logger.log('Cannot delete directory $sDirectory: $e');
      return false;
    }
  }

  @override
  Future<bool> deleteNonEmptyDirectory(String sDirectory) async {
    try {
      return await _deleteNonEmptyDirectory(_resolve(sDirectory));
    } catch (e) {
      logger.log('Cannot delete directory $sDirectory: $e');
      return false;
    }
  }

  Future<bool> _deleteNonEmptyDirectory(String target) async {
    final List<FTPEntry> content = await listDirectoryContent(target);
    for (final FTPEntry entry in content) {
      final String childPath = p.posix.join(target, entry.name);
      if (entry.type == FTPEntryType.dir) {
        if (!await _deleteNonEmptyDirectory(childPath)) {
          throw FTPConnectException("Couldn't delete folder ${entry.name}");
        }
      } else {
        if (!await deleteFile(childPath)) {
          throw FTPConnectException("Couldn't delete file ${entry.name}");
        }
      }
    }
    return deleteDirectory(target);
  }

  @override
  Future<bool> checkFolderExistence(String pDirectory) async {
    try {
      final SftpFileStat stat = await _sftp.stat(_resolve(pDirectory));
      return stat.isDirectory;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> createFolderIfNotExist(String pDirectory) async {
    if (await checkFolderExistence(pDirectory)) return true;
    return makeDirectory(pDirectory);
  }

  @override
  Future<bool> rename(String sOldName, String sNewName) async {
    try {
      await _sftp.rename(_resolve(sOldName), _resolve(sNewName));
      return true;
    } catch (e) {
      logger.log('Cannot rename $sOldName to $sNewName: $e');
      return false;
    }
  }

  @override
  Future<bool> deleteFile(String sFilename) async {
    try {
      await _sftp.remove(_resolve(sFilename));
      return true;
    } catch (e) {
      logger.log('Cannot delete file $sFilename: $e');
      return false;
    }
  }

  @override
  Future<bool> existFile(String sFilename) async =>
      await sizeFile(sFilename) != -1;

  @override
  Future<int> sizeFile(String sFilename) async {
    try {
      final SftpFileStat stat = await _sftp.stat(_resolve(sFilename));
      return stat.size ?? -1;
    } catch (_) {
      return -1;
    }
  }

  @override
  Future<bool> uploadFile(
    File fFile, {
    String? sRemoteName,
    FileProgress? onProgress,
  }) async {
    logger.log('Upload File: ${fFile.path}');
    final String remoteName = (sRemoteName == null || sRemoteName.isEmpty)
        ? p.basename(fFile.path)
        : sRemoteName;
    return _upload(
      remoteName,
      await fFile.length(),
      fFile.openRead().cast<Uint8List>(),
      onProgress: onProgress,
    );
  }

  @override
  Future<bool> downloadFile(
    String sRemoteName,
    File fFile, {
    FileProgress? onProgress,
  }) async {
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

  Future<bool> _upload(
    String sRemoteName,
    int total,
    Stream<Uint8List> source, {
    FileProgress? onProgress,
  }) async {
    await _sftp.writeFile(
      _resolve(sRemoteName),
      source,
      onProgress: onProgress == null
          ? null
          : (int sent) => onProgress(Utils.percent(sent, total), sent, total),
    );
    logger.log('File Uploaded!');
    return true;
  }

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

  Future<void> _download(
    String sRemoteName,
    void Function(Uint8List chunk) onChunk, {
    FileProgress? onProgress,
  }) async {
    final int total = await sizeFile(sRemoteName);
    if (total == -1) {
      throw FTPConnectException('Remote File $sRemoteName does not exist!');
    }
    int read = 0;
    await for (final Uint8List chunk in _sftp.readFile(_resolve(sRemoteName))) {
      onChunk(chunk);
      if (onProgress != null) {
        read += chunk.length;
        onProgress(Utils.percent(read, total), read, total);
      }
    }
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
