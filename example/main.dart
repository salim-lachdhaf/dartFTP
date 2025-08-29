import 'dart:io';

import 'package:ftpconnect/ftpconnect.dart';

void main() async {
  final FTPConnect ftpConnect = FTPConnect(
    "users.on.net",
    user: "pvpt",
    pass: "Lachdhaf",
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
      await log('Connecting to FTP ...');
      await ftpConnect.connect();
      await ftpConnect.changeDirectory('upload');
      File fileToUpload = await fileMock(
          fileName: 'uploadStepByStep.txt', content: 'uploaded Step By Step');
      await log('Uploading ...');
      await ftpConnect.uploadFile(fileToUpload);
      await log('file uploaded sucessfully');
      await ftpConnect.disconnect();
    } catch (e) {
      await log('Error: ${e.toString()}');
    }
  }

  Future<void> uploadWithRetry() async {
    try {
      File fileToUpload = await fileMock(
          fileName: 'uploadwithRetry.txt', content: 'uploaded with Retry');
      await log('Uploading ...');
      await ftpConnect.connect();
      await ftpConnect.changeDirectory('upload');
      bool res =
          await ftpConnect.uploadFileWithRetry(fileToUpload, pRetryCount: 2);
      await log('file uploaded: ${res ? 'SUCCESSFULLY' : 'FAILED'}');
      await ftpConnect.disconnect();
    } catch (e) {
      await log('Downloading FAILED: ${e.toString()}');
    }
  }

  Future<void> downloadWithRetry() async {
    try {
      await log('Downloading ...');

      String fileName = '../512KB.zip';
      await ftpConnect.connect();
      //here we just prepare a file as a path for the downloaded file
      File downloadedFile = await fileMock(fileName: 'downloadwithRetry.txt');
      bool res = await ftpConnect
          .downloadFileWithRetry(fileName, downloadedFile, pRetryCount: 2);
      await log(
          'file downloaded  ${res ? 'path: ${downloadedFile.path}' : 'FAILED'}');
      await ftpConnect.disconnect();
    } catch (e) {
      await log('Downloading FAILED: ${e.toString()}');
    }
  }

  Future<void> downloadStepByStep() async {
    try {
      await log('Connecting to FTP ...');

      await ftpConnect.connect();

      await log('Downloading ...');
      String fileName = '../512KB.zip';

      //here we just prepare a file as a path for the downloaded file
      File downloadedFile = await fileMock(fileName: 'downloadStepByStep.txt');
      await ftpConnect.downloadFile(fileName, downloadedFile);
      await log('file downloaded path: ${downloadedFile.path}');
      await ftpConnect.disconnect();
    } catch (e) {
      await log('Downloading FAILED: ${e.toString()}');
    }
  }

  await uploadStepByStep();
  await uploadWithRetry();
  await downloadWithRetry();
  await downloadStepByStep();
}
