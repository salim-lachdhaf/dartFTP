import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../config/transfer_config.dart';
import '../domain/entities/ftp_entry.dart';
import '../domain/enums.dart';
import '../domain/exceptions.dart';
import '../domain/file_transfer_protocol.dart';
import '../domain/logger.dart';
import '../domain/progress.dart';
import '../utils/utils.dart';
import 'web_api_client.dart';
import 'web_api_routes.dart';

/// A web-safe FTP/SFTP client.
///
/// Browsers (and Flutter Web) cannot open raw FTP or SSH sockets, so this
/// client never touches `dart:io`. Instead it delegates every operation to a
/// remote HTTP API (a FastAPI server) that performs the real FTP/SFTP work and
/// relays the result back.
///
/// It mirrors the byte/path oriented subset of the package's
/// `FileTransferClient` contract. `dart:io` `File`/`Directory` based helpers are
/// intentionally omitted because they don't exist on the web — use
/// [uploadData] / [downloadToBytes] with `Uint8List` instead.
///
/// Like [FTPConnect]/[SFTPConnect], a single [FtpWebClient] wraps one remote
/// session that has its own current working directory server-side.
/// `checkFolderExistence` never navigates: it lists the parent directory and
/// looks for a matching entry. `createFolderIfNotExist` builds on it. A
/// single instance is still not safe to drive with overlapping concurrent
/// calls — await each call in turn, or use a separate session per concurrent
/// task.
///
/// ```dart
/// final client = FtpWebConnect(
///   'https://me.test.ftpweb.com',
///   host: 'ftp.example.com',
///   user: 'user',
///   pass: 'pass',
///   protocol: WebProtocol.sftp,
/// );
/// await client.connect();
/// final bytes = await client.downloadToBytes('remote/file.txt');
/// await client.disconnect();
/// ```
class FtpWebClient implements FileTransferProtocol {
  /// Default proxy/API server URL used when none is supplied.
  static const String defaultBaseUrl = 'https://me.test.ftpweb.com';

  /// Base URL of the API server, e.g. `https://me.test.ftpweb.com`.
  final String baseUrl;

  /// Remote FTP/SFTP host the server should connect to.
  final String host;

  /// Remote port. When `null` the server picks the protocol default.
  final int? port;

  final String user;
  final String pass;

  /// Optional private key content for SFTP key-based auth.
  final String? privateKey;

  /// Optional passphrase protecting [privateKey].
  final String? passphrase;

  /// Which protocol the server should speak on our behalf.
  final WebProtocol protocol;

  final Logger logger;
  final FtpWebRoutes routes;
  final WebApiClient _api;

  String? _sessionId;

  /// Create a web client instance.
  ///
  /// [baseUrl]: Base URL of the proxy/API server. Defaults to
  /// [defaultBaseUrl] (`https://me.test.ftpweb.com`).
  /// [host]/[port]/[user]/[pass]: Remote FTP/SFTP credentials forwarded to the
  /// server on [connect].
  /// [protocol]: Remote protocol (defaults to plain FTP).
  /// [routes]: Endpoint names (see [FtpWebRoutes]; defaults are placeholders).
  /// [headers]: Extra HTTP headers (e.g. an API `Authorization` token).
  /// [api]: Injectable low-level HTTP client (used for testing).
  FtpWebClient({
    this.baseUrl = defaultBaseUrl,
    required this.host,
    this.port,
    this.user = 'anonymous',
    this.pass = '',
    this.privateKey,
    this.passphrase,
    this.protocol = WebProtocol.ftp,
    int timeout = 30,
    bool showLog = false,
    Logger? logger,
    FtpWebRoutes? routes,
    Map<String, String>? headers,
    WebApiClient? api,
  })  : logger = logger ?? Logger(isEnabled: showLog),
        routes = routes ?? const FtpWebRoutes(),
        _api = api ??
            WebApiClient(
              baseUrl: baseUrl,
              logger: logger ?? Logger(isEnabled: showLog),
              timeout: Duration(seconds: timeout),
              defaultHeaders: headers,
            );

  /// Create a web client from a [WebConfig].
  factory FtpWebClient.fromConfig(WebConfig config) => FtpWebClient(
        baseUrl: config.baseUrl,
        host: config.host,
        port: config.port,
        user: config.user,
        pass: config.pass,
        privateKey: config.privateKey,
        passphrase: config.passphrase,
        protocol: config.protocol,
        timeout: config.timeout,
        showLog: config.showLog,
        logger: config.logger,
        routes: config.routes,
        headers: config.headers,
      );

  /// The identifier of the currently open remote session (if any).
  String? get sessionId => _sessionId;

  String get _session {
    final String? id = _sessionId;
    if (id == null) {
      throw const FTPConnectException('Not connected. Call connect() first.');
    }
    return id;
  }

  Map<String, dynamic> _withSession([Map<String, dynamic>? extra]) => {
        'session_id': _session,
        if (extra != null) ...extra,
      };

  /// Open a session on the remote server and authenticate.
  @override
  Future<bool> connect() async {
    logger.log('Connecting to $host via $baseUrl ...');
    final dynamic res = await _api.postJson(routes.connect, {
      'protocol': protocol.wireName,
      'host': host,
      if (port != null) 'port': port,
      'user': user,
      'pass': pass,
      if (privateKey != null) 'private_key': privateKey,
      if (passphrase != null) 'passphrase': passphrase,
    });
    final String? id = _extractString(
        res, const ['session_id', 'sessionId', 'session', 'id', 'token']);
    if (id == null || id.isEmpty) {
      throw FTPConnectException(
          'Server did not return a session id', res.toString());
    }
    _sessionId = id;
    logger.log('Connected! session=$id');
    return true;
  }

  /// Close the remote session.
  @override
  Future<bool> disconnect() async {
    if (_sessionId == null) return true;
    logger.log('Disconnecting...');
    try {
      await _api.postJson(routes.disconnect, _withSession());
    } catch (e) {
      // Keep the session id so a caller can retry disconnect(): unlike a
      // local socket, the remote session is not implicitly closed by giving
      // up on it, so discarding the id here would leak it server-side with
      // no way to close it later.
      logger.log('Disconnect error: $e');
      return false;
    }
    _sessionId = null;
    logger.log('Disconnected!');
    return true;
  }

  /// Detailed content of the remote directory ([sDirectory] or the current one).
  @override
  Future<List<FTPEntry>> listDirectoryContent([String? sDirectory]) async {
    final dynamic res = await _api.postJson(
      routes.list,
      _withSession({if (sDirectory != null) 'path': sDirectory}),
    );
    final List<dynamic> rawEntries =
        _extractList(res, const ['entries', 'data', 'items', 'files']);
    return rawEntries
        .whereType<Map>()
        .map((e) => _entryFromJson(e.cast<String, dynamic>()))
        .toList(growable: false);
  }

  /// Current working directory of the session.
  @override
  Future<String> currentDirectory() async {
    final dynamic res =
        await _api.postJson(routes.currentDirectory, _withSession());
    if (res is String) return res;
    return _extractString(res, const ['path', 'cwd', 'directory', 'pwd']) ??
        '/';
  }

  /// Change into [sDirectory]. Returns `false` when the server rejects it.
  @override
  Future<bool> changeDirectory(String sDirectory) async {
    try {
      final dynamic res = await _api.postJson(
          routes.changeDirectory, _withSession({'path': sDirectory}));
      return _extractBool(res, const ['success', 'ok', 'changed'],
          defaultValue: true);
    } catch (e) {
      logger.log('Cannot change directory to $sDirectory: $e');
      return false;
    }
  }

  /// Create the directory [sDirectory].
  @override
  Future<bool> makeDirectory(String sDirectory) async {
    try {
      final dynamic res = await _api.postJson(
          routes.makeDirectory, _withSession({'path': sDirectory}));
      return _extractBool(res, const ['success', 'ok', 'created'],
          defaultValue: true);
    } catch (e) {
      logger.log('Cannot create directory $sDirectory: $e');
      return false;
    }
  }

  /// Remove the empty directory [sDirectory].
  @override
  Future<bool> deleteDirectory(String sDirectory) async {
    try {
      final dynamic res = await _api.postJson(
          routes.removeDirectory, _withSession({'path': sDirectory}));
      return _extractBool(res, const ['success', 'ok', 'deleted'],
          defaultValue: true);
    } catch (e) {
      logger.log('Cannot delete directory $sDirectory: $e');
      return false;
    }
  }

  /// Delete the directory [sDirectory] and all of its content recursively,
  /// even when it is not empty, returning `false` (instead of throwing) on
  /// failure.
  @override
  Future<bool> deleteNonEmptyDirectory(String sDirectory) async {
    try {
      return await _deleteNonEmptyDirectory(sDirectory);
    } catch (e) {
      logger.log('Cannot delete directory $sDirectory: $e');
      return false;
    }
  }

  Future<bool> _deleteNonEmptyDirectory(String sDirectory) async {
    final List<FTPEntry> content = await listDirectoryContent(sDirectory);
    for (final FTPEntry entry in content) {
      final String childPath = p.posix.join(sDirectory, entry.name);
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
    return deleteDirectory(sDirectory);
  }

  /// Rename/move [sOldName] to [sNewName].
  @override
  Future<bool> rename(String sOldName, String sNewName) async {
    try {
      final dynamic res = await _api.postJson(
        routes.rename,
        _withSession({'from': sOldName, 'to': sNewName}),
      );
      return _extractBool(res, const ['success', 'ok', 'renamed'],
          defaultValue: true);
    } catch (e) {
      logger.log('Cannot rename $sOldName to $sNewName: $e');
      return false;
    }
  }

  /// Delete the file [sFilename].
  @override
  Future<bool> deleteFile(String sFilename) async {
    try {
      final dynamic res = await _api.postJson(
          routes.deleteFile, _withSession({'path': sFilename}));
      return _extractBool(res, const ['success', 'ok', 'deleted'],
          defaultValue: true);
    } catch (e) {
      logger.log('Cannot delete file $sFilename: $e');
      return false;
    }
  }

  /// Whether the file [sFilename] exists on the server.
  @override
  Future<bool> existFile(String sFilename) async {
    try {
      final dynamic res =
          await _api.postJson(routes.exists, _withSession({'path': sFilename}));
      return _extractBool(res, const ['exists', 'found', 'success'],
          defaultValue: false);
    } catch (e) {
      logger.log('Cannot check existence of $sFilename: $e');
      return false;
    }
  }

  /// Size of [sFilename] in bytes, or `-1` when it does not exist.
  @override
  Future<int> sizeFile(String sFilename) async {
    try {
      final dynamic res =
          await _api.postJson(routes.size, _withSession({'path': sFilename}));
      return _extractInt(res, const ['size', 'length', 'bytes']) ?? -1;
    } catch (e) {
      logger.log('Cannot get size of $sFilename: $e');
      return -1;
    }
  }

  /// Check the existence of the directory [pDirectory] without navigating
  /// into it: lists the *parent* directory and looks for a matching entry
  /// that isn't a plain file, leaving the session's current directory
  /// untouched.
  @override
  Future<bool> checkFolderExistence(String pDirectory) async {
    final String normalized = p.posix.normalize(pDirectory);
    if (normalized == '/' || normalized == '.' || normalized.isEmpty) {
      return true;
    }
    final String name = p.posix.basename(normalized);
    final String dirName = p.posix.dirname(normalized);
    final String? parent = dirName == '.' ? null : dirName;
    final List<FTPEntry> entries = await listDirectoryContent(parent);
    return entries.any((FTPEntry entry) =>
        entry.name == name && entry.type != FTPEntryType.file);
  }

  /// Create [pDirectory] if it does not already exist.
  @override
  Future<bool> createFolderIfNotExist(String pDirectory) async {
    if (await checkFolderExistence(pDirectory)) return true;
    return makeDirectory(pDirectory);
  }

  /// Upload the in-memory [data] to the remote path [sRemoteName].
  @override
  Future<bool> uploadData(
    Uint8List data,
    String sRemoteName, {
    FileProgress? onProgress,
  }) async {
    logger.log('Upload ${data.length} bytes to $sRemoteName');
    await _api.postMultipart(
      routes.upload,
      fields: {'session_id': _session, 'path': sRemoteName},
      bytes: data,
      filename: p.posix.basename(sRemoteName),
    );
    // The multipart request is atomic from the browser's perspective, so we
    // can only report 0% then 100%.
    if (onProgress != null) {
      onProgress(
          Utils.percent(data.length, data.length), data.length, data.length);
    }
    logger.log('File Uploaded!');
    return true;
  }

  /// Download the remote file [sRemoteName] and return its bytes.
  @override
  Future<Uint8List> downloadToBytes(
    String sRemoteName, {
    FileProgress? onProgress,
  }) async {
    logger.log('Download $sRemoteName to memory');
    final Uint8List bytes = await _api.postForBytes(
      routes.download,
      _withSession({'path': sRemoteName}),
    );
    if (onProgress != null) {
      onProgress(100, bytes.length, bytes.length);
    }
    logger.log('File Downloaded! (${bytes.length} bytes)');
    return bytes;
  }

  /// Releases the underlying HTTP resources. Call once you're done with the
  /// client (does not close the remote session — use [disconnect] for that).
  void dispose() => _api.close();

  // --- response parsing helpers ---------------------------------------------

  FTPEntry _entryFromJson(Map<String, dynamic> json) {
    final String name = (json['name'] ?? json['filename'] ?? '').toString();
    final FTPEntryType type = _parseType(json['type']);
    DateTime? modify;
    final dynamic rawModify =
        json['modify'] ?? json['modified'] ?? json['mtime'];
    if (rawModify is String) {
      modify = DateTime.tryParse(rawModify);
    } else if (rawModify is int) {
      modify = DateTime.fromMillisecondsSinceEpoch(
          rawModify > 1000000000000 ? rawModify : rawModify * 1000);
    }
    return FTPEntry.details(
      name: name,
      type: type,
      size: _asInt(json['size'] ?? json['length']),
      modifyTime: modify,
      permission: json['permission']?.toString() ?? json['perm']?.toString(),
      owner: json['owner']?.toString(),
      group: json['group']?.toString(),
    );
  }

  FTPEntryType _parseType(dynamic raw) {
    final String value = raw?.toString().toLowerCase() ?? '';
    if (value.startsWith('d') ||
        value == 'dir' ||
        value == 'directory' ||
        value == 'folder') {
      return FTPEntryType.dir;
    }
    if (value.startsWith('l') || value == 'link' || value == 'symlink') {
      return FTPEntryType.link;
    }
    if (value.startsWith('f') || value == 'file') {
      return FTPEntryType.file;
    }
    return FTPEntryType.unknown;
  }

  String? _extractString(dynamic res, List<String> keys) {
    if (res is Map) {
      for (final String key in keys) {
        final dynamic v = res[key];
        if (v != null) return v.toString();
      }
      final dynamic data = res['data'];
      if (data is Map) return _extractString(data, keys);
    }
    return null;
  }

  bool _extractBool(dynamic res, List<String> keys,
      {required bool defaultValue}) {
    if (res is bool) return res;
    if (res is Map) {
      for (final String key in keys) {
        final dynamic v = res[key];
        if (v is bool) return v;
        if (v is String) return v.toLowerCase() == 'true' || v == '1';
        if (v is num) return v != 0;
      }
      final dynamic data = res['data'];
      if (data is Map) {
        return _extractBool(data, keys, defaultValue: defaultValue);
      }
    }
    logger.log('Response did not contain any of $keys; '
        'assuming $defaultValue. Response: $res');
    return defaultValue;
  }

  int? _extractInt(dynamic res, List<String> keys) {
    if (res is num) return res.toInt();
    if (res is Map) {
      for (final String key in keys) {
        final int? v = _asInt(res[key]);
        if (v != null) return v;
      }
      final dynamic data = res['data'];
      if (data is Map) return _extractInt(data, keys);
    }
    return null;
  }

  List<dynamic> _extractList(dynamic res, List<String> keys) {
    if (res is List) return res;
    if (res is Map) {
      for (final String key in keys) {
        final dynamic v = res[key];
        if (v is List) return v;
      }
      final dynamic data = res['data'];
      if (data is Map || data is List) return _extractList(data, keys);
    }
    return const [];
  }

  int? _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }
}
