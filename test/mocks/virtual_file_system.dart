import 'dart:typed_data';

import 'package:path/path.dart' as p;

/// A single immediate child of a directory in a [VirtualFileSystem].
class VfsEntry {
  final String name;
  final bool isDirectory;
  final int size;

  const VfsEntry(this.name, this.isDirectory, this.size);
}

/// A tiny in-memory POSIX-like filesystem used to back the offline
/// [FileTransferClient] mocks ([FtpClientForTest] and [SftpClientForTest]).
///
/// Paths are absolute, `/`-separated and normalized. The root `/` always
/// exists. It intentionally implements just the behavior the mocks need
/// (create/remove/rename/list/read/write) with the same success/failure
/// semantics a real FTP/SFTP server would expose, so the client logic under
/// test behaves exactly as it would against a live server.
class VirtualFileSystem {
  final Set<String> _dirs = <String>{'/'};
  final Map<String, Uint8List> _files = <String, Uint8List>{};

  String _norm(String path) => p.posix.normalize(path);

  String _parent(String path) => p.posix.dirname(_norm(path));

  bool isDirectory(String path) => _dirs.contains(_norm(path));

  bool isFile(String path) => _files.containsKey(_norm(path));

  bool exists(String path) => isDirectory(path) || isFile(path);

  /// Creates the directory [path]. Fails (returns `false`) when it already
  /// exists, when a file with that name exists, or when the parent is missing.
  bool createDirectory(String path) {
    final String norm = _norm(path);
    if (norm == '/' || exists(norm)) return false;
    if (!isDirectory(_parent(norm))) return false;
    _dirs.add(norm);
    return true;
  }

  /// Removes the *empty* directory [path]. Fails on the root, on non-existent
  /// or non-directory paths, or on a directory that still has children.
  bool removeEmptyDirectory(String path) {
    final String norm = _norm(path);
    if (norm == '/' || !isDirectory(norm)) return false;
    if (list(norm).isNotEmpty) return false;
    _dirs.remove(norm);
    return true;
  }

  /// Removes the file [path].
  bool removeFile(String path) {
    final String norm = _norm(path);
    if (!isFile(norm)) return false;
    _files.remove(norm);
    return true;
  }

  /// Returns the size of the file [path], or `null` when it is not a file.
  int? fileSize(String path) {
    final Uint8List? bytes = _files[_norm(path)];
    return bytes?.length;
  }

  /// Returns the content of the file [path], or `null` when it is not a file.
  List<int>? readFile(String path) {
    final Uint8List? bytes = _files[_norm(path)];
    return bytes == null ? null : List<int>.from(bytes);
  }

  /// Writes [bytes] to [path], creating or overwriting the file. Fails when the
  /// parent directory is missing or the path is an existing directory.
  bool writeFile(String path, List<int> bytes) {
    final String norm = _norm(path);
    if (isDirectory(norm)) return false;
    if (!isDirectory(_parent(norm))) return false;
    _files[norm] = Uint8List.fromList(bytes);
    return true;
  }

  /// Renames/moves [from] to [to] (file or whole directory subtree). Fails when
  /// [from] does not exist or [to]'s parent directory is missing.
  bool rename(String from, String to) {
    final String src = _norm(from);
    final String dst = _norm(to);
    if (!exists(src) || src == '/') return false;
    if (!isDirectory(_parent(dst))) return false;
    if (exists(dst)) return false;

    if (isFile(src)) {
      _files[dst] = _files.remove(src)!;
      return true;
    }

    // Directory: move the node and every descendant, rewriting the prefix.
    final String prefix = '$src/';
    for (final String dir in _dirs.toList()) {
      if (dir == src) {
        _dirs.remove(dir);
        _dirs.add(dst);
      } else if (dir.startsWith(prefix)) {
        _dirs.remove(dir);
        _dirs.add('$dst/${dir.substring(prefix.length)}');
      }
    }
    for (final String file in _files.keys.toList()) {
      if (file.startsWith(prefix)) {
        final Uint8List bytes = _files.remove(file)!;
        _files['$dst/${file.substring(prefix.length)}'] = bytes;
      }
    }
    return true;
  }

  /// Lists the immediate children of the directory [path].
  List<VfsEntry> list(String path) {
    final String dir = _norm(path);
    if (!isDirectory(dir)) return const <VfsEntry>[];
    final List<VfsEntry> entries = <VfsEntry>[];
    for (final String d in _dirs) {
      if (d != '/' && _parent(d) == dir) {
        entries.add(VfsEntry(p.posix.basename(d), true, 0));
      }
    }
    for (final MapEntry<String, Uint8List> f in _files.entries) {
      if (_parent(f.key) == dir) {
        entries.add(VfsEntry(p.posix.basename(f.key), false, f.value.length));
      }
    }
    entries.sort((VfsEntry a, VfsEntry b) => a.name.compareTo(b.name));
    return entries;
  }

  /// Convenience helper to eagerly seed a directory tree.
  void mkdirs(String path) {
    final String norm = _norm(path);
    final List<String> parts =
        norm.split('/').where((String s) => s.isNotEmpty).toList();
    String current = '';
    for (final String part in parts) {
      current = '$current/$part';
      _dirs.add(current);
    }
  }

  /// Convenience helper to seed a file (creating parent directories).
  void seedFile(String path, List<int> bytes) {
    mkdirs(_parent(path));
    _files[_norm(path)] = Uint8List.fromList(bytes);
  }
}
