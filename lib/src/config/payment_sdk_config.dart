/// Connection settings for the Nexus Payments backend.
///
/// The merchant account, provider and currency are not configured here: the
/// backend derives them from the API key.
class PaymentSdkConfig {
  /// Throws [ArgumentError] if [baseUrl] is not an absolute http(s) URL or
  /// [apiKey] is empty.
  PaymentSdkConfig({
    required String baseUrl,
    required this.apiKey,
    this.timeout = const Duration(seconds: 30),
    this.defaultQrExpiration = const Duration(hours: 24),
    this.enableLogging = false,
  }) : baseUrl = _normalizeBaseUrl(baseUrl) {
    if (apiKey.trim().isEmpty) {
      throw ArgumentError('must not be empty', 'apiKey');
    }
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout', 'must be positive');
    }
    if (defaultQrExpiration <= Duration.zero) {
      throw ArgumentError.value(
        defaultQrExpiration,
        'defaultQrExpiration',
        'must be positive',
      );
    }
  }

  /// Backend URL including the `/api` prefix, without a trailing slash.
  final String baseUrl;

  /// Account API key, sent as `Authorization: Bearer <apiKey>`. Never logged.
  final String apiKey;

  final Duration timeout;

  /// QR lifetime used when `generateQr` gets no `dueDate`.
  final Duration defaultQrExpiration;

  /// Logs method, URL and status of each request with `debugPrint`.
  final bool enableLogging;

  static String _normalizeBaseUrl(String raw) {
    final value = raw.trim();
    final uri = Uri.tryParse(value);
    final valid = uri != null &&
        uri.hasAuthority &&
        (uri.scheme == 'http' || uri.scheme == 'https');
    if (!valid) {
      throw ArgumentError.value(
        raw,
        'baseUrl',
        'must be an absolute http(s) URL, e.g. http://localhost:8000/api',
      );
    }
    return value.endsWith('/') ? value.substring(0, value.length - 1) : value;
  }

  @override
  String toString() =>
      'PaymentSdkConfig(baseUrl: $baseUrl, apiKey: ***, timeout: $timeout)';
}
