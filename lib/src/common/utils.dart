class Utils {
  Utils._();

  /// Computes the transferred percentage (0 -> 100, rounded to 2 decimals).
  ///
  /// Returns 100 when [total] is unknown/zero or the computation is not finite,
  /// and never returns more than 100.
  static double percent(int transferred, int total) {
    if (total <= 0) return 100;
    final double value =
        double.tryParse(((transferred / total) * 100).toStringAsFixed(2)) ??
            100;
    if (value.isNaN || value.isInfinite) return 100;
    return value > 100 ? 100 : value;
  }

  static int parsePort(String response, bool isIPV6) {
    return isIPV6 ? parsePortEPSV(response) : parsePortPASV(response);
  }

  /// Parse the Passive Mode Port from the Servers [sResponse]
  /// port format (|||xxxxx|)
  static int parsePortEPSV(String sResponse) {
    int iParOpen = sResponse.indexOf('(');
    int iParClose = sResponse.indexOf(')');

    if (iParClose > -1 && iParOpen > -1) {
      sResponse = sResponse.substring(iParOpen + 4, iParClose - 1);
    }
    return int.parse(sResponse);
  }

  /// Parse the Passive Mode Port from the Servers [sResponse]
  /// format 227 Entering Passive Mode (192,168,8,36,8,75).
  static int parsePortPASV(String sResponse) {
    int iParOpen = sResponse.indexOf('(');
    int iParClose = sResponse.indexOf(')');

    String sParameters = sResponse.substring(iParOpen + 1, iParClose);
    List<String> lstParameters = sParameters.split(',');

    int iPort1 = int.parse(lstParameters[lstParameters.length - 2]);
    int iPort2 = int.parse(lstParameters[lstParameters.length - 1]);

    return (iPort1 * 256) + iPort2;
  }
}
