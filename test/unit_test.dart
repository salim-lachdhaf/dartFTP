library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ftpconnect/ftpconnect.dart';
import 'package:ftpconnect/src/ftp/ftp_response_reader.dart';
import 'package:ftpconnect/src/utils/utils.dart';
import 'package:test/test.dart';

/// A minimal [RawSocketConnection] that only replays a scripted byte stream.
class _ScriptedConnection implements RawSocketConnection {
  final StreamController<Uint8List> _controller = StreamController<Uint8List>();

  @override
  Stream<Uint8List> get inbound => _controller.stream;

  void feed(String text) =>
      _controller.add(Uint8List.fromList(utf8.encode(text)));

  void done() => _controller.close();

  @override
  void add(List<int> data) {}
  @override
  Future<void> flush() async {}
  @override
  Future<RawSocketConnection> secure() async => this;
  @override
  Future<void> close() async => _controller.close();
  @override
  void destroy() => _controller.close();
}

void main() {
  group('Utils.percent', () {
    test('computes a rounded percentage', () {
      expect(Utils.percent(50, 200), 25);
      expect(Utils.percent(1, 3), 33.33);
    });

    test('returns 100 for unknown/zero totals and never exceeds 100', () {
      expect(Utils.percent(10, 0), 100);
      expect(Utils.percent(200, 100), 100);
    });
  });

  group('Utils port/host parsing', () {
    test('parses a standard PASV response', () {
      const response = '227 Entering Passive Mode (192,168,8,36,8,75).';
      expect(Utils.parsePort(response, false), 2123);
      expect(Utils.parseHostPASV(response), '192.168.8.36');
    });

    test('parses an EPSV (extended passive) response', () {
      const response = '229 Entering Extended Passive Mode (|||6446|)';
      expect(Utils.parsePort(response, true), 6446);
      expect(Utils.parseHostPASV(response), isNull);
    });

    test('throws when the PASV response is malformed', () {
      expect(() => Utils.parsePortPASV('227 no parentheses here'),
          throwsA(isA<FTPConnectException>()));
    });

    test('throws when the EPSV response is malformed', () {
      expect(() => Utils.parsePortEPSV('229 no parentheses here'),
          throwsA(isA<FTPConnectException>()));
    });

    test('throws when the PASV response has too few segments', () {
      expect(() => Utils.parsePortPASV('227 Entering Passive Mode (192)'),
          throwsA(isA<FTPConnectException>()));
    });
  });

  group('FTPReply', () {
    test('isSuccessCode is true only for 2xx codes', () {
      expect(FTPReply(200, 'ok').isSuccessCode(), isTrue);
      expect(FTPReply(226, 'done').isSuccessCode(), isTrue);
      expect(FTPReply(299, 'ok').isSuccessCode(), isTrue);
      expect(FTPReply(150, 'opening').isSuccessCode(), isFalse);
      expect(FTPReply(331, 'need pass').isSuccessCode(), isFalse);
      expect(FTPReply(550, 'error').isSuccessCode(), isFalse);
    });
  });

  group('FTPEntry parsing', () {
    test('parses an MLSD line', () {
      final e = FTPEntry.parse(
          'type=file;size=1024;modify=20200101120000; report.txt',
          ListCommand.mlsd);
      expect(e.name, 'report.txt');
      expect(e.type, FTPEntryType.file);
      expect(e.size, 1024);
      expect(e.modifyTime, isNotNull);
    });

    test('parses an MLSD directory line', () {
      final e = FTPEntry.parse('type=dir; docs', ListCommand.mlsd);
      expect(e.name, 'docs');
      expect(e.type, FTPEntryType.dir);
    });

    test('parses a unix LIST line', () {
      final e = FTPEntry.parse(
          '-rw-r--r-- 1 owner group 213 Aug 26 2020 FileName.txt',
          ListCommand.list);
      expect(e.name, 'FileName.txt');
      expect(e.type, FTPEntryType.file);
      expect(e.size, 213);
      expect(e.permission, 'rw-r--r--');
    });

    test('parses a windows/SII LIST line', () {
      final e = FTPEntry.parse(
          '02-11-15  03:05PM       <DIR>          0 myFolder',
          ListCommand.list);
      expect(e.name, 'myFolder');
      expect(e.type, FTPEntryType.dir);
    });

    test('parses an NLST line as a bare name', () {
      final e = FTPEntry.parse('justAName.txt', ListCommand.nlst);
      expect(e.name, 'justAName.txt');
      expect(e.type, FTPEntryType.unknown);
    });

    test('throws on a blank line', () {
      expect(() => FTPEntry.parse('   ', ListCommand.mlsd),
          throwsA(isA<FTPConnectException>()));
    });

    test('throws on an invalid LIST line', () {
      expect(() => FTPEntry.parse('totally invalid', ListCommand.list),
          throwsA(isA<FTPConnectException>()));
    });
  });

  group('FtpResponseReader', () {
    const timeout = Duration(seconds: 2);

    test('reads a single-line reply', () async {
      final conn = _ScriptedConnection();
      final reader = FtpResponseReader(conn, const Logger(), timeout);
      conn.feed('220 Welcome\r\n');
      final reply = await reader.readReply();
      expect(reply.code, 220);
      expect(reply.message, '220 Welcome');
      await reader.dispose();
    });

    test('reads two replies from one chunk in order', () async {
      final conn = _ScriptedConnection();
      final reader = FtpResponseReader(conn, const Logger(), timeout);
      conn.feed('331 Need password\r\n230 Logged in\r\n');
      expect((await reader.readReply()).code, 331);
      expect((await reader.readReply()).code, 230);
      await reader.dispose();
    });

    test('reassembles a reply split across chunks', () async {
      final conn = _ScriptedConnection();
      final reader = FtpResponseReader(conn, const Logger(), timeout);
      final future = reader.readReply();
      conn.feed('257 "/ho');
      conn.feed('me" is cwd\r\n');
      final reply = await future;
      expect(reply.code, 257);
      expect(reply.message, contains('/home'));
      await reader.dispose();
    });

    test('handles a multi-line reply and returns the terminating code',
        () async {
      final conn = _ScriptedConnection();
      final reader = FtpResponseReader(conn, const Logger(), timeout);
      conn.feed('211-Features:\r\n MLSD\r\n UTF8\r\n211 End\r\n');
      final reply = await reader.readReply();
      expect(reply.code, 211);
      await reader.dispose();
    });

    test(
        'a multi-line reply is not terminated early by an intermediate line '
        'that looks like a different-code terminator', () async {
      final conn = _ScriptedConnection();
      final reader = FtpResponseReader(conn, const Logger(), timeout);
      // The "150 opening data connection" line here is just server text
      // inside a 211 multi-line reply; it must not be mistaken for the
      // terminator of an unrelated 150 reply.
      conn.feed('211-Status:\r\n'
          '150 opening data connection\r\n'
          '211 End\r\n');
      final reply = await reader.readReply();
      expect(reply.code, 211);
      expect(reply.message, contains('150 opening data connection'));
      await reader.dispose();
    });

    test('times out when no reply arrives', () async {
      final conn = _ScriptedConnection();
      final reader = FtpResponseReader(
          conn, const Logger(), const Duration(milliseconds: 100));
      expect(() => reader.readReply(), throwsA(isA<FTPConnectException>()));
      await reader.dispose();
    });

    test('errors when the connection closes with no reply', () async {
      final conn = _ScriptedConnection();
      final reader = FtpResponseReader(conn, const Logger(), timeout);
      final future = reader.readReply();
      conn.done();
      expect(future, throwsA(isA<FTPConnectException>()));
    });
  });
}
