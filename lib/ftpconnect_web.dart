/// Web-safe entry point of the `ftpconnect` package.
///
/// Browsers (and Flutter Web) cannot open raw FTP/SSH sockets, so the regular
/// `package:ftpconnect/ftpconnect.dart` library — which relies on `dart:io` —
/// does not compile for the web platform.
///
/// Import this library instead when targeting the web. It exposes an
/// HTTP-backed client ([FtpWebClient]) that delegates every FTP/SFTP operation
/// to a remote API server (e.g. a FastAPI backend), plus the shared, transport
/// agnostic domain types.
///
/// ```dart
/// import 'package:ftpconnect/ftpconnect_web.dart';
///
/// final client = FtpWebClient(
///   'https://me.test.ftpweb.com',
///   host: 'ftp.example.com',
///   user: 'user',
///   pass: 'pass',
///   protocol: WebProtocol.sftp,
/// );
/// ```
library;

// Domain (entities, contracts, value types) — all `dart:io`-free.
export 'src/domain/entities/ftp_entry.dart';
export 'src/domain/entities/ftp_reply.dart';
export 'src/domain/enums.dart';
export 'src/domain/exceptions.dart';
export 'src/domain/file_transfer_protocol.dart';
export 'src/domain/logger.dart';
export 'src/domain/progress.dart';

// Config objects.
export 'src/config/transfer_config.dart';

// Web client.
export 'src/web/ftp_web_connect.dart';
export 'src/web/web_api_client.dart';
export 'src/web/web_api_routes.dart';
