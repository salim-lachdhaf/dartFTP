import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart' show SSHHostkeyVerifyHandler;

import '../domain/entities/ftp_entry.dart';
import '../domain/logger.dart';

/// Lightweight, transport-agnostic view of a remote entry's attributes.
class SftpFileStat {
  final bool isDirectory;
  final bool isSymbolicLink;
  final int? size;

  const SftpFileStat({
    required this.isDirectory,
    this.isSymbolicLink = false,
    this.size,
  });
}

/// The set of SFTP operations the [SFTPConnect] client relies on.
///
/// This is the abstraction that makes the SFTP client testable: the real
/// implementation wraps the `dartssh2` package, while tests provide an in-memory
/// fake. Method signatures are intentionally free of any `dartssh2` type.
abstract class SftpAdapter {
  /// Returns the attributes of [path]. Throws when [path] does not exist.
  Future<SftpFileStat> stat(String path);

  /// Lists the content of the directory [path] (excluding `.` and `..`).
  Future<List<FTPEntry>> listdir(String path);

  /// Creates the directory [path].
  Future<void> mkdir(String path);

  /// Removes the empty directory [path].
  Future<void> rmdir(String path);

  /// Removes the file [path].
  Future<void> remove(String path);

  /// Renames/moves [from] to [to].
  Future<void> rename(String from, String to);

  /// Writes [data] to the remote file [path], overwriting it.
  ///
  /// [onProgress] is called with the running number of bytes sent.
  Future<void> writeFile(
    String path,
    Stream<Uint8List> data, {
    void Function(int totalSent)? onProgress,
  });

  /// Reads the remote file [path] as a stream of chunks.
  Stream<Uint8List> readFile(String path);

  /// Closes the SFTP session and the underlying connection.
  Future<void> close();
}

/// Immutable configuration used to open an SFTP session.
class SftpConnectionConfig {
  final String host;
  final int port;
  final String user;
  final String pass;
  final String? privateKey;
  final String? passphrase;
  final Duration timeout;
  final SSHHostkeyVerifyHandler? onVerifyHostKey;
  final Logger logger;

  const SftpConnectionConfig({
    required this.host,
    required this.port,
    required this.user,
    required this.pass,
    required this.timeout,
    required this.logger,
    this.privateKey,
    this.passphrase,
    this.onVerifyHostKey,
  });
}

/// Opens an [SftpAdapter] from a [SftpConnectionConfig].
///
/// Injecting a fake connector replaces the whole SSH/SFTP stack.
abstract class SftpConnector {
  Future<SftpAdapter> connect(SftpConnectionConfig config);
}
