import 'dart:convert';
import 'dart:typed_data';

import 'package:ftpconnect/ftpconnect_web.dart';

/// Example of using the package on the **web** platform.
///
/// On the web the classic [FtpWebClient] talks to a remote HTTP API
/// (a FastAPI backend) that performs the real FTP/SFTP operations, because a
/// browser cannot open raw FTP/SSH sockets itself.
void main() async {
  final FtpWebClient client = FtpWebClient(
    // baseUrl defaults to https://me.test.ftpweb.com — pass baseUrl: '...' to override.
    host: 'ftp.example.com',
    user: 'user',
    pass: 'pass',
    protocol: WebProtocol.sftp, // or WebProtocol.ftp / ftps / ftpes
    showLog: true,
    // Optional: an API auth token sent with every request.
    // headers: {'Authorization': 'Bearer <token>'},
    // Optional: override endpoint names once the final API is known.
    // routes: const FtpWebRoutes(connect: 'api/v1/sessions'),
  );

  try {
    await client.connect();

    // Upload in-memory bytes (no dart:io File on the web).
    final Uint8List data = Uint8List.fromList(utf8.encode('Hello Web FTP!'));
    await client.uploadData(data, 'hello.txt', onProgress: (p, sent, total) {
      print('upload $p% ($sent/$total)');
    });

    // List the current remote directory.
    final List<FTPEntry> entries = await client.listDirectoryContent();
    for (final FTPEntry e in entries) {
      print('${e.type.name}  ${e.name}  ${e.size ?? '-'}');
    }

    // Download a remote file back into memory.
    final Uint8List downloaded = await client.downloadToBytes('hello.txt');
    print('downloaded ${downloaded.length} bytes');

    await client.disconnect();
  } finally {
    client.dispose();
  }
}
