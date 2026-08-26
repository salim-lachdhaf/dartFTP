<h1 align="center">
  Flutter FTP Connect
  <br>
</h1>

<h4 align="center">
   <a href="https://flutter.io" target="_blank">Flutter</a> simple and robust dart FTP Connect Library to interact with FTP and SFTP Servers.
</h4>

<p align="center">
  <a href="https://github.com/salim-lachdhaf/dartFTP/actions"><img src="https://github.com/salim-lachdhaf/dartFTP/workflows/build/badge.svg"/></a>
  <a href="https://pub.dev/packages/ftpconnect"><img src="https://img.shields.io/pub/v/ftpconnect?color=blue"></a>
  <a href="https://codecov.io/gh/salim-lachdhaf/dartFTP"><img src="https://codecov.io/gh/salim-lachdhaf/dartFTP/branch/master/graph/badge.svg"/></a>
  <a href="https://www.buymeacoffee.com/SalimDev"><img src="https://img.shields.io/badge/$-donate-ff69b4.svg"></a>
</p>

<p align="center">
  <a href="#key-features">Key Features</a> •
  <a href="https://github.com/salim-lachdhaf/dartFTP/blob/master/example">Examples</a> •
  <a href="#parameters">Parameters</a> •
  <a href="#sftp-support">SFTP Support</a> •
  <a href="#license">License</a>
</p>


## Key Features
* Supports SFTP/FTP/FTPS/FTPES
* Upload files to the server
* Download files/directories from the server
* List directory contents
* Manage files (rename/delete) and directories (create/delete)
* Completely asynchronous functions
<p>
This library is originally based on <a href="https://github.com/Nexific/dart_ftpclient">dart_ftpclient</a>, which has not been updated in years.
</p>

## Example upload file
### Example 1:
```dart
import 'dart:io';
import 'package:ftpconnect/ftpconnect.dart';

main() async{
    FTPConnect ftpConnect = FTPConnect('example.com',user:'user', pass:'pass');
    File fileToUpload = File('fileToUpload.txt');
    await ftpConnect.connect();
    bool res = await ftpConnect.uploadFile(fileToUpload);
    await ftpConnect.disconnect();
    print(res);
}
```

### Example 2: step by step
```dart
import 'dart:io';
import 'package:ftpconnect/ftpconnect.dart';

main() async{
  FTPConnect ftpConnect = FTPConnect('example.com',user:'user', pass:'pass');
 try {
      File fileToUpload = File('fileToUpload.txt');
      await ftpConnect.connect();
      await ftpConnect.uploadFile(fileToUpload);
      await ftpConnect.disconnect();
    } catch (e) {
      //error
    }
}
```

## Download file
### Example 1:
```dart
import 'dart:io';
import 'package:ftpconnect/ftpconnect.dart';

main() async{
    FTPConnect ftpConnect = FTPConnect('example.com',user:'user', pass:'pass');
    String fileName = 'toDownload.txt';
    await ftpConnect.connect();
    bool res = await ftpConnect.downloadFile(fileName, File('myFileFromFTP.txt'));
    await ftpConnect.disconnect();
    print(res);
}
```

### Example 2: step by step
```dart
import 'dart:io';
import 'package:ftpconnect/ftpconnect.dart';

main() async {
  FTPConnect ftpConnect = FTPConnect('example.com',user:'user', pass:'pass');
 try {
      String fileName = 'toDownload.txt';
      await ftpConnect.connect();
      await ftpConnect.downloadFile(fileName, File('myFileFromFTP.txt'));
      await ftpConnect.disconnect();
    } catch (e) {
      //error
    }
}
```
## Other Features
### Directory functions:
```dart
//Get directory content
ftpConnect.listDirectoryContent();

//Create directory
ftpConnect.makeDirectory('newDir');

//Change directory
ftpConnect.changeDirectory('moveHereDir');

//get current directory
ftpConnect.currentDirectory();

//Delete directory
ftpConnect.deleteDirectory('dirToDelete');

//Delete a non-empty directory (recursively)
ftpConnect.deleteNonEmptyDirectory('dirToDelete');

//check for directory existance
ftpConnect.checkFolderExistence('dirToCheck');

//create a directory if it does not exist
ftpConnect.createFolderIfNotExist('dirToCreate');

//Upload a local directory recursively to the server
ftpConnect.uploadDirectory(Directory('localDir'), 'remoteDir');

//Download a remote directory recursively
ftpConnect.downloadDirectory('remoteDir', Directory('localDir'));
```
### File functions:
```dart
//rename file
ftpConnect.rename('test1.txt', 'test2.txt');

//file size
ftpConnect.sizeFile('test1.txt');

//file existence
ftpConnect.existFile('test1.txt');

//delete file
ftpConnect.deleteFile('test2.zip');

//upload in-memory bytes (no local file needed)
ftpConnect.uploadData(Uint8List.fromList([1, 2, 3]), 'remote.bin');

//download a remote file into memory as bytes
final Uint8List bytes = await ftpConnect.downloadToBytes('remote.bin');
```

## Parameters

### Common parameters (`FTPConnect` and `SFTPConnect`)

|  Property | Description                                               |
| ------------ |-----------------------------------------------------------|
|`host`| Hostname or IP Address                                    |
|`port`| Port number (FTP defaults to 21, FTPS to 990, SFTP to 22) |
|`user`| Username (Defaults to anonymous)                          |
|`pass`| Password if not anonymous login                           |
|`showLog`| Enable Debug Logging (Defaults to false)                  |
|`logger`| Custom logger                                             |
|`timeout`| Timeout in seconds to wait for responses (Defaults to 30) |

### FTP-only parameters (`FTPConnect`)

|  Property | Description                          |
| ------------ |--------------------------------------|
|`securityType`| `SecurityType.ftp` / `ftpes` / `ftps` (Defaults to `ftp`) |

### SFTP-only parameters (`SFTPConnect`)

|  Property | Description                                          |
| ------------ |------------------------------------------------------|
|`privateKey`| PEM/OpenSSH private key content, used instead of `pass` |
|`passphrase`| Passphrase protecting `privateKey` (if any)          |
|`onVerifyHostKey`| Optional host key verification handler           |

More details [here](https://pub.dev/documentation/ftpconnect/latest/ftpconnect/ftpconnect-library.html).

## SFTP support

SFTP is provided by the `SFTPConnect` class, powered by the pure-Dart
[dartssh2](https://pub.dev/packages/dartssh2) package. Both `FTPConnect` and
`SFTPConnect` implement the same `FileTransferClient` interface, so they share
identical method names/signatures and you can swap one for the other by changing
only the instantiated class.

> ℹ️ `dartssh2` is written in pure Dart, so `SFTPConnect` works on every
> platform supported by Dart/Flutter (except web, which has no raw TCP sockets).

```dart
import 'dart:io';
import 'package:ftpconnect/ftpconnect.dart';

main() async {
  SFTPConnect sftpConnect = SFTPConnect(
    'example.com',
    port: 22,
    user: 'user',
    pass: 'pass',
    showLog: true,
  );

  try {
    await sftpConnect.connect();

    // Upload a file
    File fileToUpload = File('fileToUpload.txt');
    await sftpConnect.uploadFile(fileToUpload);

    // List directory content
    List<FTPEntry> content = await sftpConnect.listDirectoryContent('.');
    print(content);

    // Download a file
    await sftpConnect.downloadFile('toDownload.txt', File('myFile.txt'));

    // Manage files/directories
    await sftpConnect.makeDirectory('newDir');
    await sftpConnect.rename('test1.txt', 'test2.txt');
    await sftpConnect.deleteFile('test2.txt');

    await sftpConnect.disconnect();
  } catch (e) {
    // error
  }
}
```

Authenticating with a private key instead of a password:

```dart
SFTPConnect sftpConnect = SFTPConnect(
  'example.com',
  user: 'user',
  privateKey: '''-----BEGIN RSA PRIVATE KEY-----
...
-----END RSA PRIVATE KEY-----''',
  passphrase: 'passphrase-for-key',
);
```

# [View more Examples](https://github.com/salim-lachdhaf/dartFTP/tree/master/example)

## Support

If this plugin was useful to you, helped you to deliver your app, saved you a lot of time, or you just want to support the project, I would be very grateful if you buy me a cup of coffee.

<a href="https://www.buymeacoffee.com/SalimDev" target="_blank"><img src="https://www.buymeacoffee.com/assets/img/custom_images/purple_img.png" alt="Buy Me A Coffee" style="height: 41px !important;width: 174px !important;box-shadow: 0px 3px 2px 0px rgba(190, 190, 190, 0.5) !important;-webkit-box-shadow: 0px 3px 2px 0px rgba(190, 190, 190, 0.5) !important;" ></a>

## License
MIT
