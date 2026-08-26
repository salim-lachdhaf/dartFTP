///Note that [list] and [mlsd] return content detailed
///BUT [nlst] return only dir/file names inside the given directory
enum ListCommand { nlst, list, mlsd }

enum TransferType { auto, ascii, binary }

enum TransferMode { active, passive }

enum SecurityType { ftp, ftps, ftpes }

extension CommandListTypeEnum on ListCommand {
  String get describeEnum => name;
}
