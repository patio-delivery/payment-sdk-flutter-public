import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../exceptions/payment_sdk_exception.dart';
import 'card_terminal.dart';

/// Charges through the local service (totem_bancard_pos) running on the
/// device: `GET {bridgeUrl}/pago/{deviceId}/ctl/{amount}`. The service
/// forwards the sale to the POS at [posIp]:[posPort] (sent with every sale,
/// so it comes from Nexus Payments and not from the service's own settings).
class BancardBridgeTerminal extends CardTerminal {
  BancardBridgeTerminal({
    required this.posIp,
    required this.posPort,
    String bridgeUrl = CardTerminalConfig.defaultBridgeUrl,
    this.deviceId = 'device001',
    this.chargeTimeout = const Duration(seconds: 260),
    HttpClientAdapter? httpClientAdapter,
    bool enableLogging = false,
  })  : bridgeUrl = _trimSlash(bridgeUrl),
        _dio = _terminalDio(httpClientAdapter, enableLogging);

  final String posIp;
  final int posPort;
  final String bridgeUrl;

  /// The service's fixed route segment (`/pago/device001`).
  final String deviceId;

  /// How long to wait for the customer to finish on the POS. The service
  /// waits 250 s for the POS itself.
  final Duration chargeTimeout;
  final Dio _dio;

  @override
  Future<bool> isReachable() async {
    try {
      // With the POS's address the service also checks the POS itself
      // (503 when it doesn't accept connections). Older versions ignore it.
      final response = await _dio.get<Object?>(
        '$bridgeUrl/pago/$deviceId/health',
        queryParameters: {'posIp': posIp, 'posPort': '$posPort'},
        options: _quick.copyWith(receiveTimeout: const Duration(seconds: 6)),
      );
      return (response.statusCode ?? 0) < 400;
    } on DioException {
      return false;
    }
  }

  @override
  Future<CardChargeResult> charge({
    required num amount,
    required String orderId,
    String? currency,
  }) async {
    final Response<Object?> response;
    try {
      response = await _dio.get<Object?>(
        // The service takes the amount in the currency's units and turns it
        // into cents itself.
        '$bridgeUrl/pago/$deviceId/ctl/${amount.toStringAsFixed(2)}',
        queryParameters: {'posIp': posIp, 'posPort': '$posPort'},
        options: Options(
          receiveTimeout: chargeTimeout,
          // Read as text and decode here: the answer may not say it is JSON.
          responseType: ResponseType.plain,
          // The service answers 502 when it could not reach the POS.
          validateStatus: (status) => status != null && status < 300,
        ),
      );
    } on DioException catch (e) {
      throw _terminalError(e, target: 'el servicio del POS');
    }

    final body = _decodeJson(response.data);
    final list = body?['message'] ?? body?['data'];
    if (list is! List) {
      // Something answered, so the sale may have reached the POS.
      throw _unexpected('el servicio del POS', response);
    }
    return BancardResponse.fromNameValues(list);
  }

  @override
  void close() => _dio.close(force: true);

  @override
  String toString() => 'BancardBridgeTerminal($bridgeUrl → $posIp:$posPort)';
}

/// Charges on the POS directly, without the local service:
/// `GET http://{posIp}:{posPort}/sale?monto={cents}&cod_moneda={code}`, the
/// same call the service makes.
class BancardDirectTerminal extends CardTerminal {
  BancardDirectTerminal({
    required this.posIp,
    required this.posPort,
    this.currencyCode,
    this.chargeTimeout = const Duration(seconds: 250),
    HttpClientAdapter? httpClientAdapter,
    bool enableLogging = false,
  }) : _dio = _terminalDio(httpClientAdapter, enableLogging);

  final String posIp;
  final int posPort;

  /// ISO 4217 numeric code the POS expects (`068` = BOB). By default it
  /// follows the account's currency.
  final String? currencyCode;
  final Duration chargeTimeout;
  final Dio _dio;

  static const _numericCurrency = {'BOB': '068', 'PYG': '600', 'USD': '840'};

  String get _base => 'http://$posIp:$posPort';

  @override
  Future<bool> isReachable() async {
    try {
      // Any HTTP answer means the POS is there; only a failed connection
      // means it isn't.
      await _dio.get<Object?>(
        '$_base/',
        options: _quick.copyWith(validateStatus: (_) => true),
      );
      return true;
    } on DioException {
      return false;
    }
  }

  @override
  Future<CardChargeResult> charge({
    required num amount,
    required String orderId,
    String? currency,
  }) async {
    final code = currencyCode ??
        _numericCurrency[currency?.trim().toUpperCase()] ??
        _numericCurrency['BOB']!;
    final Response<Object?> response;
    try {
      response = await _dio.get<Object?>(
        '$_base/sale',
        queryParameters: {
          'monto': '${(amount * 100).round()}',
          'cod_moneda': code,
        },
        options: Options(
          receiveTimeout: chargeTimeout,
          // The POS answers JSON without saying so (no application/json
          // Content-Type): read it as text and decode it here.
          responseType: ResponseType.plain,
        ),
      );
    } on DioException catch (e) {
      throw _terminalError(e, target: 'el POS');
    }

    final body = _decodeJson(response.data);
    if (body == null) throw _unexpected('el POS', response);
    return BancardResponse.fromSale(body);
  }

  @override
  void close() => _dio.close(force: true);

  @override
  String toString() => 'BancardDirectTerminal($posIp:$posPort)';
}

/// Reads Bancard's answers into a [CardChargeResult].
abstract final class BancardResponse {
  /// The POS's own `/sale` answer: `{respuestaTransacción, autorizacion,
  /// referencia, pan, merchID, terminalID, mensaje, estado…}`.
  static CardChargeResult fromSale(Map<String, dynamic> sale) {
    String? read(List<String> keys) {
      for (final key in keys) {
        final value = sale[key]?.toString().trim();
        if (value != null && value.isNotEmpty) return value;
      }
      return null;
    }

    final code = read(['respuestaTransacción', 'respuestaTransaccion']);
    final pan = read(['pan']);
    return CardChargeResult(
      approved: code == '00',
      responseCode: code,
      authCode: read(['autorizacion', 'codigoAutorizacion']),
      receiptNumber: read(['referencia', 'nroBoleta']),
      posTerminalId: read(['terminalID']),
      posMerchantId: read(['merchID', 'codigoComercio']),
      last4: _last4(pan),
      bin: _bin(pan),
      cardNetwork: pan == null ? null : cardNetworkOf(pan),
      entryLabel: pan == null ? null : entryLabelOf(pan),
      message: read(['mensaje', 'mensajeDisplay', 'estado']),
      raw: {...sale, if (pan != null) 'pan': maskPan(pan)},
    );
  }

  /// The local service's answer: `{message: [{name, value}…]}`.
  static CardChargeResult fromNameValues(List<dynamic> list) {
    final map = <String, String>{
      for (final item in list)
        if (item is Map && item['name'] != null)
          '${item['name']}': '${item['value'] ?? ''}'.trim(),
    };
    String? read(String key) {
      final value = map[key];
      return value == null || value.isEmpty ? null : value;
    }

    final code = read('responseCode');
    final network = read('cardNetwork');
    return CardChargeResult(
      approved: code == '00',
      responseCode: code,
      authCode: read('authCode'),
      receiptNumber: read('receiptNumber'),
      posTerminalId: read('terminalID'),
      posMerchantId: read('merchantID'),
      last4: _fit(read('last4Digits'), 4),
      bin: _fit(read('cardBINTarjeta'), 8),
      cardNetwork: network == 'UNKNOWN' ? null : network,
      entryLabel: read('paymentMethod'),
      message: read('errorMessage') ?? read('status'),
      raw: map,
    );
  }

  /// The card network from the (masked) card number, as the local service
  /// computes it.
  static String? cardNetworkOf(String pan) {
    final digits = pan.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return null;
    bool starts(String pattern) => RegExp('^(?:$pattern)').hasMatch(digits);
    if (starts('4')) return 'VISA';
    if (starts('5[1-5]')) return 'MASTERCARD_LEGACY';
    if (starts('2[2-7]')) return 'MASTERCARD';
    if (starts('3[47]')) return 'AMEX';
    if (starts('3(?:0[0-5]|6|8)')) return 'DINERS_CLUB';
    if (starts('6(?:011|5|4[4-9])|622')) return 'DISCOVER';
    if (starts('50|56|57|58|6[7-9]')) return 'MAESTRO';
    if (starts('1')) return 'UATP';
    return null;
  }

  /// What the customer paid with on the POS, as the local service tells
  /// them apart: "QR Simple", "Tigo Money", "Tarjeta" or "Otro".
  static String entryLabelOf(String pan) {
    if (pan == '215141XXXXXX2548') return 'QR Simple';
    if (RegExp(r'^[67]\d{7}$').hasMatch(pan)) return 'Tigo Money';
    final first10 =
        pan.padRight(10, '0').substring(0, 10).replaceAll(RegExp(r'\D'), '0');
    final bin = int.parse(first10);
    const ranges = [
      [1100000000, 1199999999],
      [2221000000, 2720999999],
      [3000000000, 3999999990],
      [4000000000, 6999999999],
    ];
    return ranges.any((r) => bin >= r[0] && bin <= r[1]) ? 'Tarjeta' : 'Otro';
  }

  /// Keeps only the first 6 and last 4 digits.
  static String maskPan(String pan) {
    if (pan.length <= 10) return pan;
    return '${pan.substring(0, 6)}${'X' * (pan.length - 10)}'
        '${pan.substring(pan.length - 4)}';
  }

  static String? _last4(String? pan) {
    if (pan == null || pan.length < 4) return null;
    final last = pan.substring(pan.length - 4);
    return RegExp(r'^\d{4}$').hasMatch(last) ? last : null;
  }

  static String? _bin(String? pan) {
    if (pan == null || pan.length < 6) return null;
    final first = pan.substring(0, 6);
    return RegExp(r'^\d{6}$').hasMatch(first) ? first : null;
  }

  static String? _fit(String? value, int max) =>
      value == null || value.length <= max ? value : value.substring(0, max);
}

/// The answer as a JSON object, whatever its Content-Type said; null when it
/// isn't one.
Map<String, dynamic>? _decodeJson(Object? data) {
  Object? value = data;
  if (value is String) {
    final text = value.trim();
    if (text.isEmpty) return null;
    try {
      value = jsonDecode(text);
    } on FormatException {
      return null;
    }
  }
  return value is Map ? Map<String, dynamic>.from(value) : null;
}

/// Something answered that isn't a sale result, so the sale may have reached
/// the POS. The start of the answer goes in the message, for the logs.
CardTerminalException _unexpected(String target, Response<Object?> response) {
  final raw = '${response.data ?? ''}'.trim();
  final snippet = raw.length > 200 ? '${raw.substring(0, 200)}…' : raw;
  return CardTerminalException(
    'Respuesta inesperada de $target'
    '${snippet.isEmpty ? '' : ': $snippet'}',
    outcomeUnknown: true,
    statusCode: response.statusCode,
    details: response.data,
  );
}

/// A Dio for the POS or the local service: no API key, no backend base URL.
Dio _terminalDio(HttpClientAdapter? adapter, bool enableLogging) {
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 5),
    responseType: ResponseType.json,
  ));
  if (adapter != null) dio.httpClientAdapter = adapter;
  if (enableLogging) {
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        debugPrint('[PaymentSdk] POS --> ${options.method} ${options.uri}');
        handler.next(options);
      },
      onResponse: (response, handler) {
        debugPrint('[PaymentSdk] POS <-- ${response.statusCode} '
            '${response.requestOptions.uri}');
        handler.next(response);
      },
      onError: (error, handler) {
        debugPrint('[PaymentSdk] POS <-- ${error.type.name} '
            '${error.requestOptions.uri}');
        handler.next(error);
      },
    ));
  }
  return dio;
}

final _quick = Options(
  sendTimeout: const Duration(seconds: 3),
  receiveTimeout: const Duration(seconds: 3),
);

String _trimSlash(String url) {
  final value = url.trim();
  return value.endsWith('/') ? value.substring(0, value.length - 1) : value;
}

/// Whether a failed sale may have reached the POS decides if the customer
/// can be charged again: only a connection that never opened (or the
/// service saying it couldn't reach the POS) is safe.
CardTerminalException _terminalError(DioException e, {required String target}) {
  final status = e.response?.statusCode;
  return switch (e.type) {
    DioExceptionType.connectionError ||
    DioExceptionType.connectionTimeout =>
      CardTerminalException(
        'No se pudo conectar con $target',
        outcomeUnknown: false,
        cause: e,
      ),
    DioExceptionType.badResponse when status == 502 || status == 400 =>
      CardTerminalException(
        status == 502
            ? 'El servicio no pudo conectarse con el POS'
            : 'El servicio del POS rechazó el cobro',
        outcomeUnknown: false,
        statusCode: status,
        details: e.response?.data,
        cause: e,
      ),
    DioExceptionType.receiveTimeout => CardTerminalException(
        'El POS no respondió a tiempo',
        outcomeUnknown: true,
        cause: e,
      ),
    _ => CardTerminalException(
        'No se pudo confirmar el cobro en $target',
        outcomeUnknown: true,
        statusCode: status,
        details: e.response?.data,
        cause: e,
      ),
  };
}
