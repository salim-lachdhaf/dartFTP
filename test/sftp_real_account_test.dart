library;

import 'dart:io';
import 'dart:typed_data';

import 'package:ftpconnect/ftpconnect.dart';
import 'package:test/test.dart';

/// Real-network integration test that exercises [FTPConnect] end to end
/// against a live, temporary free FTP server (sftpcloud.io free trial).
///
/// IMPORTANT: this server and its credentials are short-lived (auto-deleted
/// shortly after creation), so this file is meant to be run once, manually,
/// against the live account and then removed - it is NOT intended to be kept
/// in the repository or run in CI, since the credentials below will stop
/// working almost immediately.
void main() {
  const String host = 'eu-central-1.sftpcloud.io';
  const int port = 22;
  const String user = '017d6a8171fc462e89647303d6d6e0df';
  const String pass = 'pHo8uO0oxtbHT4zoSqh0OxPHaoKljJ82';

  const String testFileDir = 'test/SFTP_tmp';
  const String remoteWorkingDir = 'sftpTestTmp';
  late Directory tempDir;
  late SFTPConnect ftpConnect;

  setUp(() async {
    tempDir = Directory(testFileDir)..createSync(recursive: true);
    ftpConnect = SFTPConnect(host, port: port, user: user, pass: pass);
    expect(await ftpConnect.connect(), isTrue);
    // isolate all remote operations inside a dedicated remote working dir
    await ftpConnect.makeDirectory(remoteWorkingDir);
    expect(await ftpConnect.changeDirectory('/$remoteWorkingDir'), isTrue);
  });

  tearDown(() async {
    try {
      await ftpConnect.deleteNonEmptyDirectory('/$remoteWorkingDir');
    } catch (_) {}
    await ftpConnect.disconnect();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('connects to the live free SFTP server', () async {
    expect(await ftpConnect.currentDirectory(), isNotEmpty);
  });

  test('uploads then downloads a file round-trip', () async {
    final File local = File('${tempDir.path}/upload.txt')
      ..writeAsStringSync('hello real ftp server');

    expect(
        await ftpConnect.uploadFile(local, sRemoteName: 'upload.txt'), isTrue);

    expect(await ftpConnect.existFile('upload.txt'), isTrue);

    final File downloaded = File('${tempDir.path}/download.txt');
    expect(await ftpConnect.downloadFile('upload.txt', downloaded), isTrue);
    expect(downloaded.readAsStringSync(), 'hello real ftp server');

    expect(await ftpConnect.deleteFile('upload.txt'), isTrue);
    expect(await ftpConnect.existFile('upload.txt'), isFalse);
  });

  test('uploads and downloads binary data', () async {
    final Uint8List data = Uint8List.fromList('in-memory payload'.codeUnits);
    final File local = File('${tempDir.path}/dummy.bin')
      ..writeAsBytesSync(data);

    expect(
        await ftpConnect.uploadFile(local, sRemoteName: 'memory.bin'), isTrue);

    final File downloaded = File('${tempDir.path}/memory_down.bin');
    expect(await ftpConnect.downloadFile('memory.bin', downloaded), isTrue);
    expect(downloaded.readAsBytesSync(), equals(data));

    expect(await ftpConnect.deleteFile('memory.bin'), isTrue);
  });

  test('creates and removes a remote directory', () async {
    expect(await ftpConnect.makeDirectory('unit_test_dir'), isTrue);
    expect(await ftpConnect.checkFolderExistence('unit_test_dir'), isTrue);

    final entries = await ftpConnect.listDirectoryContent();
    expect(entries.map((e) => e.name), contains('unit_test_dir'));

    expect(await ftpConnect.deleteDirectory('unit_test_dir'), isTrue);
    expect(await ftpConnect.checkFolderExistence('unit_test_dir'), isFalse);
  });

  test('renames a remote file', () async {
    final File local = File('${tempDir.path}/rename_me.txt')
      ..writeAsStringSync('rename me');

    expect(await ftpConnect.uploadFile(local, sRemoteName: 'rename_me.txt'),
        isTrue);

    expect(await ftpConnect.rename('rename_me.txt', 'renamed.txt'), isTrue);

    expect(await ftpConnect.existFile('rename_me.txt'), isFalse);
    expect(await ftpConnect.existFile('renamed.txt'), isTrue);

    expect(await ftpConnect.deleteFile('renamed.txt'), isTrue);
  });

  test('reports the remote file size', () async {
    final Uint8List data = Uint8List.fromList('twelve bytes'.codeUnits);
    final File local = File('${tempDir.path}/sized.bin')
      ..writeAsBytesSync(data);

    expect(
        await ftpConnect.uploadFile(local, sRemoteName: 'sized.bin'), isTrue);

    expect(await ftpConnect.sizeFile('sized.bin'), data.length);

    expect(await ftpConnect.deleteFile('sized.bin'), isTrue);
  });

  test('navigates directories with changeDirectory', () async {
    expect(await ftpConnect.makeDirectory('nav_test_dir'), isTrue);

    final String previousDirectory = await ftpConnect.currentDirectory();
    expect(await ftpConnect.changeDirectory('nav_test_dir'), isTrue);
    expect(await ftpConnect.currentDirectory(), endsWith('nav_test_dir'));

    expect(await ftpConnect.changeDirectory(previousDirectory), isTrue);
    expect(await ftpConnect.currentDirectory(), previousDirectory);

    expect(await ftpConnect.deleteDirectory('nav_test_dir'), isTrue);
  });

  test('uploads and downloads a directory recursively', () async {
    final Directory localUpload = Directory('${tempDir.path}/dir_upload')
      ..createSync(recursive: true);
    File('${localUpload.path}/root.txt').writeAsStringSync('root file');
    Directory('${localUpload.path}/nested').createSync(recursive: true);
    File('${localUpload.path}/nested/child.txt')
        .writeAsStringSync('nested file');

    expect(await ftpConnect.uploadDirectory(localUpload, 'remote_dir_test'),
        isTrue);

    expect(await ftpConnect.checkFolderExistence('remote_dir_test'), isTrue);

    final Directory localDownload = Directory('${tempDir.path}/dir_download');
    expect(await ftpConnect.downloadDirectory('remote_dir_test', localDownload),
        isTrue);
    expect(
        File('${localDownload.path}/root.txt').readAsStringSync(), 'root file');
    expect(File('${localDownload.path}/nested/child.txt').readAsStringSync(),
        'nested file');

    expect(await ftpConnect.deleteNonEmptyDirectory('remote_dir_test'), isTrue);
    expect(await ftpConnect.checkFolderExistence('remote_dir_test'), isFalse);
  });
}
