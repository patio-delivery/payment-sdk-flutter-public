import 'package:flutter/material.dart';

import '../core/payment_sdk.dart';
import '../exceptions/payment_sdk_exception.dart';
import '../models/payment_method_info.dart';
import '../models/payment_status.dart';
import '../models/payment_version.dart';
import '../models/qr_payment.dart';
import 'internal/animations.dart';
import 'internal/responsive.dart';
import 'payment_checkout.dart';
import 'payment_methods.dart';
import 'payment_sheet.dart';

/// One integration for every SDK version: the app passes the payment once
/// and [version] decides what the customer sees.
///
/// ```dart
/// PaymentFlow(
///   version: PaymentVersion.tryParse(config) ?? PaymentVersion.v1,
///   payments: payments,
///   amount: 150,
///   orderId: 'ORDER-123',
///   onSuccess: (payment) => ...,
///   onCancel: () => ...,
///   onTimeout: () => ...,
/// )
/// ```
///
/// | Version | The customer sees |
/// |---|---|
/// | [PaymentVersion.v1] | The QR checkout right away. |
/// | [PaymentVersion.v2] | The account's methods, then the checkout. |
/// | [PaymentVersion.v3] | A pay button that opens the payment window. |
///
/// The callbacks mean the same in every version: [onSuccess] once the
/// payment is confirmed, [onCancel] when the customer leaves unpaid (checked
/// first), [onTimeout] when the QR expires unpaid.
class PaymentFlow extends StatelessWidget {
  const PaymentFlow({
    super.key,
    required this.version,
    required this.payments,
    required this.amount,
    this.orderId,
    this.createOrderId,
    this.currency,
    this.description = '',
    this.descriptionFor,
    this.payLabel = 'Pagar',
    this.methodsTitle = '¿Con qué vas a pagar hoy?',
    this.confirmLabel = 'Confirmar',
    this.backLabel = 'Volver',
    this.qrInstructionsTitle = 'Prepárate para escanear',
    this.qrInstructionsMessage =
        'Tu código QR aparecerá en la siguiente pantalla. '
            'Apúntalo con tu cámara y completa el pago.',
    this.autoOpen = false,
    this.qrTimeout = const Duration(minutes: 5),
    this.confirmTimeout = const Duration(seconds: 20),
    this.pollInterval = const Duration(seconds: 3),
    this.successDelay = const Duration(seconds: 2),
    this.qrSize = 240,
    this.onMethodSelected,
    this.onSuccess,
    this.onError,
    this.onStatusChanged,
    this.onTimeout,
    this.onCancel,
    this.onBack,
    this.autoSelectSingleMethod = true,
  }) : assert(
          orderId != null || createOrderId != null,
          'PaymentFlow needs an orderId or a createOrderId',
        );

  /// What the customer sees. Changing it rebuilds the payment from scratch.
  final PaymentVersion version;

  final PaymentSdk payments;
  final num amount;

  /// Your unique reference for this payment, when it already exists.
  final String? orderId;

  /// Creates the order when the payment starts (V1) or once a method is
  /// chosen (V2, V3); resolves to its id.
  final Future<String> Function(PaymentMethodInfo method)? createOrderId;

  /// Shown next to the amount (display only).
  final String? currency;

  /// Text sent with the payment (the QR's glosa) and shown with the amount.
  final String description;

  /// Builds the description once the order id is known. Takes precedence
  /// over [description].
  final String Function(String orderId)? descriptionFor;

  /// V3: the pay button and the window's title.
  final String payLabel;

  /// V2 and V3: title of the methods list.
  final String methodsTitle;
  final String confirmLabel;
  final String backLabel;
  final String qrInstructionsTitle;
  final String qrInstructionsMessage;

  /// V3: open the payment window right away instead of showing the button.
  final bool autoOpen;
  final Duration qrTimeout;
  final Duration confirmTimeout;
  final Duration pollInterval;

  /// V3: how long "¡Pago confirmado!" shows before the window closes.
  final Duration successDelay;

  /// Largest QR side; it shrinks to fit the screen.
  final double qrSize;
  final ValueChanged<PaymentMethodInfo>? onMethodSelected;
  final ValueChanged<QrPayment>? onSuccess;
  final ValueChanged<PaymentSdkException>? onError;
  final ValueChanged<PaymentStatus>? onStatusChanged;

  /// The QR expired unpaid.
  final VoidCallback? onTimeout;

  /// The customer left without paying. In V1 this also shows the cancel
  /// button.
  final VoidCallback? onCancel;

  /// V2: shows a back button when there is nothing to pay with (the methods
  /// could not be loaded or none is available). V3's window always shows it
  /// in that case and closes, reporting [onCancel]. V1 does not load methods.
  final VoidCallback? onBack;

  /// V2 and V3: with only one method available, go straight to it the
  /// first time the methods load, without the list or the instructions.
  final bool autoSelectSingleMethod;

  @override
  Widget build(BuildContext context) => switch (version) {
        PaymentVersion.v1 => _DirectPayment(flow: this),
        PaymentVersion.v2 => PaymentMethods(
            payments: payments,
            amount: amount,
            orderId: orderId,
            createOrderId: createOrderId,
            currency: currency,
            description: description,
            descriptionFor: descriptionFor,
            title: methodsTitle,
            confirmLabel: confirmLabel,
            backLabel: backLabel,
            qrInstructionsTitle: qrInstructionsTitle,
            qrInstructionsMessage: qrInstructionsMessage,
            qrTimeout: qrTimeout,
            confirmTimeout: confirmTimeout,
            pollInterval: pollInterval,
            qrSize: qrSize,
            onMethodSelected: onMethodSelected,
            onSuccess: onSuccess,
            onError: onError,
            onStatusChanged: onStatusChanged,
            onTimeout: onTimeout,
            onCancel: onCancel,
            onBack: onBack,
            autoSelectSingleMethod: autoSelectSingleMethod,
          ),
        PaymentVersion.v3 => _SheetLauncher(flow: this),
      };
}

/// V1: creates the order if needed, then the QR checkout starts right away.
class _DirectPayment extends StatefulWidget {
  const _DirectPayment({required this.flow});

  final PaymentFlow flow;

  @override
  State<_DirectPayment> createState() => _DirectPaymentState();
}

class _DirectPaymentState extends State<_DirectPayment> {
  static const _qr = PaymentMethodInfo(
    code: PaymentMethodInfo.qrCode,
    name: 'Pago QR',
  );

  late String? _orderId = widget.flow.orderId;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    if (_orderId == null) _createOrder();
  }

  Future<void> _createOrder() async {
    if (_failed) setState(() => _failed = false);
    try {
      final id = await widget.flow.createOrderId!(_qr);
      if (mounted) setState(() => _orderId = id);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final flow = widget.flow;
    final orderId = _orderId;
    if (orderId == null) {
      return Center(child: _failed ? _orderError() : _preparing());
    }
    return Center(
      child: PaymentCheckout(
        key: ValueKey(orderId),
        payments: flow.payments,
        amount: flow.amount,
        orderId: orderId,
        currency: flow.currency,
        description: flow.descriptionFor?.call(orderId) ?? flow.description,
        autoStart: true,
        qrTimeout: flow.qrTimeout,
        confirmTimeout: flow.confirmTimeout,
        pollInterval: flow.pollInterval,
        qrSize: flow.qrSize,
        onSuccess: flow.onSuccess,
        onError: flow.onError,
        onStatusChanged: flow.onStatusChanged,
        onCancel: flow.onCancel,
        onTimeout: flow.onTimeout,
      ),
    );
  }

  Widget _preparing() => const PulseLoader(
        icon: Icons.receipt_long_outlined,
        title: 'Preparando tu pago…',
      );

  Widget _orderError() {
    final onCancel = widget.flow.onCancel;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ResultBadge(
          icon: Icons.error_outline,
          color: Theme.of(context).colorScheme.error,
          title: 'No se pudo preparar el pago',
          message: 'Intenta de nuevo.',
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _createOrder,
          icon: const Icon(Icons.refresh),
          label: const Text('Reintentar'),
        ),
        if (onCancel != null)
          TextButton(onPressed: onCancel, child: const Text('Cancelar')),
      ],
    );
  }
}

/// V3: the pay button; the payment happens in [PaymentSheet].
class _SheetLauncher extends StatefulWidget {
  const _SheetLauncher({required this.flow});

  final PaymentFlow flow;

  @override
  State<_SheetLauncher> createState() => _SheetLauncherState();
}

class _SheetLauncherState extends State<_SheetLauncher> {
  bool _open = false;

  @override
  void initState() {
    super.initState();
    if (widget.flow.autoOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openSheet();
      });
    }
  }

  Future<void> _openSheet() async {
    if (_open) return;
    final flow = widget.flow;
    setState(() => _open = true);
    final result = await PaymentSheet.show(
      context,
      payments: flow.payments,
      amount: flow.amount,
      orderId: flow.orderId,
      createOrderId: flow.createOrderId,
      currency: flow.currency,
      description: flow.description,
      descriptionFor: flow.descriptionFor,
      title: flow.payLabel,
      methodsTitle: flow.methodsTitle,
      confirmLabel: flow.confirmLabel,
      backLabel: flow.backLabel,
      qrInstructionsTitle: flow.qrInstructionsTitle,
      qrInstructionsMessage: flow.qrInstructionsMessage,
      qrTimeout: flow.qrTimeout,
      confirmTimeout: flow.confirmTimeout,
      pollInterval: flow.pollInterval,
      successDelay: flow.successDelay,
      qrSize: flow.qrSize,
      onMethodSelected: flow.onMethodSelected,
      onError: flow.onError,
      onStatusChanged: flow.onStatusChanged,
      autoSelectSingleMethod: flow.autoSelectSingleMethod,
    );
    if (mounted) setState(() => _open = false);
    switch (result.status) {
      case PaymentSheetStatus.paid:
        flow.onSuccess?.call(result.payment!);
      case PaymentSheetStatus.expired:
        flow.onTimeout?.call();
      case PaymentSheetStatus.cancelled:
        flow.onCancel?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final flow = widget.flow;
    if (_open) {
      // The payment happens in the window on top of this view.
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Procesando tu pago…',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge,
        ),
      );
    }
    final height =
        Responsive.pick<double>(context, compact: 56, regular: 64, large: 80);
    final amount = [flow.currency, flow.amount.toStringAsFixed(2)]
        .whereType<String>()
        .join(' ');
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SizedBox(
          width: double.infinity,
          height: height,
          child: FilledButton.icon(
            onPressed: _openSheet,
            icon: Icon(Icons.lock_outline, size: height * 0.38),
            label: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '${flow.payLabel} $amount',
                style: (height >= 64
                        ? theme.textTheme.headlineSmall
                        : theme.textTheme.titleLarge)
                    ?.copyWith(
                  color: theme.colorScheme.onPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
