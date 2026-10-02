import 'dart:async';

import 'package:flutter/material.dart';

import '../core/payment_sdk.dart';
import '../exceptions/payment_sdk_exception.dart';
import '../models/payment_method_info.dart';
import '../models/payment_status.dart';
import '../models/qr_payment.dart';
import 'internal/methods_flow.dart';

/// How a payment sheet ended.
enum PaymentSheetStatus {
  /// The payment was confirmed.
  paid,

  /// The QR expired unpaid.
  expired,

  /// The customer closed the sheet without paying.
  cancelled,
}

/// What [PaymentSheet.show] resolves to.
class PaymentSheetResult {
  const PaymentSheetResult(this.status, {this.payment, this.method});

  final PaymentSheetStatus status;

  /// The confirmed payment, when [status] is [PaymentSheetStatus.paid].
  final QrPayment? payment;

  /// The method the customer chose, if any.
  final PaymentMethodInfo? method;

  bool get isPaid => status == PaymentSheetStatus.paid;

  @override
  String toString() => 'PaymentSheetResult(${status.name})';
}

/// V3 · Payment Sheet: the app keeps its cart and a "Pay" button; the SDK
/// opens its own window with the account's payment methods and the checkout,
/// and tells the app how it ended.
///
/// ```dart
/// final result = await PaymentSheet.show(
///   context,
///   payments: payments,
///   amount: 150,
///   orderId: 'ORDER-123',
/// );
/// if (result.isPaid) ...
/// ```
///
/// On narrow screens it slides up from the bottom; on wide ones (kiosks,
/// tablets, desktop) it opens as a centered dialog. Closing it while a QR is
/// on screen checks the payment first: a QR that was paid reports
/// [PaymentSheetStatus.paid], never [PaymentSheetStatus.cancelled].
abstract final class PaymentSheet {
  /// Screens at least this wide get a centered dialog.
  static const dialogMinWidth = 600.0;

  static Future<PaymentSheetResult> show(
    BuildContext context, {
    required PaymentSdk payments,
    required num amount,
    String? orderId,
    Future<String> Function(PaymentMethodInfo method)? createOrderId,
    String? currency,
    String description = '',
    String Function(String orderId)? descriptionFor,
    String title = 'Pagar',
    String methodsTitle = '¿Con qué vas a pagar?',
    String confirmLabel = 'Confirmar',
    String backLabel = 'Volver',
    String qrInstructionsTitle = 'Prepárate para escanear',
    String qrInstructionsMessage =
        'Tu código QR aparecerá en la siguiente pantalla. '
            'Apúntalo con tu cámara y completa el pago.',
    Duration qrTimeout = const Duration(minutes: 5),
    Duration confirmTimeout = const Duration(seconds: 20),
    Duration pollInterval = const Duration(seconds: 3),
    Duration successDelay = const Duration(seconds: 2),
    double qrSize = 240,
    ValueChanged<PaymentMethodInfo>? onMethodSelected,
    ValueChanged<PaymentSdkException>? onError,
    ValueChanged<PaymentStatus>? onStatusChanged,
  }) async {
    assert(
      orderId != null || createOrderId != null,
      'PaymentSheet needs an orderId or a createOrderId',
    );
    final body = _SheetBody(
      payments: payments,
      amount: amount,
      orderId: orderId,
      createOrderId: createOrderId,
      currency: currency,
      description: description,
      descriptionFor: descriptionFor,
      title: title,
      methodsTitle: methodsTitle,
      confirmLabel: confirmLabel,
      backLabel: backLabel,
      qrInstructionsTitle: qrInstructionsTitle,
      qrInstructionsMessage: qrInstructionsMessage,
      qrTimeout: qrTimeout,
      confirmTimeout: confirmTimeout,
      pollInterval: pollInterval,
      successDelay: successDelay,
      qrSize: qrSize,
      onMethodSelected: onMethodSelected,
      onError: onError,
      onStatusChanged: onStatusChanged,
    );

    // Closing is only through the sheet's own button or the back gesture,
    // both of which verify a QR on screen first.
    final wide = MediaQuery.sizeOf(context).width >= dialogMinWidth;
    final result = wide
        ? await showDialog<PaymentSheetResult>(
            context: context,
            barrierDismissible: false,
            builder: (_) => Dialog(
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: body,
              ),
            ),
          )
        : await showModalBottomSheet<PaymentSheetResult>(
            context: context,
            isScrollControlled: true,
            isDismissible: false,
            enableDrag: false,
            useSafeArea: true,
            builder: (_) => body,
          );
    return result ?? const PaymentSheetResult(PaymentSheetStatus.cancelled);
  }
}

class _SheetBody extends StatefulWidget {
  const _SheetBody({
    required this.payments,
    required this.amount,
    required this.orderId,
    required this.createOrderId,
    required this.currency,
    required this.description,
    required this.descriptionFor,
    required this.title,
    required this.methodsTitle,
    required this.confirmLabel,
    required this.backLabel,
    required this.qrInstructionsTitle,
    required this.qrInstructionsMessage,
    required this.qrTimeout,
    required this.confirmTimeout,
    required this.pollInterval,
    required this.successDelay,
    required this.qrSize,
    required this.onMethodSelected,
    required this.onError,
    required this.onStatusChanged,
  });

  final PaymentSdk payments;
  final num amount;
  final String? orderId;
  final Future<String> Function(PaymentMethodInfo method)? createOrderId;
  final String? currency;
  final String description;
  final String Function(String orderId)? descriptionFor;
  final String title;
  final String methodsTitle;
  final String confirmLabel;
  final String backLabel;
  final String qrInstructionsTitle;
  final String qrInstructionsMessage;
  final Duration qrTimeout;
  final Duration confirmTimeout;
  final Duration pollInterval;
  final Duration successDelay;
  final double qrSize;
  final ValueChanged<PaymentMethodInfo>? onMethodSelected;
  final ValueChanged<PaymentSdkException>? onError;
  final ValueChanged<PaymentStatus>? onStatusChanged;

  @override
  State<_SheetBody> createState() => _SheetBodyState();
}

class _SheetBodyState extends State<_SheetBody> {
  final _flow = MethodsFlowController();
  PaymentMethodInfo? _method;
  bool _closing = false;
  bool _done = false;
  Timer? _successTimer;

  @override
  void dispose() {
    _successTimer?.cancel();
    super.dispose();
  }

  void _finish(PaymentSheetResult result) {
    if (_done || !mounted) return;
    _done = true;
    Navigator.of(context).pop(result);
  }

  void _onMethodSelected(PaymentMethodInfo method) {
    setState(() => _method = method);
    widget.onMethodSelected?.call(method);
  }

  void _onSuccess(QrPayment payment) {
    // Let the customer see "¡Pago confirmado!" before closing.
    _successTimer = Timer(
      widget.successDelay,
      () => _finish(PaymentSheetResult(
        PaymentSheetStatus.paid,
        payment: payment,
        method: _method,
      )),
    );
  }

  Future<void> _requestClose() async {
    if (_closing || _done) return;
    if (!_flow.isPaying) {
      return _finish(PaymentSheetResult(
        PaymentSheetStatus.cancelled,
        method: _method,
      ));
    }
    setState(() => _closing = true);
    final canLeave = await _flow.verifyBeforeLeaving();
    if (!mounted) return;
    setState(() => _closing = false);
    // When the QR turned out paid, the flow reports success and closes.
    if (canLeave) {
      _finish(PaymentSheetResult(
        PaymentSheetStatus.cancelled,
        method: _method,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currency = _method?.currency ?? widget.currency;
    final amount = [currency, widget.amount.toStringAsFixed(2)]
        .whereType<String>()
        .join(' ');

    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _requestClose();
      },
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.92,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          amount,
                          style: theme.textTheme.headlineMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        if (widget.description.isNotEmpty)
                          Text(
                            widget.description,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  _closing
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox.square(
                            dimension: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : IconButton(
                          tooltip: 'Cerrar',
                          onPressed: _requestClose,
                          icon: const Icon(Icons.close),
                        ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
                child: MethodsFlow(
                  controller: _flow,
                  showCard: false,
                  payments: widget.payments,
                  amount: widget.amount,
                  orderId: widget.orderId,
                  createOrderId: widget.createOrderId,
                  currency: widget.currency,
                  description: widget.description,
                  descriptionFor: widget.descriptionFor,
                  title: widget.methodsTitle,
                  confirmLabel: widget.confirmLabel,
                  backLabel: widget.backLabel,
                  qrInstructionsTitle: widget.qrInstructionsTitle,
                  qrInstructionsMessage: widget.qrInstructionsMessage,
                  qrTimeout: widget.qrTimeout,
                  confirmTimeout: widget.confirmTimeout,
                  pollInterval: widget.pollInterval,
                  qrSize: widget.qrSize,
                  onMethodSelected: _onMethodSelected,
                  onSuccess: _onSuccess,
                  onError: widget.onError,
                  onStatusChanged: widget.onStatusChanged,
                  onTimeout: () => _finish(PaymentSheetResult(
                    PaymentSheetStatus.expired,
                    method: _method,
                  )),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
