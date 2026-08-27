import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ftpconnect/ftpconnect.dart';
import 'package:path/path.dart' as p;

import 'virtual_file_system.dart';

/// An in-memory FTP server used to drive the *real* [FTPConnect] client in
/// tests.
///
/// It implements the [SocketConnector] port: the first [connect] returns the
/// control channel, subsequent [connect] calls (to the port advertised by
/// `PASV`) return the pending data channel. The server reacts to the FTP
/// commands the real client writes and answers with realistic replies, backed
/// by a [VirtualFileSystem].
class FakeFtpServer implements SocketConnector {
  final VirtualFileSystem fs;
  final String? validUser;
  final String? validPass;
  final bool throwOnConnect;

  FakeFtpServer({
    VirtualFileSystem? fs,
    this.validUser,
    this.validPass,
    this.throwOnConnect = false,
  }) : fs = fs ?? VirtualFileSystem();

  _FakeSocket? _control;
  _FakeSocket? _pendingData;

  String _cwd = '/';
  String? _renameFrom;
  int _dataPort = 40000;

  @override
  Future<RawSocketConnection> connect(
    String host,
    int port, {
    required bool secure,
    required Duration timeout,
  }) async {
    if (throwOnConnect) {
      throw const SocketExceptionLike('connection refused');
    }
    if (_control == null) {
      final _FakeSocket control = _FakeSocket();
      control.onWrite = (data) => _handleCommand(control, data);
      _control = control;
      // Welcome banner (buffered until the client's reader subscribes).
      control.emitLine('220 Welcome to FakeFtpServer');
      return control;
    }
    // Data connection.
    final _FakeSocket? data = _pendingData;
    if (data == null) {
      throw const SocketExceptionLike('no passive data connection prepared');
    }
    return data;
  }

  // --- command handling ---------------------------------------------------

  void _handleCommand(_FakeSocket control, List<int> raw) {
    final String line = utf8.decode(raw).trim();
    final int spaceIndex = line.indexOf(' ');
    final String keyword =
        (spaceIndex == -1 ? line : line.substring(0, spaceIndex)).toUpperCase();
    final String arg = spaceIndex == -1 ? '' : line.substring(spaceIndex + 1);

    switch (keyword) {
      case 'USER':
        control.emitLine('331 Please specify the password');
        break;
      case 'PASS':
        control.emitLine(
            _checkLogin(arg) ? '230 Login successful' : '530 Login incorrect');
        break;
      case 'ACCT':
        control.emitLine('230 Account accepted');
        break;
      case 'TYPE':
        control.emitLine('200 Type set to $arg');
        break;
      case 'PBSZ':
        control.emitLine('200 PBSZ=0');
        break;
      case 'PROT':
        control.emitLine('200 Protection level set');
        break;
      case 'PWD':
        control.emitLine('257 "$_cwd" is the current directory');
        break;
      case 'CWD':
        _handleCwd(control, arg);
        break;
      case 'MKD':
        control.emitLine(fs.createDirectory(_abs(arg))
            ? '257 "$arg" created'
            : '550 Create directory operation failed');
        break;
      case 'RMD':
        control.emitLine(fs.removeEmptyDirectory(_abs(arg))
            ? '250 Remove directory operation successful'
            : '550 Remove directory operation failed');
        break;
      case 'DELE':
        control.emitLine(fs.removeFile(_abs(arg))
            ? '250 Delete operation successful'
            : '550 Delete operation failed');
        break;
      case 'SIZE':
        _handleSize(control, arg);
        break;
      case 'RNFR':
        if (fs.exists(_abs(arg))) {
          _renameFrom = _abs(arg);
          control.emitLine('350 Ready for RNTO');
        } else {
          control.emitLine('550 RNFR failed');
        }
        break;
      case 'RNTO':
        final String? from = _renameFrom;
        _renameFrom = null;
        control.emitLine((from != null && fs.rename(from, _abs(arg)))
            ? '250 Rename successful'
            : '550 Rename failed');
        break;
      case 'PASV':
        _handlePasv(control);
        break;
      case 'RETR':
        _handleRetr(control, arg);
        break;
      case 'STOR':
        _handleStor(control, arg);
        break;
      case 'MLSD':
      case 'LIST':
      case 'NLST':
        _handleList(control, keyword, arg);
        break;
      case 'QUIT':
        control.emitLine('221 Goodbye');
        break;
      default:
        control.emitLine('502 Command not implemented');
    }
  }

  bool _checkLogin(String pass) {
    if (validPass == null) return true;
    return pass == validPass;
  }

  void _handleCwd(_FakeSocket control, String arg) {
    final String target = _abs(arg);
    if (fs.isDirectory(target)) {
      _cwd = target;
      control.emitLine('250 Directory successfully changed');
    } else {
      control.emitLine('550 Failed to change directory');
    }
  }

  void _handleSize(_FakeSocket control, String arg) {
    final int? size = fs.fileSize(_abs(arg));
    control
        .emitLine(size != null ? '213 $size' : '550 Could not get file size');
  }

  void _handlePasv(_FakeSocket control) {
    final int port = _dataPort++;
    final _FakeSocket data = _FakeSocket();
    _pendingData = data;
    final int p1 = port ~/ 256;
    final int p2 = port % 256;
    control.emitLine('227 Entering Passive Mode (127,0,0,1,$p1,$p2)');
  }

  void _handleRetr(_FakeSocket control, String arg) {
    final List<int>? bytes = fs.readFile(_abs(arg));
    final _FakeSocket? data = _pendingData;
    if (bytes == null || data == null) {
      control.emitLine('550 Failed to open file');
      return;
    }
    control.emitLine('150 Opening data connection');
    data.emit(bytes);
    data.emitDone();
    control.emitLine('226 Transfer complete');
    _pendingData = null;
  }

  void _handleStor(_FakeSocket control, String arg) {
    final _FakeSocket? data = _pendingData;
    if (data == null) {
      control.emitLine('425 Use PASV first');
      return;
    }
    final String target = _abs(arg);
    control.emitLine('150 Ok to send data');
    data.onDestroy = () {
      fs.writeFile(target, data.written);
      control.emitLine('226 Transfer complete');
      _pendingData = null;
    };
  }

  void _handleList(_FakeSocket control, String keyword, String arg) {
    final _FakeSocket? data = _pendingData;
    if (data == null) {
      control.emitLine('425 Use PASV first');
      return;
    }
    final String target = arg.isEmpty ? _cwd : _abs(arg);
    final List<VfsEntry> entries = fs.list(target);
    final String body =
        entries.map((e) => _formatEntry(keyword, e)).join('\r\n');
    control.emitLine('150 Here comes the directory listing');
    data.emit(utf8.encode(body.isEmpty ? '' : '$body\r\n'));
    data.emitDone();
    control.emitLine('226 Directory send OK');
    _pendingData = null;
  }

  String _formatEntry(String keyword, VfsEntry e) {
    switch (keyword) {
      case 'NLST':
        return e.name;
      case 'LIST':
        final String flag = e.isDirectory ? 'd' : '-';
        final String perms = e.isDirectory ? 'rwxr-xr-x' : 'rw-r--r--';
        return '$flag$perms 1 owner group ${e.size} Jan 01 2020 ${e.name}';
      case 'MLSD':
      default:
        return e.isDirectory
            ? 'type=dir; ${e.name}'
            : 'type=file;size=${e.size}; ${e.name}';
    }
  }

  String _abs(String path) {
    if (path.isEmpty) return _cwd;
    if (p.posix.isAbsolute(path)) return p.posix.normalize(path);
    return p.posix.normalize(p.posix.join(_cwd, path));
  }
}

/// Minimal exception used by the fake connector to emulate socket failures.
class SocketExceptionLike implements Exception {
  final String message;
  const SocketExceptionLike(this.message);
  @override
  String toString() => 'SocketExceptionLike: $message';
}

/// In-memory [RawSocketConnection] used by [FakeFtpServer].
class _FakeSocket implements RawSocketConnection {
  final StreamController<Uint8List> _controller = StreamController<Uint8List>();
  final List<int> written = <int>[];

  void Function(List<int> data)? onWrite;
  void Function()? onDestroy;
  bool _destroyed = false;

  @override
  Stream<Uint8List> get inbound => _controller.stream;

  @override
  void add(List<int> data) {
    written.addAll(data);
    onWrite?.call(data);
  }

  @override
  Future<void> flush() async {}

  @override
  Future<RawSocketConnection> secure() async => this;

  @override
  Future<void> close() async {
    if (!_controller.isClosed) await _controller.close();
  }

  @override
  void destroy() {
    if (_destroyed) return;
    _destroyed = true;
    onDestroy?.call();
    if (!_controller.isClosed) _controller.close();
  }

  void emit(List<int> bytes) {
    if (!_controller.isClosed) _controller.add(Uint8List.fromList(bytes));
  }

  void emitLine(String line) => emit(utf8.encode('$line\r\n'));

  void emitDone() {
    if (!_controller.isClosed) _controller.close();
  }
}
