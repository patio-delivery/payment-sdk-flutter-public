import 'package:dio/dio.dart' show HttpClientAdapter;

import 'bancard_terminals.dart';

/// How the SDK reaches a terminal's POS.
enum CardConnection {
  /// Through the local service (totem_bancard_pos) running on the device,
  /// which forwards the sale to the POS.
  bridge('BRIDGE'),

  /// Straight to the POS in the device's network, without the local service.
  direct('DIRECT');

  const CardConnection(this.value);

  /// Backend value.
  final String value;

  /// Anything but `DIRECT` is [bridge], the connection that already works
  /// with real POS.
  static CardConnection fromJson(Object? json) =>
      json is String && json.trim().toUpperCase() == direct.value
          ? direct
          : bridge;
}

/// Where a device's POS is and how to reach it. Read from Nexus Payments
/// (`GET /card/terminals/:code`), or built by hand with
/// `CardOptions.manual`.
class CardTerminalConfig {
  const CardTerminalConfig({
    required this.posIp,
    required this.posPort,
    this.connection = CardConnection.bridge,
    this.bridgeUrl,
    this.code,
    this.name,
  });

  factory CardTerminalConfig.fromJson(Map<String, dynamic> json) {
    final port = json['posPort'];
    final bridgeUrl = json['bridgeUrl']?.toString().trim();
    return CardTerminalConfig(
      code: json['code']?.toString(),
      name: json['name']?.toString(),
      connection: CardConnection.fromJson(json['connection']),
      posIp: json['posIp']?.toString().trim() ?? '',
      posPort: port is num ? port.toInt() : int.tryParse('$port') ?? 0,
      bridgeUrl: bridgeUrl == null || bridgeUrl.isEmpty ? null : bridgeUrl,
    );
  }

  /// Where the local service listens when [bridgeUrl] is not set.
  static const defaultBridgeUrl = 'http://127.0.0.1:8000';

  /// The terminal's code in Nexus Payments (the totem's IMEI,
  /// "PARKING-CAJA-1"…), when it was read from there.
  final String? code;
  final String? name;
  final CardConnection connection;

  /// IP of the POS in the device's network.
  final String posIp;
  final int posPort;

  /// Only for [CardConnection.bridge]; null means [defaultBridgeUrl].
  final String? bridgeUrl;

  String get effectiveBridgeUrl => bridgeUrl ?? defaultBridgeUrl;

  Map<String, dynamic> toJson() => {
        'code': code,
        'name': name,
        'connection': connection.value,
        'posIp': posIp,
        'posPort': posPort,
        'bridgeUrl': bridgeUrl,
      };

  @override
  String toString() =>
      'CardTerminalConfig(${code ?? '-'}, ${connection.value}, $posIp:$posPort)';
}

/// What the POS answered to a sale.
class CardChargeResult {
  const CardChargeResult({
    required this.approved,
    this.responseCode,
    this.authCode,
    this.receiptNumber,
    this.posTerminalId,
    this.posMerchantId,
    this.last4,
    this.bin,
    this.cardNetwork,
    this.entryLabel,
    this.message,
    this.raw = const {},
  });

  /// Whether the POS approved the sale (response code `00`).
  final bool approved;
  final String? responseCode;
  final String? authCode;
  final String? receiptNumber;

  /// The POS's own terminal and merchant ids, as it prints them.
  final String? posTerminalId;
  final String? posMerchantId;

  /// Never the full card number: only what the POS shows masked.
  final String? last4;
  final String? bin;

  /// VISA, MASTERCARD, AMEX…
  final String? cardNetwork;

  /// What the customer paid with on the POS: "Tarjeta", "QR Simple"…
  final String? entryLabel;

  /// The POS's message ("APROBADA", the rejection reason…).
  final String? message;

  /// The POS's full answer, for audit. The card number in it is masked.
  final Map<String, dynamic> raw;

  /// The body of `POST /card/:id/result`.
  Map<String, dynamic> toJson() => {
        'approved': approved,
        if (responseCode != null) 'responseCode': responseCode,
        if (authCode != null) 'authCode': authCode,
        if (receiptNumber != null) 'receiptNumber': receiptNumber,
        if (posTerminalId != null) 'posTerminalId': posTerminalId,
        if (posMerchantId != null) 'posMerchantId': posMerchantId,
        if (last4 != null) 'last4': last4,
        if (bin != null) 'bin': bin,
        if (cardNetwork != null) 'cardNetwork': cardNetwork,
        if (entryLabel != null) 'entryLabel': entryLabel,
        if (message != null) 'message': message,
        if (raw.isNotEmpty) 'raw': raw,
      };

  @override
  String toString() =>
      'CardChargeResult(approved: $approved, code: $responseCode, auth: $authCode)';
}

/// A POS the SDK can charge cards on. The SDK ships Bancard's
/// ([BancardBridgeTerminal], [BancardDirectTerminal]); another POS is one
/// more implementation, passed with `CardOptions.custom`.
abstract class CardTerminal {
  const CardTerminal();

  /// The Bancard terminal for [config]'s connection.
  factory CardTerminal.fromConfig(
    CardTerminalConfig config, {
    HttpClientAdapter? httpClientAdapter,
    bool enableLogging = false,
  }) =>
      switch (config.connection) {
        CardConnection.bridge => BancardBridgeTerminal(
            posIp: config.posIp,
            posPort: config.posPort,
            bridgeUrl: config.effectiveBridgeUrl,
            httpClientAdapter: httpClientAdapter,
            enableLogging: enableLogging,
          ),
        CardConnection.direct => BancardDirectTerminal(
            posIp: config.posIp,
            posPort: config.posPort,
            httpClientAdapter: httpClientAdapter,
            enableLogging: enableLogging,
          ),
      };

  /// Whether the POS (or the service in front of it) answers. Card is only
  /// offered when it does.
  Future<bool> isReachable();

  /// Charges [amount] on the POS. Completes when the customer finishes there
  /// (approved or rejected), which can take minutes.
  ///
  /// Throws [CardTerminalException] when it can't tell: check its
  /// `outcomeUnknown` before charging again.
  Future<CardChargeResult> charge({
    required num amount,
    required String orderId,
    String? currency,
  });

  /// Releases the connections. The terminal cannot be used afterwards.
  void close() {}
}
