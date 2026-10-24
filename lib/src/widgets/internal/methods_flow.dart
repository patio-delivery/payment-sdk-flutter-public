import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/payment_sdk.dart';
import '../../exceptions/payment_sdk_exception.dart';
import '../../models/cash_payment.dart';
import '../../models/payment_method_info.dart';
import '../../models/payment_status.dart';
import '../../models/qr_payment.dart';
import '../../session/payment_session.dart';
import 'animations.dart';
import 'cash_checkout.dart';
import 'method_list.dart';
import 'payment_card.dart';
import 'session_view.dart';

/// Lets an owner (the payment sheet) ask the flow whether a QR is on screen
/// and verify it before closing.
class MethodsFlowController {
  _MethodsFlowState? _state;

  /// Whether a payment is in progress (a QR or its result is on screen).
  bool get isPaying => _state?._session != null;

  /// The cash payment on screen, once its code exists.
  CashPayment? get cashPayment => _state?._cashPayment;

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
    this.cashInstructionsTitle = 'Pagarás en caja',
    this.cashInstructionsMessage =
        'Te daremos un código de pago. Preséntalo en caja para completar '
            'tu compra.',
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
    this.onCashPayment,
    this.onCashDone,
    this.cashDoneLabel = 'Listo',
    this.autoSelectSingleMethod = true,
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
  final String cashInstructionsTitle;
  final String cashInstructionsMessage;
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

  /// Offers cash when the account has it, and is called once its code
  /// exists. Without it cash is never shown: an app that can't handle a
  /// pending cash order never gets one.
  final ValueChanged<CashPayment>? onCashPayment;

  /// Shows a [cashDoneLabel] button under the cash code (the sheet closes
  /// with it).
  final ValueChanged<CashPayment>? onCashDone;
  final String cashDoneLabel;

  /// With only one QR method available, go straight to it (no list, no
  /// instructions) the first time the methods load. Cancelling then shows
  /// the list, so the customer is not sent into a new QR on their own. Cash
  /// is never chosen on its own: it leaves an order pending.
  final bool autoSelectSingleMethod;

  @override
  State<MethodsFlow> createState() => _MethodsFlowState();
}

class _MethodsFlowState extends State<MethodsFlow> {
  late Future<List<PaymentMethodInfo>> _methods = _loadMethods();
  PaymentMethodInfo? _chosen;
  PaymentSession? _session;

  /// The cash order on screen, and its payment once the code exists.
  String? _cashOrderId;
  CashPayment? _cashPayment;
  String _description = '';
  bool _preparing = false;
  String? _orderError;

  /// Whether the single available method was already chosen automatically.
  bool _autoSelected = false;

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
    final acceptsCash = widget.onCashPayment != null;
    final supported = methods
        .where((m) => m.isSupported && (!m.isCash || acceptsCash))
        .toList();
    if (widget.autoSelectSingleMethod &&
        supported.length == 1 &&
        supported.single.isQr &&
        !_autoSelected &&
        _session == null &&
        mounted) {
      _autoSelected = true;
      unawaited(_select(supported.single));
    }
    return supported;
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
    if (method.isCash) {
      return setState(() {
        _preparing = false;
        _chosen = method;
        _description =
            widget.descriptionFor?.call(orderId) ?? widget.description;
        _cashOrderId = orderId;
      });
    }
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
      _cashOrderId = null;
      _cashPayment = null;
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

  MethodInstructions? _instructionsFor(PaymentMethodInfo method) {
    if (method.isQr) {
      return MethodInstructions(
        title: widget.qrInstructionsTitle,
        message: widget.qrInstructionsMessage,
      );
    }
    if (method.isCash) {
      return MethodInstructions(
        title: widget.cashInstructionsTitle,
        message: widget.cashInstructionsMessage,
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final cashOrderId = _cashOrderId;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: session != null
          ? KeyedSubtree(
              key: ValueKey(session),
              child: Center(child: _checkout(session)),
            )
          : cashOrderId != null
              ? KeyedSubtree(
                  key: ValueKey('cash-$cashOrderId'),
                  child: Center(child: _cashCheckout(cashOrderId)),
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

  Widget _cashCheckout(String orderId) {
    final view = CashCheckout(
      payments: widget.payments,
      orderId: orderId,
      amount: widget.amount,
      description: _description,
      onCreated: (cash) {
        _cashPayment = cash;
        widget.onCashPayment?.call(cash);
      },
      onError: widget.onError,
      onBack: _backToMethods,
      onDone: widget.onCashDone,
      doneLabel: widget.cashDoneLabel,
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
            backLabel: widget.backLabel,
            onBack: widget.onBack,
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
            if (methods.isEmpty && widget.onBack != null) ...[
              const SizedBox(height: 16),
              Center(
                child: _BackButton(
                  label: widget.backLabel,
                  onPressed: widget.onBack!,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({
    required this.message,
    required this.onRetry,
    required this.backLabel,
    this.onBack,
  });

  final String message;
  final VoidCallback onRetry;
  final String backLabel;
  final VoidCallback? onBack;

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
          Wrap(
            spacing: 12,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              if (onBack case final onBack?)
                _BackButton(label: backLabel, onPressed: onBack),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => TextButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.arrow_back),
        label: Text(label),
      );
}
