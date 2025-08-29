@Timeout(Duration(minutes: 20))
library;

import 'dart:io';

import 'package:ftpconnect/ftpconnect.dart';
import 'package:ftpconnect/src/ftp_reply.dart';
import 'package:test/test.dart';

void main() async {
  final FTPConnect ftpConnect = FTPConnect(
    "ftp.dlptest.com",
    user: "dlpuser",
    pass: "rNrKYTX9g7z3RgJRmxWuGHbeu",
    showLog: true,
  );
  ftpConnect.supportIPV6 = true;

  final FTPConnect ftpsConnect = FTPConnect(
    "test.rebex.net",
    user: "demo",
    pass: "password",
    securityType: SecurityType.ftps,
    showLog: true,
  );
  ftpConnect.supportIPV6 = true;

  final FTPConnect ftpConnectSecured = FTPConnect(
    "ftp.dlptest.com",
    user: "dlpuser",
    pass: "rNrKYTX9g7z3RgJRmxWuGHbeu",
    showLog: true,
    port: 21,
    securityType: SecurityType.ftpes,
  );
  ftpConnectSecured.supportIPV6 = true;
  // final FTPConnect _ftpConnect2 = new FTPConnect(
  //   "demo.wftpserver.com",
  //   user: "demo",
  //   pass: "demo",
  //   debug: true,
  //   timeout: 60,
  // );

  const String testFileDir = 'test/test_res_files';
  const String localUploadFile = 'test_upload.txt';
  const String localDownloadFile = 'test_download.txt';

  ///mock a file for the demonstration example
  Future<File> fileMock({fileName = localUploadFile}) async {
    final Directory directory = Directory(testFileDir);
    await directory.create(recursive: true);
    final File file = File('${directory.path}/$fileName');
    await file.create(recursive: true);
    await file.writeAsString(DateTime.now().toString());
    return file;
  }

  test('test ftpConnect', () async {
    expect(await ftpConnect.connect(), equals(true));
    expect(await ftpConnect.sendCustomCommand("FEAT"), isA<FTPReply>());
    expect(await ftpConnect.disconnect(), equals(true));
    expect(await ftpConnectSecured.connect(), equals(true));
    expect(await ftpConnectSecured.disconnect(), equals(true));
    final FTPConnect ftpConnectNoLog = FTPConnect("users.on.net",
        user: "pvpt", pass: "Lachdhaf", securityType: SecurityType.ftpes);
    expect(() async => await ftpConnectNoLog.connect(),
        throwsA(isA<FTPConnectException>()));
  });

  test('test ftps', () async {
    expect(await ftpsConnect.connect(), equals(true));
  });

  test('test ftpConnect No log', () async {
    final FTPConnect ftpConnectNoLog0 = FTPConnect("users.on.net",
        user: "pvpt", pass: "Lachdhaf", showLog: true);
    expect(await ftpConnectNoLog0.connect(), equals(true));
    await ftpConnectNoLog0.currentDirectory();
    ftpConnectNoLog0.listCommand = ListCommand.list;
    ftpConnectNoLog0.supportIPV6 = false;
    await ftpConnectNoLog0.setTransferType(TransferType.binary);
    await ftpConnectNoLog0.listDirectoryContent();
    await ftpConnectNoLog0.setTransferType(TransferType.ascii);
    ftpConnectNoLog0.transferMode = TransferMode.passive;
    await ftpConnectNoLog0.listDirectoryContent();

    expect(await ftpConnectNoLog0.disconnect(), equals(true));
  });

  test('test ftpConnect timeOut', () async {
    final FTPConnect ftpConnectTimeOut = FTPConnect("speedtest.tele2.net",
        user: "xxxcx", pass: "xxxx", securityType: SecurityType.ftpes);

    expect(() async => await ftpConnectTimeOut.connect(),
        throwsA(isA<FTPConnectException>()));
  });

  test('test ftpConnect error connect', () async {
    FTPConnect ftpConnectErrorConnect =
        FTPConnect("demo.wftpserver.com", user: "xxxx", pass: "xxxx");
    try {
      await ftpConnectErrorConnect.connect();
    } catch (e) {
      expect(e is FTPConnectException, equals(true));
    }
    ftpConnectErrorConnect = FTPConnect("xxxx.wwww.com");
    try {
      await ftpConnectErrorConnect.connect();
    } catch (e) {
      expect(e is FTPConnectException, equals(true));
    }
  });

  test('test ftpConnect Dir functions', () async {
    expect(await ftpConnect.connect(), equals(true));

    expect(await ftpConnect.currentDirectory(), equals("/"));

    String dirName = 'no_name_test';
    //make sure that the folder does not exist
    expect(await ftpConnect.checkFolderExistence("dirName${DateTime.now()}"),
        equals(false));
    await ftpConnect.deleteEmptyDirectory(dirName);
    //create a new dir NoName and change dir to that dir
    expect(await ftpConnect.createFolderIfNotExist(dirName), equals(true));
    //change directory
    expect(await ftpConnect.changeDirectory(dirName), equals(true));
    //back to root
    await ftpConnect.changeDirectory('..');
    //delete directory
    expect(await ftpConnect.deleteEmptyDirectory(dirName), equals(true));
    //try delete a non epty dir => crash because permission denied
    try {
      ftpConnect.listCommand = ListCommand.list;
      await ftpConnect.deleteDirectory("../upload");
    } catch (e) {
      expect(e is FTPConnectException, equals(true));
    }

    //change directory to root
    expect(await ftpConnect.changeDirectory('/'), equals(true));
    //make directory => false because the folder is protected
    expect(await ftpConnect.createFolderIfNotExist(dirName), equals(true));
    //change directory to root
    expect(await ftpConnect.changeDirectory('/$dirName'), equals(true));
    expect(await ftpConnect.createFolderIfNotExist('newDir'), equals(true));

    String fileName = 'my_file_test.txt';
    expect(await ftpConnect.uploadFile(await fileMock(fileName: fileName)),
        equals(true));

    //change directory to root
    expect(await ftpConnect.changeDirectory('/'), equals(true));

    //download a dir => false to prevent long loading duration of the test
    bool res = await ftpConnect.downloadDirectory(
      dirName,
      Directory(testFileDir)..createSync(),
    );
    expect(res, equals(true));

    //change directory to root
    expect(await ftpConnect.changeDirectory('/'), equals(true));
    await ftpConnect.deleteDirectory(dirName);

    try {
      await ftpConnect.downloadDirectory(
        '/nonExist',
        Directory(testFileDir)..createSync(),
      );
    } catch (e) {
      expect(e is FTPConnectException, equals(true));
    }

    //close connexion
    expect(await ftpConnect.disconnect(), equals(true));
  });

  test('test ftpConnect File functions', () async {
    expect(await ftpConnect.connect(), equals(true));
    String dirName1 = 'no_name_test_file_folder';
    String fileName = 'my_file.txt';
    //change to the directory where we can work
    expect(await ftpConnect.createFolderIfNotExist(dirName1), equals(true));

    //test upload file (this file will be automatically deleted after upload by the server)
    void testUploadProgress(double p, int r, int fileSize) {
      print('uploaded :$r byte =========> $p%');
    }

    expect(
        await ftpConnect.uploadFile(await fileMock(fileName: fileName),
            onProgress: testUploadProgress),
        equals(true));

    expect(
        await ftpConnect.uploadFileWithRetry(await fileMock(fileName: fileName),
            onProgress: testUploadProgress),
        equals(true));

    //check for file existence
    expect(await ftpConnect.existFile(fileName), equals(true));
    //test download file
    void testDownloadProgress(double p, int r, int fileSize) {
      print('downloaded :$r byte =========> $p%');
    }

    expect(
        await ftpConnect.downloadFile(
            fileName, File('$testFileDir/$localDownloadFile'),
            onProgress: testDownloadProgress),
        equals(true));

    expect(
        await ftpConnect.downloadFileWithRetry(
            fileName, File('$testFileDir/$localDownloadFile'),
            onProgress: testDownloadProgress),
        equals(true));

    //test download non exist file
    var remoteFile = 'not_exist.zip';
    try {
      await ftpConnect.downloadFile(remoteFile, File('dist'));
    } catch (e) {
      expect(e is FTPConnectException, equals(true));
      expect(
          (e as FTPConnectException).message ==
              'Remote File $remoteFile does not exist!',
          equals(true));
    }
    //get file size
    expect(await ftpConnect.sizeFile('../notExist.zip'), equals(-1));

    //test rename file (false because the server is protected)
    expect(await ftpConnect.rename(fileName, '${fileName}_renamed.txt'),
        equals(true));

    //test delete file (false because the server is protected)
    expect(
        await ftpConnect.deleteFile('${fileName}_renamed.txt'), equals(true));

    expect(await ftpConnect.disconnect(), equals(true));
  });

  test('test FTP Entry Class', () {
    //test LIST COMMAND with standard response
    var data = '-rw-------    1 105      108        1024 Jan 10 11:50 file.zip';
    FTPEntry ftpEntry = FTPEntry.parse(data, ListCommand.list);
    expect(ftpEntry.type, equals(FTPEntryType.file));
    expect(ftpEntry.permission, equals('rw-------'));
    expect(ftpEntry.name, equals('file.zip'));
    expect(ftpEntry.owner, equals('105'));
    expect(ftpEntry.group, equals('108'));
    expect(ftpEntry.size, equals(1024));
    expect(ftpEntry.modifyTime is DateTime, equals(true));

    //test LIS COMMAND with IIS servers
    data = '02-11-15  03:05PM      <DIR>     1410887680 directory';
    ftpEntry = FTPEntry.parse(data, ListCommand.list);
    expect(ftpEntry.type, equals(FTPEntryType.dir));
    expect(ftpEntry.name, equals('directory'));
    expect(ftpEntry.modifyTime is DateTime, equals(true));

    data = '02-11-15  03:05PM               1410887680 directory';
    ftpEntry = FTPEntry.parse(data, ListCommand.list);
    expect(ftpEntry.type, equals(FTPEntryType.file));
    expect(ftpEntry.name, equals('directory'));
    expect(ftpEntry.modifyTime is DateTime, equals(true));

    var data2 = 'drw-------    1 105      108        1024 Jan 10 11:50 dir/';
    ftpEntry = FTPEntry.parse(data2, ListCommand.list);
    expect(ftpEntry.type, equals(FTPEntryType.dir));

    var data3 = ftpEntry.toString();
    ftpEntry = FTPEntry.parse(data3, ListCommand.mlsd);
    expect(ftpEntry.type, equals(FTPEntryType.dir));
    expect(ftpEntry.owner, equals('105'));
    expect(ftpEntry.group, equals('108'));
    expect(ftpEntry.size, equals(1024));
    expect(ftpEntry.modifyTime is DateTime, equals(true));

    var data4 = 'drw-------    1 105';
    ftpEntry = FTPEntry.parse(data4, ListCommand.mlsd);
    expect(ftpEntry.name, equals(data4));

    expect(() => FTPEntry.parse(data4, ListCommand.list),
        throwsA(isA<FTPConnectException>()));

    String data5 = "";
    expect(() => FTPEntry.parse(data5, ListCommand.mlsd),
        throwsA(isA<FTPConnectException>()));
    expect(() => FTPEntry.parse(data5, ListCommand.list),
        throwsA(isA<FTPConnectException>()));
  });

  test('test FTPConnect exception', () {
    String msgError = 'message';
    String msgResponse = 'reply is here';
    FTPConnectException exception = FTPConnectException(msgError);
    expect(exception.message, equals(msgError));
    exception = FTPConnectException(msgError, msgResponse);
    expect(exception.message, equals(msgError));
    expect(exception.response, equals(msgResponse));
    expect(exception.toString(),
        equals('FTPConnectException: $msgError (Response: $msgResponse)'));
  });
}
