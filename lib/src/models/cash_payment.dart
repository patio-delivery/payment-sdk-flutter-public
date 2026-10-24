import 'payment_status.dart';

/// A cash payment, as returned by `POST /cash`: the payer takes [code] to a
/// collector, who marks it paid or cancels it. It stays
/// [PaymentStatus.pending] until then — it never expires on its own.
class CashPayment {
  const CashPayment({
    required this.code,
    required this.orderId,
    required this.amount,
    required this.status,
    this.currency,
    this.description,
    this.createdAt,
  });

  factory CashPayment.fromJson(Map<String, dynamic> json) {
    final amount = json['amount'];
    final glosa = json['glosa']?.toString();
    return CashPayment(
      code: json['code']?.toString() ?? '',
      orderId: json['order']?.toString() ?? '',
      amount: amount is num ? amount : num.tryParse('$amount') ?? 0,
      status: PaymentStatus.fromJson(json['status']),
      currency: json['currency']?.toString(),
      description: glosa == null || glosa.isEmpty ? null : glosa,
      createdAt: DateTime.tryParse('${json['createdAt']}'),
    );
  }

  /// What the payer shows the collector, e.g. "EF-7K3M9QX2".
  final String code;

  /// Your reference for the payment.
  final String orderId;
  final num amount;
  final PaymentStatus status;

  /// Currency of the account that processes cash.
  final String? currency;
  final String? description;
  final DateTime? createdAt;

  bool get isPending => status == PaymentStatus.pending;

  Map<String, dynamic> toJson() => {
        'code': code,
        'order': orderId,
        'amount': amount,
        'status': status.value,
        'currency': currency,
        'glosa': description,
        'createdAt': createdAt?.toIso8601String(),
      };

  CashPayment copyWith({PaymentStatus? status}) => CashPayment(
        code: code,
        orderId: orderId,
        amount: amount,
        status: status ?? this.status,
        currency: currency,
        description: description,
        createdAt: createdAt,
      );

  @override
  String toString() =>
      'CashPayment(code: $code, orderId: $orderId, status: ${status.value})';
}
