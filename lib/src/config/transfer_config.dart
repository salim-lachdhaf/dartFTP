import '../domain/enums.dart';
import '../domain/logger.dart';
import '../web/web_api_routes.dart';

/// Immutable, web-safe description of a remote endpoint to connect to.
///
/// It is a [sealed] hierarchy consumed by the `fromConfig` constructors:
///
/// * [FtpConfig]  -> `FTPConnect.fromConfig`   (FTP / FTPS / FTPES)
/// * [SftpConfig] -> `SFTPConnect.fromConfig`  (SFTP)
/// * [WebConfig]  -> `FtpWebClient.fromConfig` (HTTP proxy backend)
///
/// Configs carry only plain data. For advanced dependency injection (custom
/// socket/SFTP/HTTP layers) instantiate the concrete client classes directly.
sealed class TransferConfig {
  /// Hostname or IP address of the remote server.
  final String host;

  /// Remote port. When `null` the concrete client uses its protocol default.
  final int? port;

  /// Username (defaults to `anonymous`).
  final String user;

  /// Password (ignored by SFTP key-based auth).
  final String pass;

  /// Timeout in seconds applied to the connection/operations.
  final int timeout;

  /// Enable debug logging.
  final bool showLog;

  /// Optional custom [Logger].
  final Logger? logger;

  const TransferConfig({
    required this.host,
    this.port,
    this.user = 'anonymous',
    this.pass = '',
    this.timeout = 30,
    this.showLog = false,
    this.logger,
  });
}

/// Configuration for a plain FTP / FTPS / FTPES connection.
///
/// Produces an `FTPConnect` instance (native platforms only).
class FtpConfig extends TransferConfig {
  final SecurityType securityType;
  final bool supportIPV6;
  final ListCommand listCommand;
  final TransferMode transferMode;
  final TransferType transferType;

  const FtpConfig({
    required super.host,
    super.port,
    super.user,
    super.pass,
    super.timeout,
    super.showLog,
    super.logger,
    this.securityType = SecurityType.ftp,
    this.supportIPV6 = false,
    this.listCommand = ListCommand.mlsd,
    this.transferMode = TransferMode.passive,
    this.transferType = TransferType.auto,
  });
}

/// Configuration for an SFTP (SSH) connection.
///
/// Produces an `SFTPConnect` instance (native platforms only).
class SftpConfig extends TransferConfig {
  /// PEM/OpenSSH private key content, used instead of [pass].
  final String? privateKey;

  /// Passphrase protecting [privateKey] (if any).
  final String? passphrase;

  const SftpConfig({
    required super.host,
    super.port,
    super.user,
    super.pass,
    super.timeout,
    super.showLog,
    super.logger,
    this.privateKey,
    this.passphrase,
  });
}

/// Configuration for the HTTP proxy backend used on the web (and any platform).
///
/// Produces an `FtpWebClient` that delegates the real FTP/SFTP work to the
/// proxy server at [baseUrl].
class WebConfig extends TransferConfig {
  /// Default proxy/API server URL used when none is supplied.
  static const String defaultBaseUrl = 'https://me.test.ftpweb.com';

  /// Base URL of the proxy/API server (defaults to the package default proxy).
  final String baseUrl;

  /// Which protocol the proxy should speak to [host] on our behalf.
  final WebProtocol protocol;

  /// Optional private key content for SFTP key-based auth (forwarded to proxy).
  final String? privateKey;

  /// Optional passphrase protecting [privateKey].
  final String? passphrase;

  /// Endpoint names of the proxy API.
  final FtpWebRoutes routes;

  /// Extra HTTP headers (e.g. an `Authorization` token).
  final Map<String, String>? headers;

  const WebConfig({
    required super.host,
    this.baseUrl = defaultBaseUrl,
    super.port,
    super.user,
    super.pass,
    super.timeout,
    super.showLog,
    super.logger,
    this.protocol = WebProtocol.ftp,
    this.privateKey,
    this.passphrase,
    this.routes = const FtpWebRoutes(),
    this.headers,
  });
}
