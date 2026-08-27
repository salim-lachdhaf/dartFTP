library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:ftpconnect/ftpconnect_web.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

/// Offline tests exercising the real [FtpWebClient] end to end through an
/// injected [MockClient]. No network and no `dart:io` are involved, which is
/// exactly how the client behaves on the web platform.
void main() {
  const String baseUrl = 'https://me.test.ftpweb.com';
  const FtpWebRoutes routes = FtpWebRoutes();

  String pathOf(http.BaseRequest req) =>
      req.url.path.replaceAll(RegExp(r'^/+'), '');

  FtpWebClient clientWith(MockClient mock) => FtpWebClient(
        baseUrl: baseUrl,
        host: 'ftp.example.com',
        user: 'user',
        pass: 'pass',
        api: WebApiClient(baseUrl: baseUrl, client: mock),
      );

  MockClient jsonServer(
      Map<String, dynamic> Function(String path, dynamic body) handler) {
    return MockClient((http.Request req) async {
      final dynamic body = req.body.isEmpty ? {} : jsonDecode(req.body);
      final Map<String, dynamic> res = handler(pathOf(req), body);
      final int status = (res.remove('__status') as int?) ?? 200;
      return http.Response(jsonEncode(res), status,
          headers: {'content-type': 'application/json'});
    });
  }

  Future<FtpWebClient> connected(MockClient mock) async {
    final FtpWebClient c = clientWith(mock);
    await c.connect();
    return c;
  }

  group('connection', () {
    test('connect stores the returned session id', () async {
      final client = clientWith(jsonServer((path, body) {
        expect(path, routes.connect);
        expect(body['protocol'], 'ftp');
        return {'session_id': 'abc123'};
      }));
      expect(await client.connect(), isTrue);
      expect(client.sessionId, 'abc123');
    });

    test('connect throws when no session id is returned', () {
      final client = clientWith(jsonServer((path, body) => {'error': 'nope'}));
      expect(() => client.connect(), throwsA(isA<FTPConnectException>()));
    });

    test('operations before connect throw', () {
      final client = clientWith(jsonServer((path, body) => {}));
      expect(
          () => client.currentDirectory(), throwsA(isA<FTPConnectException>()));
    });

    test('disconnect clears the session', () async {
      final client =
          await connected(jsonServer((path, body) => {'session_id': 's'}));
      expect(await client.disconnect(), isTrue);
      expect(client.sessionId, isNull);
    });

    test('baseUrl defaults to the proxy when omitted', () {
      final client = FtpWebClient(host: 'ftp.example.com');
      expect(client.baseUrl, 'https://me.test.ftpweb.com');
      expect(client.baseUrl, FtpWebClient.defaultBaseUrl);
    });
  });

  group('directory operations', () {
    test('listDirectoryContent maps entries', () async {
      final client = await connected(jsonServer((path, body) {
        if (path == routes.connect) return {'session_id': 's'};
        expect(path, routes.list);
        return {
          'entries': [
            {'name': 'a.txt', 'type': 'file', 'size': 12},
            {'name': 'sub', 'type': 'dir'},
          ],
        };
      }));
      final entries = await client.listDirectoryContent('/pub');
      expect(entries, hasLength(2));
      expect(entries[0].name, 'a.txt');
      expect(entries[0].type, FTPEntryType.file);
      expect(entries[0].size, 12);
      expect(entries[1].type, FTPEntryType.dir);
    });

    test('currentDirectory reads the path', () async {
      final client = await connected(jsonServer((path, body) {
        if (path == routes.connect) return {'session_id': 's'};
        return {'path': '/home/user'};
      }));
      expect(await client.currentDirectory(), '/home/user');
    });

    test('changeDirectory returns false on server error', () async {
      final client = await connected(jsonServer((path, body) {
        if (path == routes.connect) return {'session_id': 's'};
        return {'__status': 500, 'error': 'no such dir'};
      }));
      expect(await client.changeDirectory('/missing'), isFalse);
    });

    test('makeDirectory succeeds on 2xx', () async {
      final client = await connected(jsonServer((path, body) {
        if (path == routes.connect) return {'session_id': 's'};
        expect(path, routes.makeDirectory);
        return {'success': true};
      }));
      expect(await client.makeDirectory('newdir'), isTrue);
    });
  });

  group('file operations', () {
    test('sizeFile returns -1 when missing', () async {
      final client = await connected(jsonServer((path, body) {
        if (path == routes.connect) return {'session_id': 's'};
        return {'__status': 404, 'error': 'not found'};
      }));
      expect(await client.sizeFile('none.txt'), -1);
    });

    test('existFile reflects server answer', () async {
      final client = await connected(jsonServer((path, body) {
        if (path == routes.connect) return {'session_id': 's'};
        return {'exists': true};
      }));
      expect(await client.existFile('there.txt'), isTrue);
    });

    test('rename posts from/to', () async {
      final client = await connected(jsonServer((path, body) {
        if (path == routes.connect) return {'session_id': 's'};
        expect(path, routes.rename);
        expect(body['from'], 'old.txt');
        expect(body['to'], 'new.txt');
        return {'success': true};
      }));
      expect(await client.rename('old.txt', 'new.txt'), isTrue);
    });

    test('uploadData sends multipart and reports progress', () async {
      double? lastPercent;
      final mock = MockClient((http.Request req) async {
        if (pathOf(req) == routes.connect) {
          return http.Response(jsonEncode({'session_id': 's'}), 200,
              headers: {'content-type': 'application/json'});
        }
        expect(pathOf(req), routes.upload);
        expect(req.headers['content-type'], contains('multipart/form-data'));
        return http.Response(jsonEncode({'success': true}), 200,
            headers: {'content-type': 'application/json'});
      });
      final client = await connected(mock);
      final data = Uint8List.fromList(utf8.encode('payload'));
      final ok = await client.uploadData(data, 'f.txt',
          onProgress: (p, sent, total) => lastPercent = p);
      expect(ok, isTrue);
      expect(lastPercent, 100);
    });

    test('downloadToBytes returns raw body bytes', () async {
      final payload = Uint8List.fromList(utf8.encode('remote-content'));
      final mock = MockClient((http.Request req) async {
        if (pathOf(req) == routes.connect) {
          return http.Response(jsonEncode({'session_id': 's'}), 200,
              headers: {'content-type': 'application/json'});
        }
        expect(pathOf(req), routes.download);
        return http.Response.bytes(payload, 200);
      });
      final client = await connected(mock);
      final bytes = await client.downloadToBytes('remote.txt');
      expect(bytes, equals(payload));
    });
  });
}
