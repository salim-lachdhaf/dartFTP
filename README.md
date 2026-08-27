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
* Web support (via an HTTP API backend) with `FtpWebClient`
* Upload files to the server
* Download files/directories from the server
* List directory contents
* Manage files (rename/delete) and directories (create/delete)
* Completely asynchronous functions
<p>
This library is originally based on <a href="https://github.com/Nexific/dart_ftpclient">dart_ftpclient</a>, which has not been updated in years.
</p>

## Example upload file
### Example 1: config-driven, protocol-agnostic (recommended)
Build the client from a config with `fromConfig`. On native, both `FTPConnect`
and `SFTPConnect` implement `FileTransferClient`, so you can swap FTP/SFTP by
changing only the config and keep the full `File`-based API:
```dart
import 'dart:io';
import 'package:ftpconnect/ftpconnect.dart';

main() async {
  final FileTransferClient client = FTPConnect.fromConfig(
    FtpConfig(host: 'example.com', user: 'user', pass: 'pass'),
    // swap to SFTP with: SFTPConnect.fromConfig(SftpConfig(host: 'example.com', ...))
  );
  await client.connect();
  bool res = await client.uploadFile(File('fileToUpload.txt'));
  await client.disconnect();
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
### Example 1: config-driven (recommended)
```dart
import 'dart:io';
import 'package:ftpconnect/ftpconnect.dart';

main() async {
  final FileTransferClient client = FTPConnect.fromConfig(
    FtpConfig(host: 'example.com', user: 'user', pass: 'pass'),
  );
  await client.connect();
  bool res = await client.downloadFile('toDownload.txt', File('myFileFromFTP.txt'));
  await client.disconnect();
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

## Config-driven creation (`fromConfig`)

Instead of long named-parameter constructors, you can describe an endpoint with a
config object and build the client with a `fromConfig` constructor. Each returns
the **fully-typed** concrete client (with its complete API):

```dart
import 'package:ftpconnect/ftpconnect.dart';

final ftp  = FTPConnect.fromConfig(FtpConfig(host: 'example.com', user: 'u', pass: 'p'));
final sftp = SFTPConnect.fromConfig(SftpConfig(host: 'example.com', privateKey: '...'));
final web  = FtpWebClient.fromConfig(WebConfig(host: 'ftp.example.com', protocol: WebProtocol.sftp));
```

* `FtpConfig`  → `FTPConnect`   (FTP / FTPS / FTPES)
* `SftpConfig` → `SFTPConnect`  (SFTP)
* `WebConfig`  → `FtpWebClient` (HTTP proxy backend, see [Web support](#web-support))

On native, `FTPConnect` and `SFTPConnect` both implement `FileTransferClient`
(which extends the web-safe `FileTransferProtocol` and adds the `dart:io`
`File`/`Directory` helpers), so you can write protocol-agnostic code that still
has the full API:

```dart
final FileTransferClient client = useSftp
    ? SFTPConnect.fromConfig(SftpConfig(host: host, user: user, pass: pass))
    : FTPConnect.fromConfig(FtpConfig(host: host, user: user, pass: pass));
await client.connect();
await client.uploadFile(File('local.txt'));
```

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

## Web support

Browsers (and Flutter Web) cannot open raw FTP or SSH/TCP sockets, so the
default `FTPConnect` / `SFTPConnect` clients — which rely on `dart:io` — do not
run on the web. To support the web platform, the package ships a separate,
`dart:io`-free client, **`FtpWebClient`**, that delegates every FTP/SFTP
operation to a remote HTTP API (for example a FastAPI backend) which performs
the actual transfers on the server side.

Import the dedicated web entry point instead of the default one:

```dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:ftpconnect/ftpconnect_web.dart';

main() async {
  final client = FtpWebClient(
    // baseUrl defaults to https://me.test.ftpweb.com (the proxy/API server).
    // Pass baseUrl: '...' to point at a different proxy.
    host: 'ftp.example.com',      // remote FTP/SFTP host the proxy connects to
    user: 'user',
    pass: 'pass',
    protocol: WebProtocol.sftp,   // ftp | ftps | ftpes | sftp
    showLog: true,
    // headers: {'Authorization': 'Bearer <token>'}, // optional API auth
  );

  try {
    await client.connect();

    // Upload in-memory bytes (there is no dart:io File on the web).
    final Uint8List data = Uint8List.fromList(utf8.encode('Hello Web FTP!'));
    await client.uploadData(data, 'hello.txt');

    // List a remote directory.
    final content = await client.listDirectoryContent('.');
    print(content);

    // Download a remote file back into memory.
    final bytes = await client.downloadToBytes('hello.txt');

    await client.disconnect();
  } finally {
    client.dispose();
  }
}
```

### Configuring the API endpoints

The web client talks to your server through a small set of REST endpoints whose
names are configurable via `FtpWebRoutes` (the defaults are placeholders). Once
your final endpoint names are known, override only what you need:

```dart
final client = FtpWebClient(
  host: 'ftp.example.com',
  routes: const FtpWebRoutes(
    connect: 'api/v1/sessions',
    upload: 'api/v1/sessions/upload',
    // ...only override the ones that differ from the defaults
  ),
);
```

> The proxy `baseUrl` defaults to `https://me.test.ftpweb.com`. The `host` is the
> **destination** FTP/SFTP server (forwarded to the proxy); the proxy — not the
> browser — opens the actual FTP/SFTP connection.

Because a browser upload is a single multipart request, `FtpWebClient` supports
the byte/path oriented subset of the API (`uploadData`, `downloadToBytes`,
listing, `mkdir`, `rename`, `delete`, `exists`, `size`, ...). The `dart:io`
`File`/`Directory` helpers of `FTPConnect`/`SFTPConnect` are intentionally not
part of the web client — use `Uint8List` bytes instead.


## Support

If this plugin was useful to you, helped you to deliver your app, saved you a lot of time, or you just want to support the project, I would be very grateful if you buy me a cup of coffee.

<a href="https://www.buymeacoffee.com/SalimDev" target="_blank"><img src="https://www.buymeacoffee.com/assets/img/custom_images/purple_img.png" alt="Buy Me A Coffee" style="height: 41px !important;width: 174px !important;box-shadow: 0px 3px 2px 0px rgba(190, 190, 190, 0.5) !important;-webkit-box-shadow: 0px 3px 2px 0px rgba(190, 190, 190, 0.5) !important;" ></a>

## License
MIT
