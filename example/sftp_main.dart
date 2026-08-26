import 'dart:io';

import 'package:ftpconnect/ftpconnect.dart';

/// Example showing how to use [SFTPConnect] to interact with an SFTP server.
///
/// NOTE: SFTP is powered by the `ssh2` plugin which only supports running on
/// Android and iOS within a Flutter application.
void main() async {
  final SFTPConnect sftpConnect = SFTPConnect(
    "example.com",
    port: 22,
    user: "user",
    pass: "pass",
    showLog: true,
  );

  ///an auxiliary function that manage showed log to UI
  Future<void> log(String log) async {
    print(log);
    await Future.delayed(Duration(seconds: 1));
  }

  ///mock a file for the demonstration example
  Future<File> fileMock({fileName = 'FlutterTest.txt', content = ''}) async {
    final Directory directory = Directory('/test')..createSync(recursive: true);
    final File file = File('${directory.path}/$fileName');
    await file.writeAsString(content);
    return file;
  }

  Future<void> uploadStepByStep() async {
    try {
      await log('Connecting to SFTP ...');
      await sftpConnect.connect();
      await sftpConnect.changeDirectory('upload');
      File fileToUpload = await fileMock(
          fileName: 'uploadStepByStep.txt', content: 'uploaded Step By Step');
      await log('Uploading ...');
      await sftpConnect.uploadFile(
        fileToUpload,
        onProgress: (percent, transferred, total) => print('progress: $percent%'),
      );
      await log('file uploaded sucessfully');
      await sftpConnect.disconnect();
    } catch (e) {
      await log('Error: ${e.toString()}');
    }
  }

  Future<void> listContent() async {
    try {
      await log('Connecting to SFTP ...');
      await sftpConnect.connect();
      List<FTPEntry> content = await sftpConnect.listDirectoryContent('.');
      await log(content.map((e) => e.name).toList().toString());
      await sftpConnect.disconnect();
    } catch (e) {
      await log('Error: ${e.toString()}');
    }
  }

  Future<void> downloadStepByStep() async {
    try {
      await log('Connecting to SFTP ...');
      await sftpConnect.connect();
      await log('Downloading ...');
      //here we just prepare a file as a path for the downloaded file
      File downloadedFile = await fileMock(fileName: 'downloadStepByStep.txt');
      await sftpConnect.downloadFile(
        'toDownload.txt',
        downloadedFile,
        onProgress: (percent, transferred, total) => print('progress: $percent%'),
      );
      await log('file downloaded path: ${downloadedFile.path}');
      await sftpConnect.disconnect();
    } catch (e) {
      await log('Downloading FAILED: ${e.toString()}');
    }
  }

  await uploadStepByStep();
  await listContent();
  await downloadStepByStep();
}
