import 'package:flutter/material.dart';

import '../core/payment_sdk.dart';
import '../exceptions/payment_sdk_exception.dart';
import '../models/payment_status.dart';
import '../models/qr_payment.dart';
import '../session/payment_session.dart';
import 'internal/payment_card.dart';
import 'internal/session_view.dart';

/// Complete QR payment view: shows the amount, generates the QR with a
/// countdown, lets the customer say "I paid", watches the status and reports
/// the outcome through the callbacks.
class PaymentCheckout extends StatefulWidget {
  const PaymentCheckout({
    super.key,
    required this.payments,
    required this.amount,
    required this.orderId,
    this.currency,
    this.description = '',
    this.qrTimeout = const Duration(minutes: 5),
    this.confirmTimeout = const Duration(seconds: 20),
    this.pollInterval = const Duration(seconds: 3),
    this.autoStart = false,
    this.nextOrderId,
    this.qrSize = 240,
    this.onSuccess,
    this.onError,
    this.onStatusChanged,
    this.onCancel,
    this.onNewQr,
    this.onTimeout,
  });

  final PaymentSdk payments;
  final num amount;
  final String orderId;

  /// Display only: the backend charges in the account's currency.
  final String? currency;
  final String description;

  /// How long the QR is offered. The countdown starts when it is shown, and
  /// the QR is created with the same expiration at the provider.
  final Duration qrTimeout;

  /// How long "Ya pagué" keeps checking before telling the customer the
  /// payment has not arrived yet.
  final Duration confirmTimeout;

  /// Time between background status checks.
  final Duration pollInterval;

  /// Generate the QR right away instead of waiting for the pay button.
  final bool autoStart;

  /// New order id for a new QR after a rejected or expired one. Without it
  /// [orderId] is reused.
  final String Function()? nextOrderId;
  final double qrSize;
  final ValueChanged<QrPayment>? onSuccess;
  final ValueChanged<PaymentSdkException>? onError;
  final ValueChanged<PaymentStatus>? onStatusChanged;

  /// Shows a cancel button. Before calling it the payment is checked once, so
  /// a QR that was already paid reports [onSuccess] instead.
  final VoidCallback? onCancel;

  /// Called instead of regenerating when the user asks for a new QR after a
  /// rejected or expired one. Use it when the host must create a new order.
  final VoidCallback? onNewQr;

  /// Called a few seconds after the QR expires unpaid, so the host can leave
  /// this screen. Without it a "new QR" button is shown instead.
  final VoidCallback? onTimeout;

  @override
  State<PaymentCheckout> createState() => _PaymentCheckoutState();
}

class _PaymentCheckoutState extends State<PaymentCheckout> {
  late final _session = PaymentSession(
    payments: widget.payments,
    orderId: widget.orderId,
    amount: widget.amount,
  );

  @override
  void initState() {
    super.initState();
    _sync();
    if (widget.autoStart) _session.start();
  }

  @override
  void didUpdateWidget(PaymentCheckout oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  /// Hands the current widget values to the session.
  void _sync() {
    _session.configure(
      amount: widget.amount,
      description: widget.description,
      qrTimeout: widget.qrTimeout,
      confirmTimeout: widget.confirmTimeout,
      pollInterval: widget.pollInterval,
      onSuccess: widget.onSuccess,
      onError: widget.onError,
      onStatusChanged: widget.onStatusChanged,
      onTimeout: widget.onTimeout,
    );
  }

  Future<void> _cancel() async {
    if (await _session.verifyBeforeLeaving()) widget.onCancel?.call();
  }

  void _newQr() {
    if (widget.onNewQr case final onNewQr?) return onNewQr();
    _session.start(orderId: widget.nextOrderId?.call());
  }

  @override
  Widget build(BuildContext context) {
    return PaymentCard(
      amount: widget.amount,
      currency: widget.currency,
      description: widget.description,
      child: SessionView(
        session: _session,
        qrSize: widget.qrSize,
        onNewQr: _newQr,
        onCancel: widget.onCancel == null ? null : _cancel,
      ),
    );
  }
}
