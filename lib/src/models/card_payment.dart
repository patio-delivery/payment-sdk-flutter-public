import '../card/card_terminal.dart';
import 'payment_status.dart';

/// A card payment charged on a POS, as Nexus Payments records it
/// (`POST /card`, `POST /card/:id/result`).
///
/// [status] is [PaymentStatus.paid] when the POS approved it and
/// [PaymentStatus.failed] when it rejected it. It stays
/// [PaymentStatus.pending] until the result is reported.
class CardPayment {
  const CardPayment({
    required this.id,
    required this.orderId,
    required this.amount,
    required this.status,
    this.currency,
    this.description,
    this.terminalId,
    this.terminalName,
    this.authCode,
    this.receiptNumber,
    this.last4,
    this.bin,
    this.cardNetwork,
    this.entryLabel,
    this.responseCode,
    this.message,
    this.createdAt,
    this.resolvedAt,
    this.recorded = true,
  });

  factory CardPayment.fromJson(Map<String, dynamic> json) {
    final amount = json['amount'];
    final id = json['id'];
    final glosa = json['glosa']?.toString();
    final terminal = json['terminal'];
    final card = json['card'];
    String? fromCard(String key) => card is Map ? card[key]?.toString() : null;
    return CardPayment(
      id: id is num ? id.toInt() : int.tryParse('$id') ?? 0,
      orderId: json['order']?.toString() ?? '',
      amount: amount is num ? amount : num.tryParse('$amount') ?? 0,
      status: PaymentStatus.fromJson(json['status']),
      currency: json['currency']?.toString(),
      description: glosa == null || glosa.isEmpty ? null : glosa,
      terminalId: terminal is Map ? terminal['code']?.toString() : null,
      terminalName: terminal is Map ? terminal['name']?.toString() : null,
      authCode: fromCard('authCode'),
      receiptNumber: fromCard('receiptNumber'),
      last4: fromCard('last4'),
      bin: fromCard('bin'),
      cardNetwork: fromCard('cardNetwork'),
      entryLabel: fromCard('entryLabel'),
      responseCode: fromCard('responseCode'),
      message: fromCard('message'),
      createdAt: DateTime.tryParse('${json['createdAt']}'),
      resolvedAt: DateTime.tryParse('${json['resolvedAt']}'),
    );
  }

  /// Nexus Payments' id for the payment.
  final int id;

  /// Your reference for the payment.
  final String orderId;
  final num amount;
  final PaymentStatus status;
  final String? currency;
  final String? description;

  /// The terminal (device) it was charged on, when it is registered.
  final String? terminalId;
  final String? terminalName;

  /// What the POS answered; null until it did.
  final String? authCode;
  final String? receiptNumber;
  final String? last4;

  /// First digits of the card (BIN), as the POS shows them.
  final String? bin;
  final String? cardNetwork;
  final String? entryLabel;
  final String? responseCode;
  final String? message;

  final DateTime? createdAt;
  final DateTime? resolvedAt;

  /// False when the POS answered but Nexus Payments could not record it (it
  /// stays pending there): [status] then comes from the POS. Worth logging,
  /// so someone reconciles it with the POS's receipt.
  final bool recorded;

  bool get isApproved => status == PaymentStatus.paid;
  bool get isRejected => status == PaymentStatus.failed;

  /// "VISA •••• 1234", for the receipt and the screen.
  String? get maskedCard {
    if (last4 == null) return cardNetwork;
    return [cardNetwork, '•••• $last4'].whereType<String>().join(' ');
  }

  /// This payment with what the POS answered, for when the backend could not
  /// record it.
  CardPayment withCharge(CardChargeResult result, {required bool recorded}) =>
      CardPayment(
        id: id,
        orderId: orderId,
        amount: amount,
        status: result.approved ? PaymentStatus.paid : PaymentStatus.failed,
        currency: currency,
        description: description,
        terminalId: terminalId,
        terminalName: terminalName,
        authCode: result.authCode,
        receiptNumber: result.receiptNumber,
        last4: result.last4,
        bin: result.bin,
        cardNetwork: result.cardNetwork,
        entryLabel: result.entryLabel,
        responseCode: result.responseCode,
        message: result.message,
        createdAt: createdAt,
        resolvedAt: DateTime.now(),
        recorded: recorded,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'order': orderId,
        'amount': amount,
        'status': status.value,
        'currency': currency,
        'glosa': description,
        'terminal': terminalId,
        'authCode': authCode,
        'receiptNumber': receiptNumber,
        'last4': last4,
        'bin': bin,
        'cardNetwork': cardNetwork,
        'entryLabel': entryLabel,
        'responseCode': responseCode,
        'message': message,
        'createdAt': createdAt?.toIso8601String(),
        'resolvedAt': resolvedAt?.toIso8601String(),
        'recorded': recorded,
      };

  @override
  String toString() =>
      'CardPayment(id: $id, orderId: $orderId, status: ${status.value})';
}
