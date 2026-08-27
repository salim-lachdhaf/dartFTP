import '../domain/exceptions.dart';

/// Small stateless helpers used across the package.
class Utils {
  Utils._();

  /// Computes the transferred percentage (0 -> 100, rounded to 2 decimals).
  ///
  /// Returns 100 when [total] is unknown/zero or the computation is not finite,
  /// and never returns more than 100.
  static double percent(int transferred, int total) {
    if (total <= 0) return 100;
    final double value = ((transferred / total) * 100 * 100).round() / 100;
    if (value.isNaN || value.isInfinite) return 100;
    return value > 100 ? 100 : value;
  }

  /// Parse the passive-mode data port from the server [response].
  ///
  /// Delegates to [parsePortEPSV] for IPv6/EPSV replies and to [parsePortPASV]
  /// otherwise.
  ///
  /// Throws [FTPConnectException] when [response] does not carry a
  /// well-formed port.
  static int parsePort(String response, bool isIPV6) {
    return isIPV6 ? parsePortEPSV(response) : parsePortPASV(response);
  }

  /// Parse the passive-mode port from an EPSV reply, format `(|||xxxxx|)`.
  ///
  /// Throws [FTPConnectException] when [sResponse] is not a well-formed EPSV
  /// reply.
  static int parsePortEPSV(String sResponse) {
    final int iParOpen = sResponse.indexOf('(');
    final int iParClose = sResponse.indexOf(')');
    if (iParOpen == -1 || iParClose == -1 || iParClose - iParOpen < 5) {
      throw FTPConnectException(
          'Cannot parse the EPSV port from the server reply', sResponse);
    }
    final String sPort = sResponse.substring(iParOpen + 4, iParClose - 1);
    final int? port = int.tryParse(sPort);
    if (port == null) {
      throw FTPConnectException(
          'Cannot parse the EPSV port from the server reply', sResponse);
    }
    return port;
  }

  /// Parse the passive-mode port from a PASV reply, format
  /// `227 Entering Passive Mode (192,168,8,36,8,75)`.
  ///
  /// Throws [FTPConnectException] when [sResponse] is not a well-formed PASV
  /// reply.
  static int parsePortPASV(String sResponse) {
    final int iParOpen = sResponse.indexOf('(');
    final int iParClose = sResponse.indexOf(')');
    if (iParOpen == -1 || iParClose == -1 || iParClose <= iParOpen) {
      throw FTPConnectException(
          'Cannot parse the PASV port from the server reply', sResponse);
    }

    final String sParameters = sResponse.substring(iParOpen + 1, iParClose);
    final List<String> lstParameters = sParameters.split(',');
    if (lstParameters.length < 2) {
      throw FTPConnectException(
          'Cannot parse the PASV port from the server reply', sResponse);
    }

    final int? iPort1 = int.tryParse(lstParameters[lstParameters.length - 2]);
    final int? iPort2 = int.tryParse(lstParameters[lstParameters.length - 1]);
    if (iPort1 == null || iPort2 == null) {
      throw FTPConnectException(
          'Cannot parse the PASV port from the server reply', sResponse);
    }

    return (iPort1 * 256) + iPort2;
  }

  /// Parse the passive-mode host from a PASV reply. Returns `null` for EPSV
  /// replies (which do not advertise a host) or when the reply is
  /// malformed.
  static String? parseHostPASV(String sResponse) {
    final int iParOpen = sResponse.indexOf('(');
    final int iParClose = sResponse.indexOf(')');
    if (iParOpen == -1 || iParClose == -1) return null;

    final List<String> parts =
        sResponse.substring(iParOpen + 1, iParClose).split(',');
    if (parts.length < 6) return null;
    return '${parts[0]}.${parts[1]}.${parts[2]}.${parts[3]}';
  }
}
