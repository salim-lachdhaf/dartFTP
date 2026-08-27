/// Progress callback used by upload/download operations.
///
/// [progressInPercent] is the completed percentage (0 -> 100),
/// [totalTransferred] the number of bytes transferred so far and [fileSize] the
/// total size of the file in bytes.
typedef FileProgress = void Function(
  double progressInPercent,
  int totalTransferred,
  int fileSize,
);
