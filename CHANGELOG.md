## [Unreleased]
* **BREAKING**: renamed `deleteEmptyDirectory` to `deleteDirectory` (deletes only an empty directory) and the old recursive `deleteDirectory` to `deleteNonEmptyDirectory` (recursively deletes a folder and its content, returning `false` instead of throwing on failure).
* `deleteNonEmptyDirectory` no longer navigates (`changeDirectory`) into the target directory; it addresses every entry by its full path, so the connection's current working directory is never touched.
* `checkFolderExistence` (FTP & web clients) no longer navigates either: it lists the parent directory and looks for a matching entry instead of `CWD`-ing into the target and back.
* Fixed a bug in `FTPConnect.downloadDirectory`: it restored the working directory with a single `changeDirectory('..')`, which only undoes a *one-level* `CWD`. For a multi-segment `pRemoteDir` (e.g. `/pub/data/reports`) this left the connection's cwd one level short of where it started. `downloadDirectory` is now path-based like `SFTPConnect.downloadDirectory` and never navigates.
* `FTPConnect.uploadDirectory` is now path-based too (matching `SFTPConnect.uploadDirectory`): it no longer issues `PWD`/`CWD` round trips per directory level, addressing every file/folder by its full remote path instead.

## [4.1.0] - 2026.08.27
* **New shared contract** `FileTransferProtocol`: the web-safe, byte/path oriented core interface implemented by every client. `FileTransferClient` now extends it, adding the `dart:io` `File`/`Directory` helpers (native only).
* **Config-driven creation**: added `FtpConfig`/`SftpConfig`/`WebConfig` and the `FTPConnect.fromConfig`, `SFTPConnect.fromConfig`, `FtpWebClient.fromConfig` constructors, so you can build a fully-typed client from a single config object.
* **Web support**: new `dart:io`-free client `FtpWebClient`, exposed through the dedicated `package:ftpconnect/ftpconnect_web.dart` entry point.
  * Delegates FTP/FTPS/FTPES/SFTP operations to a remote HTTP proxy (e.g. a FastAPI backend) so the package works on Flutter Web / browsers, which cannot open raw FTP/SSH sockets.
  * Proxy URL defaults to `https://me.test.ftpweb.com` (override via `baseUrl`).
  * Configurable REST endpoints via `FtpWebRoutes`, injectable HTTP layer (`WebApiClient`) for testing, and byte-based transfers (`uploadData`/`downloadToBytes`).
* Added the `http` dependency (used only by the web client).

## [4.0.0] - 2026.08.27
* **Clean-architecture rewrite** for testability: the network layer is now injected through ports.
  * FTP: `FTPConnect` accepts a `SocketConnector` (defaults to a `dart:io` implementation, `IOSocketConnector`).
  * SFTP: `SFTPConnect` accepts a `SftpConnector` (defaults to a `dartssh2` implementation, `Dartssh2SftpConnector`).
  * The whole client surface is now unit-tested offline against the *real* clients using in-memory fakes (no network, no reimplementation of the client logic).
* Rewrote the FTP control-channel response parser to be stream-based and RFC 959 multi-line aware (replaces the previous polling loop).
* **BREAKING**: `FileTransferClient` is now a pure interface (it no longer holds the connection settings/constructor); each concrete client owns its own configuration.
* **BREAKING**: removed the `dartssh2`-typed `client` / `sftpClient` getters from `SFTPConnect`; inject a custom `SftpConnector`/`SftpAdapter` for advanced use.
* **BREAKING**: `FTPEntry.sftp(SftpName)` replaced by the transport-agnostic `FTPEntry.details(...)` factory (the SFTP adapter maps into it).

## [3.0.0] -  2026.08.27
* Add `uploadDirectory` to recursively upload a local folder to the server (FTP & SFTP)
* Add in-memory transfers: `uploadData(Uint8List, ...)` and `downloadToBytes(...)` (FTP & SFTP)
* Add `deleteNonEmptyDirectory` to recursively delete a folder without throwing when it is missing
* **BREAKING**: remove `listDirectoryContentOnlyNames`; use `listDirectoryContent` and map to `name` instead

## [2.2.0] - 2026.08.27
* Fix FTPS/FTPES data transfers failing with `425` by negotiating the data connection over TLS ([#56](https://github.com/salim-lachdhaf/dartFTP/issues/56), [#50](https://github.com/salim-lachdhaf/dartFTP/issues/50), [#41](https://github.com/salim-lachdhaf/dartFTP/issues/41), [#27](https://github.com/salim-lachdhaf/dartFTP/issues/27), PR [#63](https://github.com/salim-lachdhaf/dartFTP/pull/63))
* Fix `425 Unable to build data connection` by opening the data socket before sending `RETR`/`STOR`/list commands ([#50](https://github.com/salim-lachdhaf/dartFTP/issues/50), PR [#49](https://github.com/salim-lachdhaf/dartFTP/pull/49))
* Fix `RangeError`/`Invalid format` when parsing LIST entries with negative file sizes ([#45](https://github.com/salim-lachdhaf/dartFTP/issues/45), PR [#49](https://github.com/salim-lachdhaf/dartFTP/pull/49))
* Fix `TYPE I`/`TYPE A` not being re-sent after a disconnect/reconnect ([#62](https://github.com/salim-lachdhaf/dartFTP/issues/62))
* Fix transfers hanging on `Start downloading...`/close by destroying data sockets instead of waiting for a graceful TLS shutdown ([#40](https://github.com/salim-lachdhaf/dartFTP/issues/40))
* Fix a crash when reporting progress for zero-byte transfers
* Mask username/password in enabled logs ([#55](https://github.com/salim-lachdhaf/dartFTP/issues/55))
* Fix directory listing for a specific sub-directory (missing space between command and path)
* Fix FTP downloads failing when the local parent folder does not exist
* Always release data sockets and file handles on transfer errors
* **BREAKING**: remove `uploadFileWithRetry`/`downloadFileWithRetry`; `downloadDirectory` no longer takes `pRetryCount`
* Centralize connection settings in the `FileTransferClient` base class; `FTPConnect` and `SFTPConnect` now extend it
* Internal cleanups and performance improvements

## [2.1.0] - 2026.08.26
* Add SFTP support via the new `SFTPConnect`
* Introduce the `FileTransferClient` interface implemented by both `FTPConnect` and `SFTPConnect`
## [2.0.10] - 2025.08.29
* fix lints
## [2.0.9] - 2025.08.29
* fix bug [#43](https://github.com/salim-lachdhaf/dartFTP/issues/43)
## [2.0.7] - 2024.02.25
* fix bug [#18](https://github.com/salim-lachdhaf/dartFTP/issues/18) thnx @ChaseGuru
## [2.0.6] - 2024.02.25
* Update dependencies versions
* Fix lint error
## [2.0.5] - 2023.01.16
* Fix lint error
## [2.0.3] - 2023.01.08
* Fix FTP transferType
## [2.0.2] - 2022.09.19
* Fix lint error
## [2.0.1] - 2022.09.19
* Fix lint error
## [2.0.0] - 2022.09.18
* FixBugs secure mode.
* Improve performance.
* Add new feature: send custom commands
* Remove zip/unzip feature witch depends on external lib
## [1.0.1] - 2022.01.18
* Add secure mode TLS.
* Improve performance.
## [1.0.0] - 2021.05.01
* migrate to null-Safety
* add IPV6 support
* add secure mode support
## [0.2.1] - 2020.12.09
* add onProgress callBack for download and upload file
## [0.2.0] - 2020.11.26
* add delete feature for non empty directory
* fix bug [#7](https://github.com/salim-lachdhaf/dartFTP/issues/7)
* add new command "NLST" to list file/dir inside a directory
* handle IIS servers LIST command response
## [0.1.9] - 2020.11.23
* delete unused resource of test
## [0.1.8] - 2020.11.23
* migration to pure dart
* manage directory content command (LIST, MLSD)
## [0.1.7] - 2020.11.18
* migration to embedding Android
* fix bug [#3](https://github.com/salim-lachdhaf/dartFTP/issues/3)
## [0.1.6] - 2020.05.22
* throw exception if directory doesn't exist
## [0.1.5] - 2020.05.21
* improve directory download
## [0.1.4] - 2020.05.19
* make all functions async
## [0.1.3] - 2020.05.18
* improve Directory download
## [0.1.2] - 2020.05.18
* add test dependency
## [0.1.1] - 2020.05.18
* Add download a folder feature
## [0.1.0] - 2020.05.08
* Update description
## [0.0.1] - 2020.05.07
* First publication
