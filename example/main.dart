import 'dart:io';

import 'package:ftpconnect/ftpconnect.dart';

void main() async {
  final FTPConnect _ftpConnect = new FTPConnect(
    "users.on.net",
    user: "pvpt",
    pass: "Lachdhaf",
    showLog: true,
  );

  ///an auxiliary function that manage showed log to UI
  Future<void> _log(String log) async {
    print(log);
    await Future.delayed(Duration(seconds: 1));
  }

  ///mock a file for the demonstration example
  Future<File> _fileMock({fileName = 'FlutterTest.txt', content = ''}) async {
    final Directory directory = Directory('/test')..createSync(recursive: true);
    final File file = File('${directory.path}/$fileName');
    await file.writeAsString(content);
    return file;
  }

  Future<void> _uploadStepByStep() async {
    try {
      await _log('Connecting to FTP ...');
      await _ftpConnect.connect();
      await _ftpConnect.changeDirectory('upload');
      File fileToUpload = await _fileMock(
          fileName: 'uploadStepByStep.txt', content: 'uploaded Step By Step');
      await _log('Uploading ...');
      await _ftpConnect.uploadFile(fileToUpload);
      await _log('file uploaded sucessfully');
      await _ftpConnect.disconnect();
    } catch (e) {
      await _log('Error: ${e.toString()}');
    }
  }

  Future<void> _uploadWithRetry() async {
    try {
      File fileToUpload = await _fileMock(
          fileName: 'uploadwithRetry.txt', content: 'uploaded with Retry');
      await _log('Uploading ...');
      await _ftpConnect.connect();
      await _ftpConnect.changeDirectory('upload');
      bool res =
          await _ftpConnect.uploadFileWithRetry(fileToUpload, pRetryCount: 2);
      await _log('file uploaded: ' + (res ? 'SUCCESSFULLY' : 'FAILED'));
      await _ftpConnect.disconnect();
    } catch (e) {
      await _log('Downloading FAILED: ${e.toString()}');
    }
  }

  Future<void> _downloadWithRetry() async {
    try {
      await _log('Downloading ...');

      String fileName = '../512KB.zip';
      await _ftpConnect.connect();
      //here we just prepare a file as a path for the downloaded file
      File downloadedFile = await _fileMock(fileName: 'downloadwithRetry.txt');
      bool res = await _ftpConnect
          .downloadFileWithRetry(fileName, downloadedFile, pRetryCount: 2);
      await _log('file downloaded  ' +
          (res ? 'path: ${downloadedFile.path}' : 'FAILED'));
      await _ftpConnect.disconnect();
    } catch (e) {
      await _log('Downloading FAILED: ${e.toString()}');
    }
  }

  Future<void> _downloadStepByStep() async {
    try {
      await _log('Connecting to FTP ...');

      await _ftpConnect.connect();

      await _log('Downloading ...');
      String fileName = '../512KB.zip';

      //here we just prepare a file as a path for the downloaded file
      File downloadedFile = await _fileMock(fileName: 'downloadStepByStep.txt');
      await _ftpConnect.downloadFile(fileName, downloadedFile);
      await _log('file downloaded path: ${downloadedFile.path}');
      await _ftpConnect.disconnect();
    } catch (e) {
      await _log('Downloading FAILED: ${e.toString()}');
    }
  }

  await _uploadStepByStep();
  await _uploadWithRetry();
  await _downloadWithRetry();
  await _downloadStepByStep();
}
