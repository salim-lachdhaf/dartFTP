import 'dart:core';

class FTPReply {
  final int _code;
  final String _messages;

  FTPReply(this._code, this._messages);

  get code => this._code;

  get message => this._messages;

  bool isSuccessCode() {
    int aux = this._code - 200;
    return aux >= 0 && aux < 100;
  }

  @override
  String toString() {
    StringBuffer buffer = new StringBuffer();
    buffer.write("FTPReply =  [code= $_code, message= $_messages]");
    return buffer.toString();
  }
}
