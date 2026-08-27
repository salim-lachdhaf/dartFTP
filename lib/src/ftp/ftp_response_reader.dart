import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../domain/entities/ftp_reply.dart';
import '../domain/exceptions.dart';
import '../domain/logger.dart';
import 'socket_connector.dart';

/// Reads FTP replies from the control connection's inbound byte stream.
///
/// It buffers incoming bytes and exposes [readReply], which completes as soon as
/// a full reply (single or multi-line, per RFC 959) is available. Bytes that
/// belong to a following reply are kept buffered for the next call.
class FtpResponseReader {
  final Logger _logger;
  final Duration _timeout;
  late final StreamSubscription<Uint8List> _subscription;

  final List<int> _bytes = <int>[];
  Completer<FTPReply>? _pending;
  Object? _error;
  bool _closed = false;

  FtpResponseReader(
      RawSocketConnection connection, this._logger, this._timeout) {
    _subscription = connection.inbound.listen(
      _onData,
      onError: _onError,
      onDone: _onDone,
      cancelOnError: false,
    );
  }

  void _onData(Uint8List data) {
    _bytes.addAll(data);
    _tryComplete();
  }

  void _onError(Object error) {
    _error = error;
    final Completer<FTPReply>? pending = _pending;
    if (pending != null && !pending.isCompleted) {
      _pending = null;
      pending.completeError(
          FTPConnectException('Control connection error', null, error));
    }
  }

  void _onDone() {
    _closed = true;
    _tryComplete();
    final Completer<FTPReply>? pending = _pending;
    if (pending != null && !pending.isCompleted) {
      _pending = null;
      pending.completeError(const FTPConnectException(
          'Control connection closed while waiting for a reply'));
    }
  }

  void _tryComplete() {
    final Completer<FTPReply>? pending = _pending;
    if (pending == null || pending.isCompleted) return;
    final FTPReply? reply = _extractReply();
    if (reply != null) {
      _pending = null;
      pending.complete(reply);
    }
  }

  /// Extracts the next complete reply from the buffer, or `null` when the buffer
  /// does not yet hold a full reply.
  FTPReply? _extractReply() {
    final String text = utf8.decode(_bytes, allowMalformed: true);
    int cursor = 0;
    int newlineIndex;
    // The code of a multi-line reply's opening "NNN-..." line, once seen.
    // Per RFC 959, only a later line with the exact same code followed by a
    // space (not another server line that merely happens to start with
    // three digits and a space) terminates that reply.
    String? openCode;
    while ((newlineIndex = text.indexOf('\n', cursor)) != -1) {
      String line = text.substring(cursor, newlineIndex);
      if (line.endsWith('\r')) line = line.substring(0, line.length - 1);
      cursor = newlineIndex + 1;

      if (openCode == null) {
        if (_isTerminatorLine(line)) {
          return _completeReply(text, cursor, line.substring(0, 3));
        }
        if (_isMultilineStart(line)) {
          openCode = line.substring(0, 3);
        }
        continue;
      }

      if (_isTerminatorLine(line) && line.startsWith(openCode)) {
        return _completeReply(text, cursor, openCode);
      }
    }
    return null;
  }

  FTPReply _completeReply(String text, int cursor, String codeText) {
    final String replyText = text.substring(0, cursor);
    final int consumed = utf8.encode(replyText).length;
    _bytes.removeRange(0, consumed);
    final int code = int.parse(codeText);
    final FTPReply reply = FTPReply(code, replyText.trim());
    _logger.log('< $reply');
    return reply;
  }

  static bool _isTerminatorLine(String line) {
    if (line.length < 4) return false;
    if (line[3] != ' ') return false;
    return _hasDigitCode(line);
  }

  static bool _isMultilineStart(String line) {
    if (line.length < 4) return false;
    if (line[3] != '-') return false;
    return _hasDigitCode(line);
  }

  static bool _hasDigitCode(String line) {
    for (int i = 0; i < 3; i++) {
      final int c = line.codeUnitAt(i);
      if (c < 0x30 || c > 0x39) return false;
    }
    return true;
  }

  /// Completes with the next full FTP reply, or throws a [FTPConnectException]
  /// on timeout / connection error.
  Future<FTPReply> readReply() {
    if (_error != null) {
      return Future.error(
          FTPConnectException('Control connection error', null, _error));
    }
    final FTPReply? buffered = _extractReply();
    if (buffered != null) return Future.value(buffered);
    if (_closed) {
      return Future.error(const FTPConnectException(
          'Control connection closed while waiting for a reply'));
    }

    final Completer<FTPReply> completer = Completer<FTPReply>();
    _pending = completer;
    return completer.future.timeout(_timeout, onTimeout: () {
      _pending = null;
      throw const FTPConnectException(
          'Timeout reached for Receiving response !');
    });
  }

  /// Releases the underlying stream subscription.
  Future<void> dispose() => _subscription.cancel();
}
