import 'dart:async';
import 'dart:typed_data';

import 'package:ftpconnect/ftpconnect.dart';
import 'package:path/path.dart' as p;

import 'virtual_file_system.dart';

/// A [SftpConnector] that yields an in-memory [SftpAdapter] backed by a
/// [VirtualFileSystem], used to drive the *real* [SFTPConnect] client in tests.
class FakeSftpConnector implements SftpConnector {
  final VirtualFileSystem fs;
  final bool throwOnConnect;

  FakeSftpConnector({VirtualFileSystem? fs, this.throwOnConnect = false})
      : fs = fs ?? VirtualFileSystem();

  @override
  Future<SftpAdapter> connect(SftpConnectionConfig config) async {
    if (throwOnConnect) {
      throw const FTPConnectException('Could not connect', 'refused');
    }
    return FakeSftpAdapter(fs);
  }
}

/// In-memory [SftpAdapter] backed by a [VirtualFileSystem].
class FakeSftpAdapter implements SftpAdapter {
  final VirtualFileSystem fs;
  bool closed = false;

  FakeSftpAdapter(this.fs);

  /// The real SSH server resolves relative paths against the login home
  /// directory. This VFS is rooted at `/`, so map `.`/relative paths to it.
  String _r(String path) {
    if (path.isEmpty || path == '.') return '/';
    return p.posix.isAbsolute(path)
        ? p.posix.normalize(path)
        : p.posix.normalize('/$path');
  }

  @override
  Future<SftpFileStat> stat(String path) async {
    path = _r(path);
    if (fs.isDirectory(path)) {
      return const SftpFileStat(isDirectory: true);
    }
    final int? size = fs.fileSize(path);
    if (size == null) {
      throw const FTPConnectException('No such file', 'stat failed');
    }
    return SftpFileStat(isDirectory: false, size: size);
  }

  @override
  Future<List<FTPEntry>> listdir(String path) async {
    path = _r(path);
    if (!fs.isDirectory(path)) {
      throw const FTPConnectException('No such directory', 'listdir failed');
    }
    return fs.list(path).map((VfsEntry e) {
      return FTPEntry.details(
        name: e.name,
        type: e.isDirectory ? FTPEntryType.dir : FTPEntryType.file,
        size: e.isDirectory ? null : e.size,
      );
    }).toList();
  }

  @override
  Future<void> mkdir(String path) async {
    if (!fs.createDirectory(_r(path))) {
      throw const FTPConnectException('mkdir failed');
    }
  }

  @override
  Future<void> rmdir(String path) async {
    if (!fs.removeEmptyDirectory(_r(path))) {
      throw const FTPConnectException('rmdir failed');
    }
  }

  @override
  Future<void> remove(String path) async {
    if (!fs.removeFile(_r(path))) {
      throw const FTPConnectException('remove failed');
    }
  }

  @override
  Future<void> rename(String from, String to) async {
    if (!fs.rename(_r(from), _r(to))) {
      throw const FTPConnectException('rename failed');
    }
  }

  @override
  Future<void> writeFile(
    String path,
    Stream<Uint8List> data, {
    void Function(int totalSent)? onProgress,
  }) async {
    path = _r(path);
    final List<int> buffer = <int>[];
    await for (final Uint8List chunk in data) {
      buffer.addAll(chunk);
      onProgress?.call(buffer.length);
    }
    if (!fs.writeFile(path, buffer)) {
      throw FTPConnectException('write failed for $path');
    }
  }

  @override
  Stream<Uint8List> readFile(String path) async* {
    final List<int>? bytes = fs.readFile(_r(path));
    if (bytes == null) {
      throw FTPConnectException('read failed for $path');
    }
    // Emit in small chunks to exercise the streaming/progress path.
    const int chunkSize = 8;
    for (int i = 0; i < bytes.length; i += chunkSize) {
      final int end =
          (i + chunkSize) > bytes.length ? bytes.length : i + chunkSize;
      yield Uint8List.fromList(bytes.sublist(i, end));
    }
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

/// Convenience helper so tests can reference posix joins concisely.
String posixJoin(String a, String b) => p.posix.join(a, b);
