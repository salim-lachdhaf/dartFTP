/// The (relative) endpoint names exposed by the FastAPI server that performs
/// the real FTP/SFTP work on behalf of the web client.
///
/// The values below are **placeholders**. Update them once the final endpoint
/// names are known — every route is a plain field, so you only have to change
/// it in this single place:
///
/// ```dart
/// const routes = FtpWebRoutes(
///   connect: 'api/v1/sessions',
///   list: 'api/v1/sessions/list',
///   // ...
/// );
/// final client = FtpWebConnect(..., routes: routes);
/// ```
class FtpWebRoutes {
  /// Opens a session against the remote FTP/SFTP server.
  /// Expected to return a session identifier.
  final String connect;

  /// Closes / releases an existing session.
  final String disconnect;

  /// Lists the content of a remote directory.
  final String list;

  /// Returns the current working directory of the session.
  final String currentDirectory;

  /// Changes the current working directory of the session.
  final String changeDirectory;

  /// Creates a remote directory.
  final String makeDirectory;

  /// Removes an (empty) remote directory.
  final String removeDirectory;

  /// Uploads bytes (multipart) to a remote path.
  final String upload;

  /// Downloads the raw bytes of a remote file.
  final String download;

  /// Renames/moves a remote entry.
  final String rename;

  /// Deletes a remote file.
  final String deleteFile;

  /// Checks whether a remote file exists.
  final String exists;

  /// Returns the size (in bytes) of a remote file.
  final String size;

  const FtpWebRoutes({
    this.connect = 'api/v1/connect',
    this.disconnect = 'api/v1/disconnect',
    this.list = 'api/v1/list',
    this.currentDirectory = 'api/v1/pwd',
    this.changeDirectory = 'api/v1/cwd',
    this.makeDirectory = 'api/v1/mkdir',
    this.removeDirectory = 'api/v1/rmdir',
    this.upload = 'api/v1/upload',
    this.download = 'api/v1/download',
    this.rename = 'api/v1/rename',
    this.deleteFile = 'api/v1/delete',
    this.exists = 'api/v1/exists',
    this.size = 'api/v1/size',
  });

  /// Returns a copy of these routes overriding only the provided values.
  FtpWebRoutes copyWith({
    String? connect,
    String? disconnect,
    String? list,
    String? currentDirectory,
    String? changeDirectory,
    String? makeDirectory,
    String? removeDirectory,
    String? upload,
    String? download,
    String? rename,
    String? deleteFile,
    String? exists,
    String? size,
  }) {
    return FtpWebRoutes(
      connect: connect ?? this.connect,
      disconnect: disconnect ?? this.disconnect,
      list: list ?? this.list,
      currentDirectory: currentDirectory ?? this.currentDirectory,
      changeDirectory: changeDirectory ?? this.changeDirectory,
      makeDirectory: makeDirectory ?? this.makeDirectory,
      removeDirectory: removeDirectory ?? this.removeDirectory,
      upload: upload ?? this.upload,
      download: download ?? this.download,
      rename: rename ?? this.rename,
      deleteFile: deleteFile ?? this.deleteFile,
      exists: exists ?? this.exists,
      size: size ?? this.size,
    );
  }
}
