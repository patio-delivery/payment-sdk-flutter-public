import 'dart:convert';
import 'dart:typed_data';

import 'payment_status.dart';

/// A payment and its QR, as returned by `POST /qr` and
/// `GET /qr/by-id/:id_payment`.
class QrPayment {
  const QrPayment({
    required this.paymentId,
    required this.qrImageBase64,
    required this.status,
    this.dueDate,
  });

  factory QrPayment.fromJson(Map<String, dynamic> json) => QrPayment(
        paymentId: json['id_payment']?.toString() ?? '',
        qrImageBase64: json['imageQR']?.toString() ?? '',
        status: PaymentStatus.fromJson(json['status']),
        dueDate: json['dueDate']?.toString(),
      );

  /// Provider-assigned id (`id_payment`).
  final String paymentId;

  /// Base64 PNG. Empty when the backend no longer has the image.
  final String qrImageBase64;

  final PaymentStatus status;

  /// Expiration as sent by the backend; its format depends on the provider.
  final String? dueDate;

  /// Decoded PNG, or null when missing or invalid.
  Uint8List? get qrImageBytes {
    final raw = qrImageBase64.split(',').last.replaceAll(RegExp(r'\s'), '');
    if (raw.isEmpty) return null;
    try {
      return base64.decode(base64.normalize(raw));
    } on FormatException {
      return null;
    }
  }

  bool get hasQrImage => qrImageBytes != null;

  Map<String, dynamic> toJson() => {
        'id_payment': paymentId,
        'imageQR': qrImageBase64,
        'status': status.value,
        'dueDate': dueDate,
      };

  QrPayment copyWith({PaymentStatus? status}) => QrPayment(
        paymentId: paymentId,
        qrImageBase64: qrImageBase64,
        status: status ?? this.status,
        dueDate: dueDate,
      );

  @override
  String toString() =>
      'QrPayment(paymentId: $paymentId, status: ${status.value}, dueDate: $dueDate)';
}
