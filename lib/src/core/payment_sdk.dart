import 'dart:async';

import 'package:clock/clock.dart';
import 'package:dio/dio.dart' show HttpClientAdapter;
import 'package:flutter/foundation.dart' show debugPrint;

import '../card/card_options.dart';
import '../card/card_terminal.dart';
import '../config/payment_sdk_config.dart';
import '../exceptions/payment_sdk_exception.dart';
import '../models/card_payment.dart';
import '../models/cash_payment.dart';
import '../models/payment_method_info.dart';
import '../models/payment_status.dart';
import '../models/qr_payment.dart';
import 'api_client.dart';

/// Entry point of the SDK. Every method throws [PaymentSdkException] on
/// failure.
class PaymentSdk {
  /// [httpClientAdapter] replaces the HTTP transport (tests, proxies). It is
  /// also used for the card terminals this SDK builds.
  PaymentSdk({
    required PaymentSdkConfig config,
    HttpClientAdapter? httpClientAdapter,
  })  : _adapter = httpClientAdapter,
        _api = ApiClient(config, httpClientAdapter: httpClientAdapter);

  final ApiClient _api;
  final HttpClientAdapter? _adapter;

  /// Waits between attempts to record a card result the POS already gave.
  static const _reportRetryDelays = [
    Duration(milliseconds: 500),
    Duration(seconds: 1),
  ];

  PaymentSdkConfig get config => _api.config;

  /// Creates a payment and its QR (`POST /qr`).
  ///
  /// [orderId] must be unique per payment: status is looked up by it. The
  /// provider and currency come from the account behind the API key.
  Future<QrPayment> generateQr({
    required String orderId,
    required num amount,
    String description = '',
    DateTime? dueDate,
  }) async {
    final order = orderId.trim();
    final due = dueDate ?? clock.now().add(config.defaultQrExpiration);
    final errors = [
      if (order.isEmpty) 'orderId must not be empty',
      if (!amount.isFinite || amount <= 0) 'amount must be greater than 0',
      if (!due.isAfter(clock.now())) 'dueDate must be in the future',
    ];
    if (errors.isNotEmpty) {
      throw ValidationException(errors.join('; '), errors: errors);
    }

    final data = await _api.post('qr', {
      'order': order,
      'glosa': description,
      'amount': amount,
      'dueDate': due.toUtc().toIso8601String(),
    });
    return QrPayment.fromJson(data);
  }

  /// The stored payment and its QR (`GET /qr/by-id/:id_payment`). The status
  /// is not refreshed from the provider; use [getPaymentStatus] for that.
  Future<QrPayment> getPayment(String paymentId) async {
    final data =
        await _api.get('qr/by-id/${_pathSegment(paymentId, 'paymentId')}');
    return QrPayment.fromJson(data);
  }

  /// Payment methods enabled for the account behind the API key
  /// (`GET /payment-methods`), in the display order the backend sets.
  Future<List<PaymentMethodInfo>> getPaymentMethods() async {
    final data = await _api.getList('payment-methods');
    return [
      for (final item in data)
        if (item is Map<String, dynamic>) PaymentMethodInfo.fromJson(item),
    ];
  }

  /// Current status of the payment for [orderId] (`GET /qr/status/:order`).
  /// An unknown order is reported as [PaymentStatus.pending].
  Future<PaymentStatus> getPaymentStatus(String orderId) async {
    final data =
        await _api.get('qr/status/${_pathSegment(orderId, 'orderId')}');
    return PaymentStatus.fromJson(data['status']);
  }

  /// Creates a cash payment and its code (`POST /cash`). The payer takes the
  /// code to a collector; the payment stays pending until it is paid or
  /// cancelled there.
  ///
  /// Asking again for an [orderId] that is still pending returns the same
  /// code. The account must have cash enabled, otherwise this throws a
  /// [ValidationException].
  Future<CashPayment> createCashPayment({
    required String orderId,
    required num amount,
    String description = '',
  }) async {
    final order = orderId.trim();
    final errors = [
      if (order.isEmpty) 'orderId must not be empty',
      if (!amount.isFinite || amount <= 0) 'amount must be greater than 0',
    ];
    if (errors.isNotEmpty) {
      throw ValidationException(errors.join('; '), errors: errors);
    }

    final data = await _api.post('cash', {
      'order': order,
      'amount': amount,
      if (description.isNotEmpty) 'glosa': description,
    });
    return CashPayment.fromJson(data);
  }

  /// Current status of the cash payment for [orderId]
  /// (`GET /cash/status/:order`). Throws [PaymentNotFoundException] for an
  /// unknown order.
  Future<PaymentStatus> getCashPaymentStatus(String orderId) async {
    final data =
        await _api.get('cash/status/${_pathSegment(orderId, 'orderId')}');
    return PaymentStatus.fromJson(data['status']);
  }

  /// How to reach the POS registered under [terminalId] for the account's
  /// comercio (`GET /card/terminals/:code`). Throws
  /// [PaymentNotFoundException] for an unknown or inactive terminal.
  Future<CardTerminalConfig> getCardTerminal(String terminalId) async {
    final data = await _api
        .get('card/terminals/${_pathSegment(terminalId, 'terminalId')}');
    return CardTerminalConfig.fromJson(data);
  }

  /// The terminal [options] point to: the registered one (read now, so an
  /// edited IP applies right away), the one configured by hand, or yours.
  Future<CardTerminal> resolveCardTerminal(CardOptions options) async {
    if (options.terminal case final terminal?) return terminal;
    final config = options.config ?? await getCardTerminal(options.terminalId!);
    return CardTerminal.fromConfig(
      config,
      httpClientAdapter: _adapter,
      enableLogging: this.config.enableLogging,
    );
  }

  /// Registers a card payment before charging it on the POS (`POST /card`).
  ///
  /// An order already paid by card throws a [BackendException] (409), so it
  /// is never charged twice. The same order still pending with the same
  /// amount returns that payment. The account must have card enabled,
  /// otherwise this throws a [ValidationException].
  Future<CardPayment> createCardPayment({
    required String orderId,
    required num amount,
    String description = '',
    String? terminalId,
  }) async {
    final order = orderId.trim();
    final errors = [
      if (order.isEmpty) 'orderId must not be empty',
      if (!amount.isFinite || amount <= 0) 'amount must be greater than 0',
    ];
    if (errors.isNotEmpty) {
      throw ValidationException(errors.join('; '), errors: errors);
    }

    final terminal = terminalId?.trim();
    final data = await _api.post('card', {
      'order': order,
      'amount': amount,
      if (description.isNotEmpty) 'glosa': description,
      if (terminal != null && terminal.isNotEmpty) 'terminalId': terminal,
    });
    return CardPayment.fromJson(data);
  }

  /// Records what the POS answered (`POST /card/:id/result`): paid when it
  /// approved, failed when it rejected. Reporting the same result again
  /// returns the payment as it is.
  Future<CardPayment> reportCardResult(
    int paymentId,
    CardChargeResult result,
  ) async {
    final data = await _api.post('card/$paymentId/result', result.toJson());
    return CardPayment.fromJson(data);
  }

  /// Status of the latest card payment for [orderId]
  /// (`GET /card/status/:order`). Throws [PaymentNotFoundException] for an
  /// unknown order.
  Future<PaymentStatus> getCardPaymentStatus(String orderId) async {
    final data =
        await _api.get('card/status/${_pathSegment(orderId, 'orderId')}');
    return PaymentStatus.fromJson(data['status']);
  }

  /// A whole card payment, for apps with their own screens: registers it,
  /// charges it on [terminal] and records the result. Resolves with the
  /// payment approved or rejected.
  ///
  /// [onPosStarted] is called once the payment is registered and the POS is
  /// waiting for the card.
  ///
  /// Throws:
  /// - any [PaymentSdkException] from registering it: the POS was not
  ///   touched, so trying again is safe;
  /// - [CardTerminalException] from the POS. When its `outcomeUnknown` is
  ///   true the customer may have been charged: the payment stays pending in
  ///   Nexus Payments and must be checked against the POS before charging
  ///   again.
  ///
  /// When the POS answered but recording it failed (after a few attempts),
  /// it still resolves, with `recorded: false` and the POS's result.
  Future<CardPayment> chargeCard({
    required CardTerminal terminal,
    required String orderId,
    required num amount,
    String description = '',
    String? terminalId,
    void Function()? onPosStarted,
  }) async {
    final payment = await createCardPayment(
      orderId: orderId,
      amount: amount,
      description: description,
      terminalId: terminalId,
    );
    onPosStarted?.call();
    final result = await terminal.charge(
      amount: amount,
      orderId: payment.orderId,
      currency: payment.currency,
    );

    PaymentSdkException? lastError;
    for (var attempt = 0; attempt <= _reportRetryDelays.length; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(_reportRetryDelays[attempt - 1]);
      }
      try {
        return await reportCardResult(payment.id, result);
      } on PaymentSdkException catch (e) {
        lastError = e;
        if (!e.isRetryable) break;
      }
    }
    if (config.enableLogging) {
      debugPrint('[PaymentSdk] card result not recorded for '
          '${payment.orderId}: $lastError');
    }
    return payment.withCharge(result, recorded: false);
  }

  /// Polls [getPaymentStatus] every [interval] and emits each status change.
  ///
  /// Closes after a final status, after a non-retryable error, or with a
  /// [StatusWatchTimeoutException] once [timeout] passes. Retryable errors are
  /// emitted and polling continues. Cancelling the subscription stops it.
  Stream<PaymentStatus> watchPaymentStatus(
    String orderId, {
    Duration interval = const Duration(seconds: 3),
    Duration timeout = const Duration(minutes: 15),
  }) {
    if (interval <= Duration.zero) {
      throw ArgumentError.value(interval, 'interval', 'must be positive');
    }

    late final StreamController<PaymentStatus> controller;
    final elapsed = clock.stopwatch();
    Timer? timer;
    PaymentStatus? last;
    var stopped = false;

    void stop() {
      stopped = true;
      timer?.cancel();
      controller.close();
    }

    Future<void> poll() async {
      try {
        final status = await getPaymentStatus(orderId);
        if (stopped) return;
        if (status != last) controller.add(last = status);
        if (status.isFinal) return stop();
      } on PaymentSdkException catch (e) {
        if (stopped) return;
        controller.addError(e);
        if (!e.isRetryable) return stop();
      }

      if (elapsed.elapsed + interval > timeout) {
        controller.addError(StatusWatchTimeoutException(
          'No final status for $orderId within $timeout',
          lastStatus: last,
        ));
        return stop();
      }
      timer = Timer(interval, poll);
    }

    controller = StreamController(
      onListen: () {
        elapsed.start();
        unawaited(poll());
      },
      onCancel: () {
        stopped = true;
        timer?.cancel();
      },
    );
    return controller.stream;
  }

  /// Closes the HTTP connections. The instance cannot be used afterwards.
  void dispose() => _api.close();

  static String _pathSegment(String value, String name) {
    final id = value.trim();
    if (id.isEmpty) {
      throw ValidationException('$name must not be empty');
    }
    return Uri.encodeComponent(id);
  }
}
