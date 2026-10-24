import 'package:flutter/material.dart';

import '../../core/payment_sdk.dart';
import '../../exceptions/payment_sdk_exception.dart';
import '../../models/cash_payment.dart';
import 'animations.dart';
import 'responsive.dart';

/// The cash payment of one order: creates it, then shows its code for the
/// payer to take to the cashier. Shared by V2 and the payment sheet.
///
/// Once the code exists there is no going back from here: the payment stays
/// pending until a collector resolves it.
class CashCheckout extends StatefulWidget {
  const CashCheckout({
    super.key,
    required this.payments,
    required this.orderId,
    required this.amount,
    this.description = '',
    this.onCreated,
    this.onError,
    this.onBack,
    this.onDone,
    this.doneLabel = 'Listo',
  });

  final PaymentSdk payments;
  final String orderId;
  final num amount;
  final String description;

  /// Called once the code exists.
  final ValueChanged<CashPayment>? onCreated;
  final ValueChanged<PaymentSdkException>? onError;

  /// "Volver" when the code could not be created.
  final VoidCallback? onBack;

  /// Shows a [doneLabel] button under the code.
  final ValueChanged<CashPayment>? onDone;
  final String doneLabel;

  @override
  State<CashCheckout> createState() => _CashCheckoutState();
}

class _CashCheckoutState extends State<CashCheckout> {
  CashPayment? _cash;
  PaymentSdkException? _error;

  @override
  void initState() {
    super.initState();
    _create();
  }

  Future<void> _create() async {
    if (_error != null) setState(() => _error = null);
    try {
      // Asking again for the same order returns the same code, so a retry
      // never creates a second pending payment.
      final cash = await widget.payments.createCashPayment(
        orderId: widget.orderId,
        amount: widget.amount,
        description: widget.description,
      );
      if (!mounted) return;
      setState(() => _cash = cash);
      widget.onCreated?.call(cash);
    } on PaymentSdkException catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
      widget.onError?.call(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cash = _cash;
    final error = _error;
    final Widget child;
    if (cash != null) {
      child = _created(cash);
    } else if (error != null) {
      child = _failed(error);
    } else {
      child = const PulseLoader(
        icon: Icons.payments_outlined,
        title: 'Generando tu código de pago…',
      );
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      child: KeyedSubtree(
        key: ValueKey(cash != null
            ? 'code'
            : error != null
                ? 'error'
                : 'busy'),
        child: child,
      ),
    );
  }

  Widget _created(CashPayment cash) {
    final onDone = widget.onDone;
    final height =
        Responsive.pick<double>(context, compact: 48, regular: 52, large: 60);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CashCodeView(code: cash.code),
        if (onDone != null) ...[
          SizedBox(height: height * 0.45),
          SizedBox(
            width: double.infinity,
            height: height,
            child: FilledButton(
              onPressed: () => onDone(cash),
              child: Text(widget.doneLabel),
            ),
          ),
        ],
      ],
    );
  }

  Widget _failed(PaymentSdkException error) {
    final onBack = widget.onBack;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ResultBadge(
          icon: Icons.wifi_off_rounded,
          color: Theme.of(context).colorScheme.error,
          title: 'No pudimos generar tu código',
          message: error.message,
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            if (onBack != null)
              TextButton.icon(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back),
                label: const Text('Volver'),
              ),
            OutlinedButton.icon(
              onPressed: _create,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ],
    );
  }
}

/// The cash code, large and easy to read aloud, with what to do with it.
class CashCodeView extends StatelessWidget {
  const CashCodeView({super.key, required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final side =
        Responsive.pick<double>(context, compact: 56, regular: 72, large: 88);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 600),
          curve: Curves.elasticOut,
          builder: (context, scale, child) =>
              Transform.scale(scale: scale, child: child),
          child: Container(
            width: side,
            height: side,
            decoration: BoxDecoration(
              color: colors.primary.withAlpha(30),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.storefront_outlined,
              color: colors.primary,
              size: side * 0.55,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Tu código de pago',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium
              ?.copyWith(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.primary, width: 2),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              code,
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Preséntalo en caja para completar tu pago. '
          'Tu pedido queda pendiente hasta entonces.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
      ],
    );
  }
}
