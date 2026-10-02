import 'dart:async';

import 'package:clock/clock.dart';
import 'package:dio/dio.dart' show HttpClientAdapter;

import '../config/payment_sdk_config.dart';
import '../exceptions/payment_sdk_exception.dart';
import '../models/payment_method_info.dart';
import '../models/payment_status.dart';
import '../models/qr_payment.dart';
import 'api_client.dart';

/// Entry point of the SDK. Every method throws [PaymentSdkException] on
/// failure.
class PaymentSdk {
  /// [httpClientAdapter] replaces the HTTP transport (tests, proxies).
  PaymentSdk({
    required PaymentSdkConfig config,
    HttpClientAdapter? httpClientAdapter,
  }) : _api = ApiClient(config, httpClientAdapter: httpClientAdapter);

  final ApiClient _api;

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
