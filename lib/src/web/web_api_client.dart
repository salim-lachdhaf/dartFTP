import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../domain/exceptions.dart';
import '../domain/logger.dart';

/// Thin, transport-agnostic HTTP client used by [FtpWebConnect] to talk to the
/// remote FastAPI server.
///
/// It is intentionally free of any FTP/SFTP knowledge: it only knows how to
/// send JSON / multipart requests and how to download raw bytes. The underlying
/// [http.Client] is injectable, which keeps the web client fully testable
/// (a `MockClient` can drive it without a live server).
class WebApiClient {
  /// Base URL of the server, e.g. `https://me.test.ftpweb.com`.
  final String baseUrl;

  /// Timeout applied to every request.
  final Duration timeout;

  /// Extra headers sent with every request (e.g. an `Authorization` token).
  final Map<String, String> defaultHeaders;

  final Logger logger;
  final http.Client _client;

  WebApiClient({
    required String baseUrl,
    http.Client? client,
    Logger? logger,
    this.timeout = const Duration(seconds: 30),
    Map<String, String>? defaultHeaders,
  })  : baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
        _client = client ?? http.Client(),
        logger = logger ?? const Logger(),
        defaultHeaders = defaultHeaders ?? const {};

  Uri _uri(String path) =>
      Uri.parse('$baseUrl/${path.replaceAll(RegExp(r'^/+'), '')}');

  Map<String, String> _headers([Map<String, String>? extra]) => {
        ...defaultHeaders,
        if (extra != null) ...extra,
      };

  /// Sends a JSON `POST` request and returns the decoded JSON body.
  Future<dynamic> postJson(
    String path,
    Map<String, dynamic> body, {
    Map<String, String>? headers,
  }) async {
    final Uri uri = _uri(path);
    logger.log('POST $uri  body=$body');
    try {
      final http.Response res = await _client
          .post(
            uri,
            headers:
                _headers({'Content-Type': 'application/json', ...?headers}),
            body: jsonEncode(body),
          )
          .timeout(timeout);
      return _decode(res, uri);
    } on FTPConnectException {
      rethrow;
    } catch (e) {
      throw FTPConnectException('HTTP request to $uri failed', e.toString(), e);
    }
  }

  /// Uploads [bytes] using a multipart `POST` request and returns the decoded
  /// JSON body. [fields] are sent as additional form fields.
  Future<dynamic> postMultipart(
    String path, {
    required Map<String, String> fields,
    required Uint8List bytes,
    required String filename,
    String fileField = 'file',
    Map<String, String>? headers,
  }) async {
    final Uri uri = _uri(path);
    logger.log(
        'MULTIPART $uri  fields=$fields  file=$filename (${bytes.length} bytes)');
    try {
      final http.MultipartRequest request = http.MultipartRequest('POST', uri)
        ..headers.addAll(_headers(headers))
        ..fields.addAll(fields)
        ..files.add(
            http.MultipartFile.fromBytes(fileField, bytes, filename: filename));

      final http.StreamedResponse streamed =
          await _client.send(request).timeout(timeout);
      final http.Response res = await http.Response.fromStream(streamed);
      return _decode(res, uri);
    } on FTPConnectException {
      rethrow;
    } catch (e) {
      throw FTPConnectException('HTTP upload to $uri failed', e.toString(), e);
    }
  }

  /// Sends a JSON `POST` request and returns the raw response bytes (used to
  /// download a remote file).
  Future<Uint8List> postForBytes(
    String path,
    Map<String, dynamic> body, {
    Map<String, String>? headers,
  }) async {
    final Uri uri = _uri(path);
    logger.log('DOWNLOAD $uri  body=$body');
    try {
      final http.Response res = await _client
          .post(
            uri,
            headers:
                _headers({'Content-Type': 'application/json', ...?headers}),
            body: jsonEncode(body),
          )
          .timeout(timeout);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw FTPConnectException(
            'HTTP $uri returned ${res.statusCode}', _safeBody(res));
      }
      return res.bodyBytes;
    } on FTPConnectException {
      rethrow;
    } catch (e) {
      throw FTPConnectException(
          'HTTP download from $uri failed', e.toString(), e);
    }
  }

  dynamic _decode(http.Response res, Uri uri) {
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw FTPConnectException(
          'HTTP $uri returned ${res.statusCode}', _safeBody(res));
    }
    if (res.body.isEmpty) return <String, dynamic>{};
    try {
      return jsonDecode(res.body);
    } catch (_) {
      // Not JSON — return the raw text so callers can still use it.
      return res.body;
    }
  }

  String _safeBody(http.Response res) {
    try {
      return res.body;
    } catch (_) {
      return '';
    }
  }

  /// Closes the underlying HTTP client.
  void close() => _client.close();
}
