library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ftpconnect/ftpconnect.dart';
import 'package:test/test.dart';

import 'mocks/fake_sftp_adapter.dart';
import 'mocks/virtual_file_system.dart';

/// Offline tests exercising the *real* [SFTPConnect] client end to end through
/// an injected in-memory [FakeSftpConnector]. The actual client logic (path
/// resolution, recursion, progress, streaming) runs without any network.
void main() {
  const String testFileDir = 'test/UnitTestSFTP_tmp';
  late Directory tempDir;

  setUp(() {
    tempDir = Directory(testFileDir)..createSync(recursive: true);
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  File localFile(String name, {String? content}) {
    final File f = File('${tempDir.path}/$name');
    f.writeAsStringSync(content ?? 'sftp-test-payload');
    return f;
  }

  SFTPConnect newClient(FakeSftpConnector connector) => SFTPConnect(
        'example.com',
        user: 'user',
        pass: 'pass',
        connector: connector,
      );

  Future<SFTPConnect> connected(FakeSftpConnector connector) async {
    final SFTPConnect sftp = newClient(connector);
    await sftp.connect();
    return sftp;
  }

  group('connection', () {
    test('connect then disconnect succeed', () async {
      final sftp = newClient(FakeSftpConnector());
      expect(await sftp.connect(), isTrue);
      expect(await sftp.disconnect(), isTrue);
    });

    test('connect throws FTPConnectException on failure', () {
      final sftp = newClient(FakeSftpConnector(throwOnConnect: true));
      expect(() => sftp.connect(), throwsA(isA<FTPConnectException>()));
    });

    test('operations before connect throw', () {
      final sftp = newClient(FakeSftpConnector());
      expect(() => sftp.listDirectoryContent('/'),
          throwsA(isA<FTPConnectException>()));
    });

    test('is a FileTransferClient', () {
      expect(newClient(FakeSftpConnector()), isA<FileTransferClient>());
    });
  });

  group('directory navigation', () {
    test('changeDirectory resolves relative and absolute paths', () async {
      final fs = VirtualFileSystem()..mkdirs('/pub/example');
      final sftp = await connected(FakeSftpConnector(fs: fs));

      expect(await sftp.changeDirectory('/pub'), isTrue);
      expect(await sftp.currentDirectory(), '/pub');
      expect(await sftp.changeDirectory('example'), isTrue);
      expect(await sftp.currentDirectory(), '/pub/example');
      expect(await sftp.changeDirectory('..'), isTrue);
      expect(await sftp.currentDirectory(), '/pub');
    });

    test('changeDirectory fails on a missing/target-is-file path', () async {
      final fs = VirtualFileSystem()..seedFile('/file.txt', utf8.encode('x'));
      final sftp = await connected(FakeSftpConnector(fs: fs));
      expect(await sftp.changeDirectory('/nope'), isFalse);
      expect(await sftp.changeDirectory('/file.txt'), isFalse);
    });

    test('makeDirectory / createFolderIfNotExist / deleteDirectory', () async {
      final sftp = await connected(FakeSftpConnector());
      expect(await sftp.makeDirectory('data'), isTrue);
      expect(await sftp.checkFolderExistence('data'), isTrue);
      expect(await sftp.createFolderIfNotExist('data'), isTrue);
      expect(await sftp.deleteDirectory('data'), isTrue);
      expect(await sftp.checkFolderExistence('data'), isFalse);
    });
  });

  group('listing', () {
    test('listDirectoryContent returns typed entries', () async {
      final fs = VirtualFileSystem()
        ..seedFile('/readme.txt', utf8.encode('welcome'))
        ..mkdirs('/pub');
      final sftp = await connected(FakeSftpConnector(fs: fs));

      final entries = await sftp.listDirectoryContent('/');
      expect(entries.map((e) => e.name), containsAll(['readme.txt', 'pub']));
      expect(entries.firstWhere((e) => e.name == 'pub').type, FTPEntryType.dir);
      final file = entries.firstWhere((e) => e.name == 'readme.txt');
      expect(file.type, FTPEntryType.file);
      expect(file.size, 7);
    });
  });

  group('file transfers', () {
    test('uploadFile then downloadFile round-trip', () async {
      final fs = VirtualFileSystem();
      final sftp = await connected(FakeSftpConnector(fs: fs));
      final File src = localFile('up.txt', content: 'hello sftp');

      expect(await sftp.uploadFile(src, sRemoteName: 'remote.txt'), isTrue);
      expect(fs.isFile('/remote.txt'), isTrue);

      final File dst = File('${tempDir.path}/down.txt');
      expect(await sftp.downloadFile('remote.txt', dst), isTrue);
      expect(dst.readAsStringSync(), 'hello sftp');
    });

    test('uploadData then downloadToBytes round-trip with progress', () async {
      final sftp = await connected(FakeSftpConnector());
      final Uint8List data =
          Uint8List.fromList(utf8.encode('some in-memory content here'));

      final List<double> up = <double>[];
      expect(
          await sftp.uploadData(data, 'mem.bin',
              onProgress: (pct, _, __) => up.add(pct)),
          isTrue);
      expect(up.last, 100);

      final List<double> down = <double>[];
      final Uint8List back = await sftp.downloadToBytes('mem.bin',
          onProgress: (pct, _, __) => down.add(pct));
      expect(back, equals(data));
      expect(down.last, 100);
    });

    test('downloadToBytes throws for a missing remote file', () async {
      final sftp = await connected(FakeSftpConnector());
      expect(() => sftp.downloadToBytes('missing.txt'),
          throwsA(isA<FTPConnectException>()));
    });

    test('sizeFile / existFile', () async {
      final fs = VirtualFileSystem()..seedFile('/f.txt', utf8.encode('12345'));
      final sftp = await connected(FakeSftpConnector(fs: fs));
      expect(await sftp.sizeFile('/f.txt'), 5);
      expect(await sftp.existFile('/f.txt'), isTrue);
      expect(await sftp.existFile('/ghost'), isFalse);
    });

    test('rename moves a remote file', () async {
      final fs = VirtualFileSystem()..seedFile('/old.txt', utf8.encode('x'));
      final sftp = await connected(FakeSftpConnector(fs: fs));
      expect(await sftp.rename('/old.txt', '/new.txt'), isTrue);
      expect(fs.isFile('/new.txt'), isTrue);
      expect(await sftp.rename('/absent', '/x'), isFalse);
    });

    test('deleteFile removes a remote file', () async {
      final fs = VirtualFileSystem()..seedFile('/gone.txt', utf8.encode('x'));
      final sftp = await connected(FakeSftpConnector(fs: fs));
      expect(await sftp.deleteFile('/gone.txt'), isTrue);
      expect(fs.isFile('/gone.txt'), isFalse);
    });
  });

  group('recursive directory operations', () {
    test('deleteNonEmptyDirectory removes a non-empty tree', () async {
      final fs = VirtualFileSystem()
        ..seedFile('/root/a.txt', utf8.encode('a'))
        ..seedFile('/root/sub/b.txt', utf8.encode('b'));
      final sftp = await connected(FakeSftpConnector(fs: fs));

      expect(await sftp.deleteNonEmptyDirectory('/root'), isTrue);
      expect(fs.exists('/root'), isFalse);
    });

    test('deleteNonEmptyDirectory returns false for a missing directory',
        () async {
      final sftp = await connected(FakeSftpConnector());
      expect(await sftp.deleteNonEmptyDirectory('/absent'), isFalse);
    });

    test('downloadDirectory mirrors a remote tree locally', () async {
      final fs = VirtualFileSystem()
        ..seedFile('/tree/one.txt', utf8.encode('one'))
        ..seedFile('/tree/nested/two.txt', utf8.encode('two'));
      final sftp = await connected(FakeSftpConnector(fs: fs));

      final Directory out = Directory('${tempDir.path}/mirror');
      expect(await sftp.downloadDirectory('/tree', out), isTrue);
      expect(File('${out.path}/one.txt').readAsStringSync(), 'one');
      expect(File('${out.path}/nested/two.txt').readAsStringSync(), 'two');
    });

    test('uploadDirectory mirrors a local tree remotely', () async {
      final fs = VirtualFileSystem();
      final sftp = await connected(FakeSftpConnector(fs: fs));

      final Directory local = Directory('${tempDir.path}/src')
        ..createSync(recursive: true);
      File('${local.path}/x.txt').writeAsStringSync('X');
      Directory('${local.path}/inner').createSync();
      File('${local.path}/inner/y.txt').writeAsStringSync('Y');

      expect(await sftp.uploadDirectory(local, '/uploaded'), isTrue);
      expect(fs.isFile('/uploaded/x.txt'), isTrue);
      expect(fs.isFile('/uploaded/inner/y.txt'), isTrue);
    });
  });
}
