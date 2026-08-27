library;

import 'package:ftpconnect/ftpconnect.dart';
import 'package:test/test.dart';

/// Tests for the typed `fromConfig` constructors (config-driven creation).
void main() {
  group('fromConfig constructors', () {
    test('FTPConnect.fromConfig produces a full native client', () {
      final ftp = FTPConnect.fromConfig(const FtpConfig(
        host: 'example.com',
        user: 'user',
        pass: 'pass',
        securityType: SecurityType.ftpes,
      ));
      expect(ftp, isA<FTPConnect>());
      expect(ftp, isA<FileTransferClient>());
      expect(ftp, isA<FileTransferProtocol>());
      expect(ftp.host, 'example.com');
      expect(ftp.securityType, SecurityType.ftpes);
    });

    test('SFTPConnect.fromConfig produces a full native client', () {
      final sftp = SFTPConnect.fromConfig(const SftpConfig(
        host: 'example.com',
        user: 'user',
        privateKey: 'KEY',
      ));
      expect(sftp, isA<SFTPConnect>());
      expect(sftp, isA<FileTransferClient>());
      expect(sftp.port, 22);
    });

    test('FtpWebClient.fromConfig maps the config with default proxy', () {
      final web = FtpWebClient.fromConfig(const WebConfig(
        host: 'ftp.example.com',
        protocol: WebProtocol.sftp,
      ));
      expect(web, isA<FtpWebClient>());
      expect(web, isA<FileTransferProtocol>());
      expect(web.baseUrl, 'https://me.test.ftpweb.com');
      expect(web.host, 'ftp.example.com');
      expect(web.protocol, WebProtocol.sftp);
    });

    test('FtpWebClient.fromConfig honors custom baseUrl and routes', () {
      final web = FtpWebClient.fromConfig(const WebConfig(
        host: 'ftp.example.com',
        baseUrl: 'https://proxy.local',
        routes: FtpWebRoutes(connect: 'v2/open'),
      ));
      expect(web.baseUrl, 'https://proxy.local');
      expect(web.routes.connect, 'v2/open');
    });
  });
}
