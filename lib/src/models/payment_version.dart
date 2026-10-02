/// The SDK's integration levels. `PaymentFlow` shows the chosen one.
enum PaymentVersion {
  /// The app chose QR: the SDK charges it.
  v1,

  /// The SDK shows the account's payment methods and charges the chosen one.
  v2,

  /// A pay button opens the SDK's own payment window.
  v3;

  /// 'V1', 'V2', 'V3'.
  String get label => name.toUpperCase();

  /// Reads a version from configuration: 'v1', 'V2', ' v3 '. Anything else,
  /// including 'off' or an empty value, is null (the SDK is not used).
  static PaymentVersion? tryParse(String? value) {
    final normalized = value?.trim().toLowerCase();
    for (final version in values) {
      if (version.name == normalized) return version;
    }
    return null;
  }
}
