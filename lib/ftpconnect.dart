/// A simple and robust Dart FTP / FTPS / FTPES / SFTP client library.
library;

// Domain (entities, contracts, value types)
export 'src/domain/entities/ftp_entry.dart';
export 'src/domain/entities/ftp_reply.dart';
export 'src/domain/enums.dart';
export 'src/domain/exceptions.dart';
export 'src/domain/file_transfer_protocol.dart';
export 'src/domain/file_transfer_client.dart';
export 'src/domain/logger.dart';
export 'src/domain/progress.dart';

// Config objects (typed `fromConfig` alternative)
export 'src/config/transfer_config.dart';

// FTP
export 'src/ftp/ftp_connect.dart';
export 'src/ftp/socket_connector.dart';

// SFTP
export 'src/sftp/sftp_connect.dart';
export 'src/sftp/sftp_adapter.dart';

// Web (HTTP proxy backend; usable from native too)
export 'src/web/ftp_web_connect.dart';
export 'src/web/web_api_client.dart';
export 'src/web/web_api_routes.dart';

// Infrastructure (default implementations, exposed for advanced use/injection)
export 'src/infrastructure/io_socket_connector.dart';
export 'src/infrastructure/dartssh2_sftp_adapter.dart';
