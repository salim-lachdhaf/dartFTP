class FTPConnectException implements Exception {
  final String message;
  final String? response;

  FTPConnectException(this.message, [this.response]);

  @override
  String toString() {
    return 'FTPConnectException: $message (Response: $response)';
  }
}

class FTPParsingErrorException implements Exception {
  final String message;
  final String? response;

  FTPParsingErrorException(this.message, [this.response]);

  @override
  String toString() {
    return 'FTPParsingErrorException: $message (Response: $response)';
  }
}

class FTPConnectionTimeoutException implements Exception {
  final String message;
  final String? response;

  FTPConnectionTimeoutException(this.message, [this.response]);

  @override
  String toString() {
    return 'FTPConnectionTimeoutException: $message (Response: $response)';
  }
}

class FTPIllegalReplyException implements Exception {
  final String message;
  final String? response;

  FTPIllegalReplyException(this.message, [this.response]);

  @override
  String toString() {
    return 'FTPIllegalReplyException: $message (Response: $response)';
  }
}

class FTPESConnectException implements Exception {
  final String message;
  final String? response;

  FTPESConnectException(this.message, [this.response]);

  @override
  String toString() {
    return 'FTPESConnectException: $message (Response: $response)';
  }
}

class FTPAccountRequiredException implements Exception {
  final String message;
  final String? response;

  FTPAccountRequiredException(this.message, [this.response]);

  @override
  String toString() {
    return 'FTPAccountRequiredException: $message (Response: $response)';
  }
}

class FTPWrongCredentialsException implements Exception {
  final String message;
  final String? response;

  FTPWrongCredentialsException(this.message, [this.response]);

  @override
  String toString() {
    return 'FTPWrongCredentialsException: $message (Response: $response)';
  }
}

class FTPUnablePassiveModeException implements Exception {
  final String message;
  final String? response;

  FTPUnablePassiveModeException(this.message, [this.response]);

  @override
  String toString() {
    return 'FTPUnablePassiveModeException: $message (Response: $response)';
  }
}

class FTPCannotChangeDirectoryException implements Exception {
  final String message;
  final String? response;

  FTPCannotChangeDirectoryException(this.message, [this.response]);

  @override
  String toString() {
    return 'FTPCannotChangeDirectoryException: $message (Response: $response)';
  }
}

class FTPCannotDeleteFolderException implements Exception {
  final String message;
  final String? response;

  FTPCannotDeleteFolderException(this.message, [this.response]);

  @override
  String toString() {
    return 'FTPCannotDeleteFolderException: $message (Response: $response)';
  }
}

class FTPCannotDeleteFileException implements Exception {
  final String message;
  final String? response;

  FTPCannotDeleteFileException(this.message, [this.response]);

  @override
  String toString() {
    return 'FTPCannotDeleteFileException: $message (Response: $response)';
  }
}

class FTPCannotDownloadException implements Exception {
  final String message;
  final String? response;

  FTPCannotDownloadException(this.message, [this.response]);

  @override
  String toString() {
    return 'FTPCannotDownloadException: $message (Response: $response)';
  }
}

class FTPFileNotExistsException implements Exception {
  final String message;
  final String? response;

  FTPFileNotExistsException(this.message, [this.response]);

  @override
  String toString() {
    return 'FTPFileNotExistsException: $message (Response: $response)';
  }
}

class FTPConnectionRefusedException implements Exception {
  final String message;
  final String? response;

  FTPConnectionRefusedException(this.message, [this.response]);

  @override
  String toString() {
    return 'FTPConnectionRefusedException: $message (Response: $response)';
  }
}

class FTPTransferException implements Exception {
  final String message;
  final String? response;

  FTPTransferException(this.message, [this.response]);

  @override
  String toString() {
    return 'FTPTransferException: $message (Response: $response)';
  }
}

class FTPUnableToGetCWDException implements Exception {
  final String message;
  final String? response;

  FTPUnableToGetCWDException(this.message, [this.response]);

  @override
  String toString() {
    return 'FTPUnableToGetCWDException: $message (Response: $response)';
  }
}
