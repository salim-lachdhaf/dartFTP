library;

import 'package:ftpconnect/ftpconnect.dart';
import 'package:ftpconnect/src/ftp/ftp_reply.dart';
import 'package:ftpconnect/src/common/utils.dart';
import 'package:test/test.dart';

/// Offline unit tests for the pure (network-free) logic of the package.
///
/// Unlike the integration suites, these run without any FTP/SFTP server and
/// are therefore safe to execute in CI.
void main() {
  group('Utils.parsePort', () {
    test('parses a standard PASV response', () {
      const response = '227 Entering Passive Mode (192,168,8,36,8,75).';
      // 8 * 256 + 75 = 2123
      expect(Utils.parsePort(response, false), 2123);
      expect(Utils.parsePortPASV(response), 2123);
    });

    test('parses an EPSV (extended passive) response', () {
      const response = '229 Entering Extended Passive Mode (|||6446|)';
      expect(Utils.parsePort(response, true), 6446);
      expect(Utils.parsePortEPSV(response), 6446);
    });

    test('throws when the PASV response is malformed', () {
      expect(() => Utils.parsePortPASV('227 no parentheses here'),
          throwsA(isA<Error>()));
    });
  });

  group('FTPReply', () {
    test('isSuccessCode is true only for 2xx codes', () {
      expect(FTPReply(200, 'ok').isSuccessCode(), isTrue);
      expect(FTPReply(226, 'transfer complete').isSuccessCode(), isTrue);
      expect(FTPReply(299, 'ok').isSuccessCode(), isTrue);
      expect(FTPReply(150, 'opening data').isSuccessCode(), isFalse);
      expect(FTPReply(331, 'need password').isSuccessCode(), isFalse);
      expect(FTPReply(550, 'error').isSuccessCode(), isFalse);
    });

    test('exposes code/message and a readable toString', () {
      final reply = FTPReply(220, 'welcome');
      expect(reply.code, 220);
      expect(reply.message, 'welcome');
      expect(reply.toString(), 'FTPReply =  [code= 220, message= welcome]');
    });
  });

  group('FTPConnectException', () {
    test('keeps message and optional response', () {
      final withResponse = FTPConnectException('boom', 'server said no');
      expect(withResponse.message, 'boom');
      expect(withResponse.response, 'server said no');
      expect(withResponse.toString(),
          'FTPConnectException: boom (Response: server said no)');

      final withoutResponse = FTPConnectException('boom');
      expect(withoutResponse.response, isNull);
    });
  });

  group('FTPEntry.parse - LIST', () {
    test('parses a standard unix listing', () {
      final entry = FTPEntry.parse(
          '-rw-------    1 105      108        1024 Jan 10 11:50 file.zip',
          ListCommand.list);
      expect(entry.type, FTPEntryType.file);
      expect(entry.permission, 'rw-------');
      expect(entry.name, 'file.zip');
      expect(entry.owner, '105');
      expect(entry.group, '108');
      expect(entry.size, 1024);
      expect(entry.modifyTime, isA<DateTime>());
    });

    test('parses a directory entry', () {
      final entry = FTPEntry.parse(
          'drwxr-xr-x    2 105      108        4096 Jan 10 11:50 folder',
          ListCommand.list);
      expect(entry.type, FTPEntryType.dir);
      expect(entry.name, 'folder');
    });

    test('parses negative file sizes without throwing', () {
      final entry = FTPEntry.parse(
          '-rw-r--r-- 1 owner group -213 Aug 26 16:31 File.txt',
          ListCommand.list);
      expect(entry.type, FTPEntryType.file);
      expect(entry.size, -213);
      expect(entry.name, 'File.txt');
    });

    test('parses IIS/SII server listings (dir and file)', () {
      final dir = FTPEntry.parse(
          '02-11-15  03:05PM      <DIR>     1410887680 directory',
          ListCommand.list);
      expect(dir.type, FTPEntryType.dir);
      expect(dir.name, 'directory');

      final file = FTPEntry.parse(
          '02-11-15  03:05PM               1410887680 movie.avi',
          ListCommand.list);
      expect(file.type, FTPEntryType.file);
      expect(file.name, 'movie.avi');
    });

    test('throws on an invalid LIST line', () {
      expect(() => FTPEntry.parse('not a valid line', ListCommand.list),
          throwsA(isA<FTPConnectException>()));
    });
  });

  group('FTPEntry.parse - MLSD', () {
    test('parses attributes and name', () {
      final entry = FTPEntry.parse(
          'Type=dir;Modify=20150211035000;UNIX.owner=105;UNIX.group=108;Size=1024; folder',
          ListCommand.mlsd);
      expect(entry.type, FTPEntryType.dir);
      expect(entry.name, 'folder');
      expect(entry.owner, '105');
      expect(entry.group, '108');
      expect(entry.size, 1024);
      expect(entry.modifyTime, isA<DateTime>());
    });

    test('round-trips through toString()', () {
      final original = FTPEntry.parse(
          'drw-------    1 105      108        1024 Jan 10 11:50 dir',
          ListCommand.list);
      final reparsed = FTPEntry.parse(original.toString(), ListCommand.mlsd);
      expect(reparsed.type, FTPEntryType.dir);
      expect(reparsed.owner, '105');
      expect(reparsed.group, '108');
      expect(reparsed.size, 1024);
    });
  });

  group('FTPEntry.parse - NLST', () {
    test('returns the raw name with unknown type', () {
      final entry = FTPEntry.parse('some_file.txt', ListCommand.nlst);
      expect(entry.name, 'some_file.txt');
      expect(entry.type, FTPEntryType.unknown);
    });
  });

  group('FTPEntry.parse - errors', () {
    test('throws on blank input for every command', () {
      for (final cmd in ListCommand.values) {
        expect(
            () => FTPEntry.parse('', cmd), throwsA(isA<FTPConnectException>()));
      }
    });
  });

  group('Logger', () {
    test('does not throw whether enabled or not', () {
      expect(() => Logger(isEnabled: false).log('hidden'), returnsNormally);
      expect(() => Logger(isEnabled: true).log('shown'), returnsNormally);
    });
  });
}
