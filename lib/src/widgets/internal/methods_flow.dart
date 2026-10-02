import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/payment_sdk.dart';
import '../../exceptions/payment_sdk_exception.dart';
import '../../models/payment_method_info.dart';
import '../../models/payment_status.dart';
import '../../models/qr_payment.dart';
import '../../session/payment_session.dart';
import 'animations.dart';
import 'method_list.dart';
import 'payment_card.dart';
import 'session_view.dart';

/// Lets an owner (the payment sheet) ask the flow whether a QR is on screen
/// and verify it before closing.
class MethodsFlowController {
  _MethodsFlowState? _state;

  /// Whether a payment is in progress (a QR or its result is on screen).
  bool get isPaying => _state?._session != null;

  /// Checks a QR on screen before leaving. True when it is safe to leave;
  /// false when the QR was in fact paid (the flow then reports success).
  Future<bool> verifyBeforeLeaving() async =>
      await _state?._session?.verifyBeforeLeaving() ?? true;
}

/// The "choose a method, then pay" flow shared by [PaymentMethods] (V2) and
/// the payment sheet (V3): loads the account's methods from the backend,
/// shows them and runs a [PaymentSession] for the chosen one.
class MethodsFlow extends StatefulWidget {
  const MethodsFlow({
    super.key,
    this.controller,
    this.showCard = true,
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
  }) : assert(
          orderId != null || createOrderId != null,
          'A payment needs an orderId or a createOrderId',
        );

  final MethodsFlowController? controller;

  /// Wraps the checkout in the card with the total. The sheet has its own
  /// header, so it turns this off.
  final bool showCard;

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

  @override
  State<MethodsFlow> createState() => _MethodsFlowState();
}

class _MethodsFlowState extends State<MethodsFlow> {
  late Future<List<PaymentMethodInfo>> _methods = _loadMethods();
  PaymentMethodInfo? _chosen;
  PaymentSession? _session;
  String _description = '';
  bool _preparing = false;
  String? _orderError;

  @override
  void initState() {
    super.initState();
    widget.controller?._state = this;
  }

  @override
  void didUpdateWidget(MethodsFlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._state = null;
      widget.controller?._state = this;
    }
    _sync();
  }

  @override
  void dispose() {
    if (widget.controller?._state == this) widget.controller?._state = null;
    _session?.dispose();
    super.dispose();
  }

  Future<List<PaymentMethodInfo>> _loadMethods() async {
    final methods = await widget.payments.getPaymentMethods();
    return methods.where((m) => m.isSupported).toList();
  }

  /// Hands the current widget values to the session.
  void _sync() {
    _session?.configure(
      amount: widget.amount,
      description: _description,
      qrTimeout: widget.qrTimeout,
      confirmTimeout: widget.confirmTimeout,
      pollInterval: widget.pollInterval,
      onSuccess: widget.onSuccess,
      onError: widget.onError,
      onStatusChanged: widget.onStatusChanged,
      onTimeout: widget.onTimeout,
    );
  }

  Future<void> _select(PaymentMethodInfo method) async {
    widget.onMethodSelected?.call(method);
    setState(() {
      _preparing = true;
      _orderError = null;
    });
    final String orderId;
    try {
      orderId = widget.orderId ?? await widget.createOrderId!(method);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _preparing = false;
        _orderError = 'No se pudo preparar el pago. Intenta de nuevo.';
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _preparing = false;
      _chosen = method;
      _description = widget.descriptionFor?.call(orderId) ?? widget.description;
      _session = PaymentSession(
        payments: widget.payments,
        orderId: orderId,
        amount: widget.amount,
      );
      _sync();
    });
    unawaited(_session!.start());
  }

  void _backToMethods() {
    _session?.dispose();
    setState(() {
      _session = null;
      _chosen = null;
    });
  }

  Future<void> _cancel() async {
    final session = _session;
    if (session != null && await session.verifyBeforeLeaving()) {
      if (!mounted) return;
      _backToMethods();
      widget.onCancel?.call();
    }
  }

  MethodInstructions? _instructionsFor(PaymentMethodInfo method) => method.isQr
      ? MethodInstructions(
          title: widget.qrInstructionsTitle,
          message: widget.qrInstructionsMessage,
        )
      : null;

  @override
  Widget build(BuildContext context) {
    final session = _session;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: session != null
          ? KeyedSubtree(
              key: ValueKey(session),
              child: Center(child: _checkout(session)),
            )
          : KeyedSubtree(
              key: const ValueKey('methods'),
              // Keeps the cards a readable size on wide screens.
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: _methodsView(),
                ),
              ),
            ),
    );
  }

  Widget _checkout(PaymentSession session) {
    final view = SessionView(
      session: session,
      qrSize: widget.qrSize,
      onNewQr: _backToMethods,
      onCancel: _cancel,
    );
    if (!widget.showCard) return view;
    return PaymentCard(
      amount: widget.amount,
      currency: _chosen?.currency ?? widget.currency,
      description: _description,
      child: view,
    );
  }

  Widget _methodsView() {
    if (_preparing) {
      return const Center(
        child: PulseLoader(
          icon: Icons.receipt_long_outlined,
          title: 'Preparando tu pago…',
        ),
      );
    }
    return FutureBuilder<List<PaymentMethodInfo>>(
      future: _methods,
      builder: (context, snapshot) {
        // A retry keeps the previous error until it finishes: show loading.
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          );
        }
        if (snapshot.hasError) {
          final error = snapshot.error;
          return _LoadError(
            message: error is PaymentSdkException
                ? error.message
                : 'No se pudieron cargar los métodos de pago',
            onRetry: () => setState(() {
              _methods = _loadMethods();
            }),
          );
        }
        final methods = snapshot.data ?? const <PaymentMethodInfo>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_orderError case final message?) ...[
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 12),
            ],
            MethodList(
              methods: methods,
              title: widget.title,
              confirmLabel: widget.confirmLabel,
              backLabel: widget.backLabel,
              instructionsFor: _instructionsFor,
              onSelected: _select,
            ),
          ],
        );
      },
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.wifi_off_rounded,
            size: 48,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }
}
