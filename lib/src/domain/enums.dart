/// Command used to list the content of a remote directory.
///
/// Note that [list] and [mlsd] return detailed entries, while [nlst] returns
/// only the names of the files/directories inside the given directory.
enum ListCommand { nlst, list, mlsd }

/// Transfer representation negotiated with the server.
enum TransferType { auto, ascii, binary }

/// How the data connection is established.
///
/// Only [passive] is currently supported by the FTP client.
enum TransferMode { active, passive }

/// Security layer used by the FTP client.
enum SecurityType { ftp, ftps, ftpes }

/// The remote protocol the web client asks the API server to speak on its
/// behalf (the browser cannot open raw FTP/SSH sockets itself).
enum WebProtocol { ftp, ftps, ftpes, sftp }

/// The kind of a remote entry returned when listing a directory.
enum FTPEntryType { file, dir, link, unknown }

extension ListCommandName on ListCommand {
  /// The FTP command keyword (`NLST`, `LIST` or `MLSD`).
  String get command => name.toUpperCase();
}

extension WebProtocolName on WebProtocol {
  /// Wire value sent to the API server (`ftp`, `ftps`, `ftpes`, `sftp`).
  String get wireName => name;
}

extension SecurityTypeToWebProtocol on SecurityType {
  /// The equivalent [WebProtocol] used when routing this FTP security type
  /// through the web proxy backend.
  WebProtocol get webProtocol => switch (this) {
        SecurityType.ftp => WebProtocol.ftp,
        SecurityType.ftps => WebProtocol.ftps,
        SecurityType.ftpes => WebProtocol.ftpes,
      };
}

extension FtpEntryTypeName on FTPEntryType {
  String get describeEnum => name;
}
