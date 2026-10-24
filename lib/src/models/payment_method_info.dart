/// A payment method enabled for the account, as returned by
/// `GET /payment-methods`. The backend decides which ones exist and which
/// provider processes each; the SDK only knows their codes.
class PaymentMethodInfo {
  const PaymentMethodInfo({
    required this.code,
    required this.name,
    this.description,
    this.iconUrl,
    this.currency,
    this.position = 0,
  });

  factory PaymentMethodInfo.fromJson(Map<String, dynamic> json) {
    final position = json['position'];
    return PaymentMethodInfo(
      code: json['code']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString(),
      iconUrl: json['icon']?.toString(),
      currency: json['currency']?.toString(),
      position: position is num ? position.toInt() : 0,
    );
  }

  static const qrCode = 'QR';
  static const cashCode = 'EFECTIVO';

  /// Stable code from the backend: 'QR', 'EFECTIVO', 'CARD'…
  final String code;
  final String name;
  final String? description;
  final String? iconUrl;

  /// Currency of the account that processes this method.
  final String? currency;
  final int position;

  bool get isQr => code.toUpperCase() == qrCode;

  /// Paid at a cashier with a code. The widgets only offer it when the app
  /// handles it (`onCashPayment`, or `acceptCash` in the payment sheet).
  bool get isCash => code.toUpperCase() == cashCode;

  /// Whether this SDK version can process the method. Others are hidden, so
  /// a new backend method never breaks an app on an older SDK.
  bool get isSupported => isQr || isCash;

  Map<String, dynamic> toJson() => {
        'code': code,
        'name': name,
        'description': description,
        'icon': iconUrl,
        'currency': currency,
        'position': position,
      };

  @override
  String toString() => 'PaymentMethodInfo($code, $name)';
}
