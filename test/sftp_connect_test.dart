library;

import 'dart:io';
import 'dart:typed_data';

import 'package:ftpconnect/ftpconnect.dart';
import 'package:test/test.dart';

import 'mocks/sftp_client_fake.dart';
import 'mocks/virtual_file_system.dart';

/// Offline unit tests for the SFTP client contract.
///
/// These replace the previous integration tests that hit the public Rebex
/// SFTP server. They drive [SftpClientForTest] — an in-memory
/// [FileTransferClient] that reproduces the real `SFTPConnect` behavior — so
/// the whole client surface is covered without any network access.
void main() {
  const String testFileDir = 'test/test_res_files';

  late Directory tempDir;

  setUp(() {
    tempDir = Directory('$testFileDir/sftp_tmp')..createSync(recursive: true);
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  File localFile(String name, {String? content}) {
    final File f = File('${tempDir.path}/$name');
    f.writeAsStringSync(content ?? 'ftpconnect-sftp-test ${DateTime.now()}');
    return f;
  }

  /// A filesystem pre-seeded to look like a typical read-only server.
  VirtualFileSystem readOnlyFs() => VirtualFileSystem()
    ..seedFile('/readme.txt', 'welcome to the test server'.codeUnits)
    ..mkdirs('/pub/example')
    ..seedFile('/pub/example/readme.txt', 'example'.codeUnits);

  SftpClientForTest newClient({VirtualFileSystem? fs, bool showLog = false}) =>
      SftpClientForTest(
        user: 'demo',
        pass: 'password',
        showLog: showLog,
        fs: fs,
      );

  group('connection', () {
    test('connect then disconnect succeed', () async {
      final SftpClientForTest sftp = newClient();
      expect(await sftp.connect(), isTrue);
      expect(sftp.isConnected, isTrue);
      expect(await sftp.disconnect(), isTrue);
      expect(sftp.isConnected, isFalse);
    });

    test('connect throws FTPConnectException on failure', () async {
      final SftpClientForTest sftp = SftpClientForTest(throwOnConnect: true);
      expect(() => sftp.connect(), throwsA(isA<FTPConnectException>()));
    });

    test('is a FileTransferClient', () {
      expect(newClient(), isA<FileTransferClient>());
    });
  });

  group('read-only operations', () {
    test('lists the root directory and returns entries', () async {
      final SftpClientForTest sftp = newClient(fs: readOnlyFs());
      await sftp.connect();
      final List<FTPEntry> entries = await sftp.listDirectoryContent();
      expect(entries, isNotEmpty);
      expect(entries.any((FTPEntry e) => e.name == 'readme.txt'), isTrue);
      expect(entries.every((FTPEntry e) => e.name != '.' && e.name != '..'),
          isTrue);
    });

    test('lists directory content', () async {
      final SftpClientForTest sftp = newClient(fs: readOnlyFs());
      await sftp.connect();
      final List<FTPEntry> entries = await sftp.listDirectoryContent();
      expect(entries.map((FTPEntry e) => e.name), contains('readme.txt'));
    });

    test('changeDirectory / currentDirectory navigate remote paths', () async {
      final SftpClientForTest sftp = newClient(fs: readOnlyFs());
      await sftp.connect();
      expect(await sftp.currentDirectory(), '.');
      expect(await sftp.changeDirectory('/pub/example'), isTrue);
      expect(await sftp.currentDirectory(), '/pub/example');
      // Missing directories return false, not throw.
      expect(await sftp.changeDirectory('/does_not_exist_dir_xyz'), isFalse);
      // ...and leave the working directory untouched.
      expect(await sftp.currentDirectory(), '/pub/example');
    });

    test('existFile / sizeFile against a known remote file', () async {
      final SftpClientForTest sftp = newClient(fs: readOnlyFs());
      await sftp.connect();
      expect(await sftp.existFile('readme.txt'), isTrue);
      expect(await sftp.sizeFile('readme.txt'), greaterThan(0));
      expect(await sftp.existFile('no_such_file_ever.zzz'), isFalse);
      expect(await sftp.sizeFile('no_such_file_ever.zzz'), -1);
    });

    test('checkFolderExistence detects directories without navigating',
        () async {
      final SftpClientForTest sftp = newClient(fs: readOnlyFs());
      await sftp.connect();
      expect(await sftp.checkFolderExistence('/pub'), isTrue);
      // Unlike FTP, this does NOT change the working directory.
      expect(await sftp.currentDirectory(), '.');
      expect(await sftp.checkFolderExistence('/no_such_dir_ever'), isFalse);
    });

    test('downloadFile writes the remote file locally with progress', () async {
      final SftpClientForTest sftp = newClient(fs: readOnlyFs());
      await sftp.connect();
      final File local = File('${tempDir.path}/sftp_download.txt');

      int lastPercent = -1;
      int lastRead = 0;
      int lastTotal = 0;
      expect(
          await sftp.downloadFile(
            'readme.txt',
            local,
            onProgress: (double p, int r, int total) {
              lastPercent = p.round();
              lastRead = r;
              lastTotal = total;
            },
          ),
          isTrue);

      expect(await local.exists(), isTrue);
      final int length = await local.length();
      expect(length, greaterThan(0));
      expect(lastTotal, length);
      expect(lastRead, length);
      expect(lastPercent, 100);
    });

    test('downloadFile throws for missing remote files', () async {
      final SftpClientForTest sftp = newClient(fs: readOnlyFs());
      await sftp.connect();
      final File local = File('${tempDir.path}/should_not_exist.bin');
      expect(
        () => sftp.downloadFile('no_such_file_ever.zzz', local),
        throwsA(isA<FTPConnectException>()),
      );
    });

    test('downloadFile throws when the remote name is null', () async {
      final SftpClientForTest sftp = newClient(fs: readOnlyFs());
      await sftp.connect();
      expect(
        () => sftp.downloadFile(null, File('${tempDir.path}/x.bin')),
        throwsA(isA<FTPConnectException>()),
      );
    });
  });

  group('write operations', () {
    test('upload, exist, size, download, then delete round-trip', () async {
      final SftpClientForTest sftp = newClient();
      await sftp.connect();

      final File toUpload =
          localFile('sftp_write_upload.txt', content: 'hello from ftpconnect');
      const String remoteName = 'sftp_write_upload.txt';

      int uploadPercent = -1;
      expect(
          await sftp.uploadFile(
            toUpload,
            sRemoteName: remoteName,
            onProgress: (double p, int r, int t) => uploadPercent = p.round(),
          ),
          isTrue);
      expect(uploadPercent, 100);

      expect(await sftp.existFile(remoteName), isTrue);
      expect(await sftp.sizeFile(remoteName), await toUpload.length());

      final File downloaded = File('${tempDir.path}/sftp_write_download.txt');
      expect(await sftp.downloadFile(remoteName, downloaded), isTrue);
      expect(await downloaded.readAsString(), await toUpload.readAsString());

      expect(await sftp.deleteFile(remoteName), isTrue);
      expect(await sftp.existFile(remoteName), isFalse);
    });

    test('uploadFile uses the local filename when no remote name is given',
        () async {
      final SftpClientForTest sftp = newClient();
      await sftp.connect();
      final File toUpload = localFile('by_name.txt', content: 'x');
      expect(await sftp.uploadFile(toUpload), isTrue);
      expect(await sftp.existFile('by_name.txt'), isTrue);
    });

    test('makeDirectory / createFolderIfNotExist / deleteEmptyDirectory',
        () async {
      final SftpClientForTest sftp = newClient();
      await sftp.connect();
      const String dirName = 'ftpconnect_test_dir';

      expect(await sftp.checkFolderExistence(dirName), isFalse);
      expect(await sftp.createFolderIfNotExist(dirName), isTrue);
      expect(await sftp.checkFolderExistence(dirName), isTrue);
      // Idempotent.
      expect(await sftp.createFolderIfNotExist(dirName), isTrue);
      expect(await sftp.deleteEmptyDirectory(dirName), isTrue);
      expect(await sftp.checkFolderExistence(dirName), isFalse);
    });

    test('deleteEmptyDirectory returns false for a null argument', () async {
      final SftpClientForTest sftp = newClient();
      await sftp.connect();
      expect(await sftp.deleteEmptyDirectory(null), isFalse);
    });

    test('deleteFile returns false for a null argument', () async {
      final SftpClientForTest sftp = newClient();
      await sftp.connect();
      expect(await sftp.deleteFile(null), isFalse);
    });

    test('rename moves a remote file', () async {
      final SftpClientForTest sftp = newClient();
      await sftp.connect();
      final File toUpload = localFile('sftp_rename_src.txt');
      const String src = 'sftp_rename_src.txt';
      const String dst = 'sftp_rename_dst.txt';

      expect(await sftp.uploadFile(toUpload, sRemoteName: src), isTrue);
      expect(await sftp.rename(src, dst), isTrue);
      expect(await sftp.existFile(src), isFalse);
      expect(await sftp.existFile(dst), isTrue);
      expect(await sftp.deleteFile(dst), isTrue);
    });

    test('rename fails when the source is missing', () async {
      final SftpClientForTest sftp = newClient();
      await sftp.connect();
      expect(await sftp.rename('ghost.txt', 'x.txt'), isFalse);
    });

    test('deleteDirectory removes a non-empty folder recursively', () async {
      final SftpClientForTest sftp = newClient();
      await sftp.connect();
      const String root = 'ftpconnect_test_tree';
      expect(await sftp.makeDirectory(root), isTrue);
      expect(await sftp.changeDirectory(root), isTrue);
      expect(await sftp.makeDirectory('sub'), isTrue);

      final File f1 = localFile('t1.txt', content: 'one');
      expect(await sftp.uploadFile(f1, sRemoteName: 't1.txt'), isTrue);
      expect(await sftp.changeDirectory('sub'), isTrue);
      final File f2 = localFile('t2.txt', content: 'two');
      expect(await sftp.uploadFile(f2, sRemoteName: 't2.txt'), isTrue);

      // Back to root and delete the whole tree.
      expect(await sftp.changeDirectory('/'), isTrue);
      expect(await sftp.deleteDirectory(root), isTrue);
      expect(await sftp.checkFolderExistence(root), isFalse);
    });

    test('downloadDirectory mirrors a remote tree locally', () async {
      final SftpClientForTest sftp = newClient();
      await sftp.connect();
      const String remoteRoot = 'ftpconnect_dl';
      expect(await sftp.makeDirectory(remoteRoot), isTrue);
      expect(await sftp.changeDirectory(remoteRoot), isTrue);
      expect(await sftp.makeDirectory('inner'), isTrue);

      final File a = localFile('a.txt', content: 'A');
      expect(await sftp.uploadFile(a, sRemoteName: 'a.txt'), isTrue);
      expect(await sftp.changeDirectory('inner'), isTrue);
      final File b = localFile('b.txt', content: 'B');
      expect(await sftp.uploadFile(b, sRemoteName: 'b.txt'), isTrue);

      expect(await sftp.changeDirectory('/'), isTrue);
      final Directory local = Directory('${tempDir.path}/$remoteRoot');
      expect(await sftp.downloadDirectory(remoteRoot, local), isTrue);

      expect(await File('${local.path}/a.txt').readAsString(), 'A');
      expect(await File('${local.path}/inner/b.txt').readAsString(), 'B');
    });

    test('uploadDirectory mirrors a local tree remotely', () async {
      final SftpClientForTest sftp = newClient();
      await sftp.connect();

      final Directory src = Directory('${tempDir.path}/src')
        ..createSync(recursive: true);
      File('${src.path}/a.txt').writeAsStringSync('A');
      Directory('${src.path}/inner').createSync();
      File('${src.path}/inner/b.txt').writeAsStringSync('B');

      expect(await sftp.uploadDirectory(src, 'remote_up'), isTrue);
      expect(await sftp.existFile('remote_up/a.txt'), isTrue);
      expect(await sftp.existFile('remote_up/inner/b.txt'), isTrue);
    });
  });

  group('in-memory transfers', () {
    test('uploadData then downloadToBytes round-trip', () async {
      final SftpClientForTest sftp = newClient();
      await sftp.connect();
      final Uint8List payload = Uint8List.fromList('in memory'.codeUnits);

      expect(await sftp.uploadData(payload, 'mem.bin'), isTrue);
      expect(await sftp.sizeFile('mem.bin'), payload.length);

      final Uint8List bytes = await sftp.downloadToBytes('mem.bin');
      expect(bytes, payload);
    });

    test('downloadToBytes throws for a missing remote file', () async {
      final SftpClientForTest sftp = newClient();
      await sftp.connect();
      expect(
        () => sftp.downloadToBytes('ghost.bin'),
        throwsA(isA<FTPConnectException>()),
      );
    });
  });

  group('deleteNonEmptyDirectory', () {
    test('removes a non-empty directory recursively', () async {
      final SftpClientForTest sftp = newClient();
      await sftp.connect();
      expect(await sftp.makeDirectory('root'), isTrue);
      final File a = localFile('a.txt', content: 'A');
      expect(await sftp.uploadFile(a, sRemoteName: 'root/a.txt'), isTrue);

      expect(await sftp.deleteNonEmptyDirectory('root'), isTrue);
      expect(await sftp.checkFolderExistence('root'), isFalse);
    });

    test('returns false when the directory is missing', () async {
      final SftpClientForTest sftp = newClient();
      await sftp.connect();
      expect(await sftp.deleteNonEmptyDirectory('ghost'), isFalse);
    });
  });
}
