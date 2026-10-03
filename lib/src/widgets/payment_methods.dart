import 'package:flutter/material.dart';

import '../core/payment_sdk.dart';
import '../exceptions/payment_sdk_exception.dart';
import '../models/payment_method_info.dart';
import '../models/payment_status.dart';
import '../models/qr_payment.dart';
import 'internal/methods_flow.dart';

/// Embedded payment methods: the SDK asks the backend which methods the
/// account offers, shows them and processes the chosen one. The app keeps
/// its cart and total; it only says how much to charge.
///
/// ```dart
/// PaymentMethods(
///   payments: payments,
///   amount: 150,
///   orderId: 'ORDER-123',
///   onSuccess: (payment) => ...,
/// )
/// ```
///
/// When the app creates its order only after the method is chosen, pass
/// [createOrderId] instead of [orderId].
class PaymentMethods extends StatefulWidget {
  const PaymentMethods({
    super.key,
    required this.payments,
    required this.amount,
    this.orderId,
    this.createOrderId,
    this.currency,
    this.description = '',
    this.descriptionFor,
    this.title = '¿Con qué vas a pagar hoy?',
    this.confirmLabel = 'Confirmar',
    this.backLabel = 'Volver',
    this.qrInstructionsTitle = 'Prepárate para escanear',
    this.qrInstructionsMessage =
        'Tu código QR aparecerá en la siguiente pantalla. '
            'Apúntalo con tu cámara y completa el pago.',
    this.qrTimeout = const Duration(minutes: 5),
    this.confirmTimeout = const Duration(seconds: 20),
    this.pollInterval = const Duration(seconds: 3),
    this.qrSize = 240,
    this.onMethodSelected,
    this.onSuccess,
    this.onError,
    this.onStatusChanged,
    this.onTimeout,
    this.onCancel,
    this.onBack,
  }) : assert(
          orderId != null || createOrderId != null,
          'PaymentMethods needs an orderId or a createOrderId',
        );

  final PaymentSdk payments;
  final num amount;

  /// Your unique reference for this payment, when it already exists.
  final String? orderId;

  /// Creates the order once a method is chosen; resolves to its id.
  final Future<String> Function(PaymentMethodInfo method)? createOrderId;

  /// Shown next to the amount when the backend does not send a currency.
  final String? currency;

  /// Text sent with the payment (the QR's glosa; some providers require
  /// it) and shown on the card.
  final String description;

  /// Builds the description once the order id is known, for apps that
  /// create the order after the method is chosen. Takes precedence over
  /// [description].
  final String Function(String orderId)? descriptionFor;
  final String? title;
  final String confirmLabel;
  final String backLabel;
  final String qrInstructionsTitle;
  final String qrInstructionsMessage;
  final Duration qrTimeout;
  final Duration confirmTimeout;
  final Duration pollInterval;
  final double qrSize;
  final ValueChanged<PaymentMethodInfo>? onMethodSelected;
  final ValueChanged<QrPayment>? onSuccess;
  final ValueChanged<PaymentSdkException>? onError;
  final ValueChanged<PaymentStatus>? onStatusChanged;

  /// Called a few seconds after the QR expires unpaid. Without it the
  /// customer can go back to the methods.
  final VoidCallback? onTimeout;

  /// Called when the customer cancels a QR, once it is verified unpaid. The
  /// view then goes back to the methods.
  final VoidCallback? onCancel;

  /// Shows a back button when there is nothing to pay with: the methods
  /// could not be loaded or none is available. Without it only "Reintentar"
  /// is offered.
  final VoidCallback? onBack;

  @override
  State<PaymentMethods> createState() => _PaymentMethodsState();
}

class _PaymentMethodsState extends State<PaymentMethods> {
  @override
  Widget build(BuildContext context) {
    final w = widget;
    return MethodsFlow(
      payments: w.payments,
      amount: w.amount,
      orderId: w.orderId,
      createOrderId: w.createOrderId,
      currency: w.currency,
      description: w.description,
      descriptionFor: w.descriptionFor,
      title: w.title,
      confirmLabel: w.confirmLabel,
      backLabel: w.backLabel,
      qrInstructionsTitle: w.qrInstructionsTitle,
      qrInstructionsMessage: w.qrInstructionsMessage,
      qrTimeout: w.qrTimeout,
      confirmTimeout: w.confirmTimeout,
      pollInterval: w.pollInterval,
      qrSize: w.qrSize,
      onMethodSelected: w.onMethodSelected,
      onSuccess: w.onSuccess,
      onError: w.onError,
      onStatusChanged: w.onStatusChanged,
      onTimeout: w.onTimeout,
      onCancel: w.onCancel,
      onBack: w.onBack,
    );
  }
}
