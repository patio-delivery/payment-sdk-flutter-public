/// Payment status, mirroring the backend's `QrStatus`.
enum PaymentStatus {
  pending('PENDING'),
  paid('PAID'),
  failed('ERROR'),
  expired('EXPIRED'),

  /// A value this SDK version does not know.
  unknown('UNKNOWN');

  const PaymentStatus(this.value);

  /// Backend value.
  final String value;

  /// Case-insensitive; anything unrecognised is [unknown].
  static PaymentStatus fromJson(Object? json) {
    final normalized = json is String ? json.trim().toUpperCase() : null;
    return values.firstWhere(
      (status) => status != unknown && status.value == normalized,
      orElse: () => unknown,
    );
  }

  /// Whether the status can no longer change.
  bool get isFinal => this == paid || this == failed || this == expired;
}
