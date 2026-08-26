library;

import 'dart:io';
import 'dart:typed_data';

import 'package:ftpconnect/ftpconnect.dart';
import 'package:test/test.dart';

import 'mocks/ftp_client_fake.dart';
import 'mocks/virtual_file_system.dart';

/// Offline unit tests for the FTP client contract.
///
/// These replace the previous integration tests that hit public FTP servers.
/// They drive [FtpClientForTest] — an in-memory [FileTransferClient] that
/// reproduces the real `FTPConnect` behavior — so the whole client surface is
/// covered without any network access.
void main() {
  const String testFileDir = 'test/test_res_files';

  late Directory tempDir;

  setUp(() {
    tempDir = Directory('$testFileDir/ftp_tmp')..createSync(recursive: true);
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  File localFile(String name, {String? content}) {
    final File f = File('${tempDir.path}/$name');
    f.writeAsStringSync(content ?? 'ftpconnect-test ${DateTime.now()}');
    return f;
  }

  FtpClientForTest newClient({VirtualFileSystem? fs, bool showLog = false}) =>
      FtpClientForTest(
        user: 'dlpuser',
        pass: 'password',
        showLog: showLog,
        fs: fs,
      );

  group('connection', () {
    test('connect then disconnect succeed', () async {
      final FtpClientForTest ftp = newClient();
      expect(await ftp.connect(), isTrue);
      expect(ftp.isConnected, isTrue);
      expect(await ftp.disconnect(), isTrue);
      expect(ftp.isConnected, isFalse);
    });

    test('connect throws FTPConnectException on failure', () async {
      final FtpClientForTest ftp = FtpClientForTest(throwOnConnect: true);
      expect(() => ftp.connect(), throwsA(isA<FTPConnectException>()));
    });

    test('is a FileTransferClient', () {
      expect(newClient(), isA<FileTransferClient>());
    });
  });

  group('directory operations', () {
    test('currentDirectory starts at root', () async {
      final FtpClientForTest ftp = newClient();
      await ftp.connect();
      expect(await ftp.currentDirectory(), '/');
    });

    test('create, change into, and delete a directory', () async {
      final FtpClientForTest ftp = newClient();
      await ftp.connect();
      const String dir = 'no_name_test';

      expect(
          await ftp.checkFolderExistence('missing_${DateTime.now()}'), isFalse);
      // Re-anchor at root: checkFolderExistence navigates on success.
      await ftp.changeDirectory('/');

      expect(await ftp.createFolderIfNotExist(dir), isTrue);
      expect(await ftp.changeDirectory(dir), isTrue);
      expect(await ftp.currentDirectory(), '/$dir');

      await ftp.changeDirectory('..');
      expect(await ftp.currentDirectory(), '/');
      expect(await ftp.deleteEmptyDirectory(dir), isTrue);
      expect(await ftp.checkFolderExistence('/$dir'), isFalse);
    });

    test('createFolderIfNotExist is idempotent', () async {
      final FtpClientForTest ftp = newClient();
      await ftp.connect();
      expect(await ftp.createFolderIfNotExist('/a'), isTrue);
      await ftp.changeDirectory('/');
      // Already exists -> true (and navigates into it as a side effect).
      expect(await ftp.createFolderIfNotExist('/a'), isTrue);
    });

    test('makeDirectory fails when parent is missing', () async {
      final FtpClientForTest ftp = newClient();
      await ftp.connect();
      expect(await ftp.makeDirectory('/nope/child'), isFalse);
    });

    test('changeDirectory returns false for a missing directory', () async {
      final FtpClientForTest ftp = newClient();
      await ftp.connect();
      expect(await ftp.changeDirectory('/does_not_exist'), isFalse);
      // Current directory is unchanged after a failed cd.
      expect(await ftp.currentDirectory(), '/');
    });

    test('deleteEmptyDirectory fails on a non-empty directory', () async {
      final VirtualFileSystem fs = VirtualFileSystem()..mkdirs('/parent/child');
      final FtpClientForTest ftp = newClient(fs: fs);
      await ftp.connect();
      expect(await ftp.deleteEmptyDirectory('/parent'), isFalse);
    });

    test('deleteDirectory removes a non-empty tree recursively', () async {
      final VirtualFileSystem fs = VirtualFileSystem()
        ..mkdirs('/root/sub')
        ..seedFile('/root/a.txt', [1, 2, 3])
        ..seedFile('/root/sub/b.txt', [4, 5]);
      final FtpClientForTest ftp = newClient(fs: fs);
      await ftp.connect();

      expect(await ftp.deleteDirectory('/root'), isTrue);
      expect(await ftp.checkFolderExistence('/root'), isFalse);
    });

    test('deleteDirectory throws when the directory does not exist', () async {
      final FtpClientForTest ftp = newClient();
      await ftp.connect();
      expect(() => ftp.deleteDirectory('/nonExist'),
          throwsA(isA<FTPConnectException>()));
    });

    test('listDirectoryContent returns typed entries', () async {
      final VirtualFileSystem fs = VirtualFileSystem()
        ..mkdirs('/data/folder')
        ..seedFile('/data/file.txt', List<int>.filled(10, 0));
      final FtpClientForTest ftp = newClient(fs: fs);
      await ftp.connect();
      await ftp.changeDirectory('/data');

      final List<FTPEntry> entries = await ftp.listDirectoryContent();
      expect(entries.map((FTPEntry e) => e.name),
          containsAll(<String>['folder', 'file.txt']));
      final FTPEntry file =
          entries.firstWhere((FTPEntry e) => e.name == 'file.txt');
      expect(file.type, FTPEntryType.file);
      expect(file.size, 10);
      final FTPEntry folder =
          entries.firstWhere((FTPEntry e) => e.name == 'folder');
      expect(folder.type, FTPEntryType.dir);
    });

    test('listDirectoryContent returns entries', () async {
      final VirtualFileSystem fs = VirtualFileSystem()
        ..seedFile('/x.txt', [0])
        ..seedFile('/y.txt', [0]);
      final FtpClientForTest ftp = newClient(fs: fs);
      await ftp.connect();
      final List<FTPEntry> entries = await ftp.listDirectoryContent();
      expect(entries.map((FTPEntry e) => e.name),
          containsAll(<String>['x.txt', 'y.txt']));
    });
  });

  group('file operations', () {
    test('upload, exist, size, download round-trip with progress', () async {
      final FtpClientForTest ftp = newClient();
      await ftp.connect();
      expect(await ftp.createFolderIfNotExist('/work'), isTrue);
      // createFolderIfNotExist navigates into /work on creation.

      final File toUpload =
          localFile('upload.txt', content: 'hello world payload');

      int uploadPercent = -1;
      int uploadRead = 0;
      expect(
          await ftp.uploadFile(
            toUpload,
            sRemoteName: 'remote.txt',
            onProgress: (double p, int r, int total) {
              uploadPercent = p.round();
              uploadRead = r;
            },
          ),
          isTrue);
      expect(uploadPercent, 100);
      expect(uploadRead, await toUpload.length());

      expect(await ftp.existFile('remote.txt'), isTrue);
      expect(await ftp.sizeFile('remote.txt'), await toUpload.length());

      final File downloaded = File('${tempDir.path}/download.txt');
      int downloadPercent = -1;
      expect(
          await ftp.downloadFile(
            'remote.txt',
            downloaded,
            onProgress: (double p, int r, int total) =>
                downloadPercent = p.round(),
          ),
          isTrue);
      expect(downloadPercent, 100);
      expect(await downloaded.readAsString(), await toUpload.readAsString());
    });

    test('uploadFile uses the local filename when no remote name is given',
        () async {
      final FtpClientForTest ftp = newClient();
      await ftp.connect();
      final File toUpload = localFile('named.txt', content: 'x');
      expect(await ftp.uploadFile(toUpload), isTrue);
      expect(await ftp.existFile('named.txt'), isTrue);
    });

    test('uploadFile fails when the target directory is missing', () async {
      final FtpClientForTest ftp = newClient();
      await ftp.connect();
      final File toUpload = localFile('u.txt', content: 'x');
      expect(await ftp.uploadFile(toUpload, sRemoteName: '/missing/u.txt'),
          isFalse);
    });

    test('downloadFile throws for a missing remote file', () async {
      final FtpClientForTest ftp = newClient();
      await ftp.connect();
      final File local = File('${tempDir.path}/nope.txt');
      expect(
        () => ftp.downloadFile('not_exist.zip', local),
        throwsA(
          isA<FTPConnectException>().having(
              (FTPConnectException e) => e.message,
              'message',
              'Remote File not_exist.zip does not exist!'),
        ),
      );
    });

    test('sizeFile returns -1 for a missing file', () async {
      final FtpClientForTest ftp = newClient();
      await ftp.connect();
      expect(await ftp.sizeFile('../notExist.zip'), -1);
      expect(await ftp.existFile('../notExist.zip'), isFalse);
    });

    test('rename moves a file', () async {
      final VirtualFileSystem fs = VirtualFileSystem()
        ..seedFile('/file.txt', [1, 2, 3]);
      final FtpClientForTest ftp = newClient(fs: fs);
      await ftp.connect();

      expect(await ftp.rename('file.txt', 'file_renamed.txt'), isTrue);
      expect(await ftp.existFile('file.txt'), isFalse);
      expect(await ftp.existFile('file_renamed.txt'), isTrue);
    });

    test('rename fails when the source is missing', () async {
      final FtpClientForTest ftp = newClient();
      await ftp.connect();
      expect(await ftp.rename('ghost.txt', 'other.txt'), isFalse);
    });

    test('deleteFile removes a file and fails when it is absent', () async {
      final VirtualFileSystem fs = VirtualFileSystem()
        ..seedFile('/gone.txt', [0]);
      final FtpClientForTest ftp = newClient(fs: fs);
      await ftp.connect();
      expect(await ftp.deleteFile('gone.txt'), isTrue);
      expect(await ftp.deleteFile('gone.txt'), isFalse);
    });
  });

  group('downloadDirectory', () {
    test('mirrors a remote tree locally', () async {
      final VirtualFileSystem fs = VirtualFileSystem()
        ..mkdirs('/remote/inner')
        ..seedFile('/remote/a.txt', 'A'.codeUnits)
        ..seedFile('/remote/inner/b.txt', 'B'.codeUnits);
      final FtpClientForTest ftp = newClient(fs: fs);
      await ftp.connect();

      final Directory local = Directory('${tempDir.path}/mirror');
      expect(await ftp.downloadDirectory('/remote', local), isTrue);
      expect(await File('${local.path}/a.txt').readAsString(), 'A');
      expect(await File('${local.path}/inner/b.txt').readAsString(), 'B');
    });

    test('throws for a missing remote directory', () async {
      final FtpClientForTest ftp = newClient();
      await ftp.connect();
      expect(
        () => ftp.downloadDirectory('/nonExist', tempDir),
        throwsA(isA<FTPConnectException>()),
      );
    });
  });

  group('in-memory transfers', () {
    test('uploadData then downloadToBytes round-trip', () async {
      final FtpClientForTest ftp = newClient();
      await ftp.connect();
      final Uint8List payload = Uint8List.fromList('in memory'.codeUnits);

      int upPercent = -1;
      expect(
          await ftp.uploadData(payload, 'mem.bin',
              onProgress: (double p, int r, int t) => upPercent = p.round()),
          isTrue);
      expect(upPercent, 100);
      expect(await ftp.sizeFile('mem.bin'), payload.length);

      int downPercent = -1;
      final Uint8List bytes = await ftp.downloadToBytes('mem.bin',
          onProgress: (double p, int r, int t) => downPercent = p.round());
      expect(downPercent, 100);
      expect(bytes, payload);
    });

    test('downloadToBytes throws for a missing remote file', () async {
      final FtpClientForTest ftp = newClient();
      await ftp.connect();
      expect(
        () => ftp.downloadToBytes('ghost.bin'),
        throwsA(isA<FTPConnectException>()),
      );
    });
  });

  group('uploadDirectory', () {
    test('mirrors a local tree remotely', () async {
      final FtpClientForTest ftp = newClient();
      await ftp.connect();

      final Directory src = Directory('${tempDir.path}/src')
        ..createSync(recursive: true);
      File('${src.path}/a.txt').writeAsStringSync('A');
      Directory('${src.path}/inner').createSync();
      File('${src.path}/inner/b.txt').writeAsStringSync('B');

      expect(await ftp.uploadDirectory(src, '/remote'), isTrue);
      expect(await ftp.existFile('/remote/a.txt'), isTrue);
      expect(await ftp.existFile('/remote/inner/b.txt'), isTrue);
    });
  });

  group('deleteNonEmptyDirectory', () {
    test('removes a non-empty directory recursively', () async {
      final VirtualFileSystem fs = VirtualFileSystem()
        ..mkdirs('/root/sub')
        ..seedFile('/root/a.txt', [1])
        ..seedFile('/root/sub/b.txt', [2]);
      final FtpClientForTest ftp = newClient(fs: fs);
      await ftp.connect();

      expect(await ftp.deleteNonEmptyDirectory('/root'), isTrue);
      expect(await ftp.checkFolderExistence('/root'), isFalse);
    });

    test('returns false when the directory is missing', () async {
      final FtpClientForTest ftp = newClient();
      await ftp.connect();
      expect(await ftp.deleteNonEmptyDirectory('/ghost'), isFalse);
    });
  });
}
