library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ftpconnect/ftpconnect.dart';
import 'package:test/test.dart';

import 'mocks/fake_ftp_server.dart';
import 'mocks/virtual_file_system.dart';

/// Offline tests exercising the *real* [FTPConnect] client end to end through an
/// injected in-memory [FakeFtpServer]. No network access is involved, yet the
/// actual protocol logic (commands, replies, passive-mode data transfers) runs.
void main() {
  const String testFileDir = 'test/UnitTestFTP_tmp';
  late Directory tempDir;

  setUp(() {
    tempDir = Directory(testFileDir)..createSync(recursive: true);
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  File localFile(String name, {String? content}) {
    final File f = File('${tempDir.path}/$name');
    f.writeAsStringSync(content ?? 'ftpconnect-test-payload');
    return f;
  }

  FTPConnect newClient(FakeFtpServer server) => FTPConnect(
        '127.0.0.1',
        user: 'dlpuser',
        pass: 'password',
        connector: server,
      );

  Future<FTPConnect> connected(FakeFtpServer server) async {
    final FTPConnect ftp = newClient(server);
    await ftp.connect();
    return ftp;
  }

  group('connection', () {
    test('connect then disconnect succeed', () async {
      final ftp = newClient(FakeFtpServer());
      expect(await ftp.connect(), isTrue);
      expect(await ftp.disconnect(), isTrue);
    });

    test('connect throws FTPConnectException when the socket fails', () {
      final ftp = newClient(FakeFtpServer(throwOnConnect: true));
      expect(() => ftp.connect(), throwsA(isA<FTPConnectException>()));
    });

    test('connect throws on a wrong password', () {
      final ftp = FTPConnect(
        '127.0.0.1',
        user: 'dlpuser',
        pass: 'wrong',
        connector: FakeFtpServer(validPass: 'secret'),
      );
      expect(() => ftp.connect(), throwsA(isA<FTPConnectException>()));
    });

    test('is a FileTransferClient', () {
      expect(newClient(FakeFtpServer()), isA<FileTransferClient>());
    });
  });

  group('directory navigation', () {
    test('currentDirectory returns the server cwd', () async {
      final ftp = await connected(FakeFtpServer());
      expect(await ftp.currentDirectory(), '/');
    });

    test('changeDirectory succeeds for an existing directory', () async {
      final fs = VirtualFileSystem()..mkdirs('/pub/data');
      final ftp = await connected(FakeFtpServer(fs: fs));
      expect(await ftp.changeDirectory('/pub/data'), isTrue);
      expect(await ftp.currentDirectory(), '/pub/data');
    });

    test('changeDirectory fails for a missing directory', () async {
      final ftp = await connected(FakeFtpServer());
      expect(await ftp.changeDirectory('/nope'), isFalse);
    });

    test('makeDirectory / deleteDirectory', () async {
      final fs = VirtualFileSystem();
      final ftp = await connected(FakeFtpServer(fs: fs));
      expect(await ftp.makeDirectory('created'), isTrue);
      expect(fs.isDirectory('/created'), isTrue);
      expect(await ftp.deleteDirectory('created'), isTrue);
      expect(fs.isDirectory('/created'), isFalse);
    });

    test('createFolderIfNotExist is idempotent', () async {
      final ftp = await connected(FakeFtpServer());
      expect(await ftp.createFolderIfNotExist('once'), isTrue);
      expect(await ftp.createFolderIfNotExist('once'), isTrue);
    });

    test('checkFolderExistence does not change the current directory',
        () async {
      final fs = VirtualFileSystem()..mkdirs('/pub/data');
      final ftp = await connected(FakeFtpServer(fs: fs));
      expect(await ftp.currentDirectory(), '/');
      expect(await ftp.checkFolderExistence('/pub/data'), isTrue);
      expect(await ftp.currentDirectory(), '/',
          reason: 'checkFolderExistence must restore the previous cwd');
      expect(await ftp.checkFolderExistence('/nope'), isFalse);
      expect(await ftp.currentDirectory(), '/');
    });

    test('deleteNonEmptyDirectory never changes the current directory',
        () async {
      final fs = VirtualFileSystem()
        ..seedFile('/root/a.txt', utf8.encode('a'))
        ..seedFile('/root/sub/b.txt', utf8.encode('b'));
      final ftp = await connected(FakeFtpServer(fs: fs));
      await ftp.changeDirectory('/');
      expect(await ftp.deleteNonEmptyDirectory('/root'), isTrue);
      expect(await ftp.currentDirectory(), '/',
          reason: 'deletion is path-based and must never navigate');
    });
  });

  group('file transfers', () {
    test('uploadFile then downloadFile round-trip', () async {
      final fs = VirtualFileSystem();
      final ftp = await connected(FakeFtpServer(fs: fs));
      final File src = localFile('up.txt', content: 'hello ftp world');

      expect(await ftp.uploadFile(src, sRemoteName: 'remote.txt'), isTrue);
      expect(fs.isFile('/remote.txt'), isTrue);

      final File dst = File('${tempDir.path}/down.txt');
      expect(await ftp.downloadFile('remote.txt', dst), isTrue);
      expect(dst.readAsStringSync(), 'hello ftp world');
    });

    test('uploadData then downloadToBytes round-trip', () async {
      final ftp = await connected(FakeFtpServer());
      final Uint8List data = Uint8List.fromList(utf8.encode('in-memory bytes'));

      expect(await ftp.uploadData(data, 'mem.bin'), isTrue);
      final Uint8List back = await ftp.downloadToBytes('mem.bin');
      expect(back, equals(data));
    });

    test('reports progress while downloading', () async {
      final ftp = await connected(FakeFtpServer());
      await ftp.uploadData(
          Uint8List.fromList(List<int>.filled(100, 65)), 'big.bin');

      final List<double> progress = <double>[];
      await ftp.downloadToBytes('big.bin',
          onProgress: (pct, _, __) => progress.add(pct));
      expect(progress, isNotEmpty);
      expect(progress.last, 100);
    });

    test('sizeFile and existFile', () async {
      final ftp = await connected(FakeFtpServer());
      await ftp.uploadData(Uint8List.fromList(utf8.encode('12345')), 'f.txt');
      expect(await ftp.sizeFile('f.txt'), 5);
      expect(await ftp.existFile('f.txt'), isTrue);
      expect(await ftp.existFile('ghost.txt'), isFalse);
      expect(await ftp.sizeFile('ghost.txt'), -1);
    });

    test('downloadToBytes throws for a missing remote file', () async {
      final ftp = await connected(FakeFtpServer());
      expect(() => ftp.downloadToBytes('missing.txt'),
          throwsA(isA<FTPConnectException>()));
    });

    test('rename moves a remote file', () async {
      final fs = VirtualFileSystem();
      final ftp = await connected(FakeFtpServer(fs: fs));
      await ftp.uploadData(Uint8List.fromList(utf8.encode('x')), 'old.txt');
      expect(await ftp.rename('old.txt', 'new.txt'), isTrue);
      expect(fs.isFile('/new.txt'), isTrue);
      expect(fs.isFile('/old.txt'), isFalse);
    });

    test('deleteFile removes a remote file', () async {
      final fs = VirtualFileSystem();
      final ftp = await connected(FakeFtpServer(fs: fs));
      await ftp.uploadData(Uint8List.fromList(utf8.encode('x')), 'gone.txt');
      expect(await ftp.deleteFile('gone.txt'), isTrue);
      expect(fs.isFile('/gone.txt'), isFalse);
    });

    test('sendCustomCommand returns the raw reply', () async {
      final ftp = await connected(FakeFtpServer());
      final FTPReply reply = await ftp.sendCustomCommand('PWD');
      expect(reply.code, 257);
    });
  });

  group('listing', () {
    test('listDirectoryContent (MLSD) returns typed entries', () async {
      final fs = VirtualFileSystem()
        ..seedFile('/readme.txt', utf8.encode('hi'))
        ..mkdirs('/docs');
      final ftp = await connected(FakeFtpServer(fs: fs));

      final List<FTPEntry> entries = await ftp.listDirectoryContent();
      expect(entries.map((e) => e.name), containsAll(['readme.txt', 'docs']));
      final FTPEntry file = entries.firstWhere((e) => e.name == 'readme.txt');
      expect(file.type, FTPEntryType.file);
      expect(file.size, 2);
      final FTPEntry dir = entries.firstWhere((e) => e.name == 'docs');
      expect(dir.type, FTPEntryType.dir);
    });

    test('listDirectoryContent works with the LIST command', () async {
      final fs = VirtualFileSystem()..seedFile('/a.txt', utf8.encode('abc'));
      final ftp = FTPConnect(
        '127.0.0.1',
        connector: FakeFtpServer(fs: fs),
        listCommand: ListCommand.list,
      );
      await ftp.connect();
      final List<FTPEntry> entries = await ftp.listDirectoryContent();
      expect(entries.single.name, 'a.txt');
      expect(entries.single.size, 3);
    });
  });

  group('recursive directory operations', () {
    test('deleteNonEmptyDirectory removes a non-empty tree', () async {
      final fs = VirtualFileSystem()
        ..seedFile('/root/a.txt', utf8.encode('a'))
        ..seedFile('/root/sub/b.txt', utf8.encode('b'));
      final ftp = await connected(FakeFtpServer(fs: fs));

      expect(await ftp.deleteNonEmptyDirectory('/root'), isTrue);
      expect(fs.exists('/root'), isFalse);
    });

    test('deleteNonEmptyDirectory returns false for a missing directory',
        () async {
      final ftp = await connected(FakeFtpServer());
      expect(await ftp.deleteNonEmptyDirectory('/absent'), isFalse);
    });

    test(
        'deleteNonEmptyDirectory correctly tells files from directories '
        'even with ListCommand.nlst (no type info)', () async {
      final fs = VirtualFileSystem()
        ..seedFile('/root/a.txt', utf8.encode('a'))
        ..seedFile('/root/sub/b.txt', utf8.encode('b'));
      final ftp = FTPConnect(
        '127.0.0.1',
        connector: FakeFtpServer(fs: fs),
        listCommand: ListCommand.nlst,
      );
      await ftp.connect();

      expect(await ftp.deleteNonEmptyDirectory('/root'), isTrue);
      expect(fs.exists('/root'), isFalse);
    });

    test('downloadDirectory mirrors a remote tree locally', () async {
      final fs = VirtualFileSystem()
        ..seedFile('/tree/one.txt', utf8.encode('one'))
        ..seedFile('/tree/nested/two.txt', utf8.encode('two'));
      final ftp = await connected(FakeFtpServer(fs: fs));

      final Directory out = Directory('${tempDir.path}/mirror');
      expect(await ftp.downloadDirectory('/tree', out), isTrue);
      expect(File('${out.path}/one.txt').readAsStringSync(), 'one');
      expect(File('${out.path}/nested/two.txt').readAsStringSync(), 'two');
    });

    test(
        'downloadDirectory correctly tells files from directories even '
        'with ListCommand.nlst (no type info)', () async {
      final fs = VirtualFileSystem()
        ..seedFile('/tree/one.txt', utf8.encode('one'))
        ..seedFile('/tree/nested/two.txt', utf8.encode('two'));
      final ftp = FTPConnect(
        '127.0.0.1',
        connector: FakeFtpServer(fs: fs),
        listCommand: ListCommand.nlst,
      );
      await ftp.connect();

      final Directory out = Directory('${tempDir.path}/mirror-nlst');
      expect(await ftp.downloadDirectory('/tree', out), isTrue);
      expect(File('${out.path}/one.txt').readAsStringSync(), 'one');
      expect(File('${out.path}/nested/two.txt').readAsStringSync(), 'two');
    });

    test(
        'downloadDirectory never changes the current directory, even for a '
        'multi-segment path', () async {
      final fs = VirtualFileSystem()
        ..seedFile('/pub/data/reports/one.txt', utf8.encode('one'));
      final ftp = await connected(FakeFtpServer(fs: fs));
      await ftp.changeDirectory('/');

      final Directory out = Directory('${tempDir.path}/multi-mirror');
      expect(await ftp.downloadDirectory('/pub/data/reports', out), isTrue);
      expect(File('${out.path}/one.txt').readAsStringSync(), 'one');
      expect(await ftp.currentDirectory(), '/',
          reason: 'download is path-based and must never navigate');
    });

    test('uploadDirectory mirrors a local tree remotely', () async {
      final fs = VirtualFileSystem();
      final ftp = await connected(FakeFtpServer(fs: fs));

      final Directory local = Directory('${tempDir.path}/src')
        ..createSync(recursive: true);
      File('${local.path}/x.txt').writeAsStringSync('X');
      Directory('${local.path}/inner').createSync();
      File('${local.path}/inner/y.txt').writeAsStringSync('Y');

      expect(await ftp.uploadDirectory(local, 'uploaded'), isTrue);
      expect(fs.isFile('/uploaded/x.txt'), isTrue);
      expect(fs.isFile('/uploaded/inner/y.txt'), isTrue);
    });

    test(
        'uploadDirectory never changes the current directory, even for a '
        'multi-segment path', () async {
      final fs = VirtualFileSystem()..mkdirs('/pub/data');
      final ftp = await connected(FakeFtpServer(fs: fs));
      await ftp.changeDirectory('/');

      final Directory local = Directory('${tempDir.path}/multi-src')
        ..createSync(recursive: true);
      File('${local.path}/x.txt').writeAsStringSync('X');

      expect(await ftp.uploadDirectory(local, '/pub/data/reports'), isTrue);
      expect(fs.isFile('/pub/data/reports/x.txt'), isTrue);
      expect(await ftp.currentDirectory(), '/',
          reason: 'upload is path-based and must never navigate');
    });
  });
}
