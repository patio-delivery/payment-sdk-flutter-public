import 'package:flutter/material.dart';

import '../../card/card_terminal.dart';
import '../../core/payment_sdk.dart';
import '../../exceptions/payment_sdk_exception.dart';
import '../../models/card_payment.dart';
import 'animations.dart';
import 'responsive.dart';

enum _CardPhase {
  /// Registering the payment in Nexus Payments; the POS is not touched yet.
  registering,

  /// The POS is waiting for the card. Nothing can be cancelled from here.
  charging,
  approved,
  rejected,

  /// The payment could not be registered: the POS was never touched.
  notStarted,

  /// The POS (or the local service) could not be reached: nothing was
  /// charged.
  unreachable,

  /// The sale may have reached the POS but its answer was lost: the
  /// customer may have been charged.
  unknown,
}

/// The card payment of one order on a POS: registers it, waits while the
/// customer pays on the POS and shows how it ended. Shared by V2 and the
/// payment sheet.
///
/// While the POS is charging there is no going back: the POS can't be
/// cancelled from the app.
class CardCheckout extends StatefulWidget {
  const CardCheckout({
    super.key,
    required this.payments,
    required this.terminal,
    required this.orderId,
    required this.amount,
    this.description = '',
    this.terminalId,
    this.onApproved,
    this.onError,
    this.onBusyChanged,
    this.onBack,
  });

  final PaymentSdk payments;
  final CardTerminal terminal;
  final String orderId;
  final num amount;
  final String description;

  /// The device's code in Nexus Payments, recorded with the payment.
  final String? terminalId;

  /// Called once the POS approved the payment.
  final ValueChanged<CardPayment>? onApproved;
  final ValueChanged<PaymentSdkException>? onError;

  /// True while the payment is being registered or charged: leaving then
  /// is not allowed.
  final ValueChanged<bool>? onBusyChanged;

  /// "Volver" / "Otro método" once nothing is in progress.
  final VoidCallback? onBack;

  @override
  State<CardCheckout> createState() => _CardCheckoutState();
}

class _CardCheckoutState extends State<CardCheckout> {
  _CardPhase _phase = _CardPhase.registering;
  CardPayment? _payment;
  PaymentSdkException? _error;

  @override
  void initState() {
    super.initState();
    _charge();
  }

  bool _isBusy(_CardPhase phase) =>
      phase == _CardPhase.registering || phase == _CardPhase.charging;

  void _setPhase(_CardPhase phase) {
    if (!mounted) return;
    final wasBusy = _isBusy(_phase);
    setState(() => _phase = phase);
    if (wasBusy != _isBusy(phase)) widget.onBusyChanged?.call(_isBusy(phase));
  }

  Future<void> _charge() async {
    _error = null;
    // The first time the owner already knows it is busy: it just chose card.
    if (_phase != _CardPhase.registering) _setPhase(_CardPhase.registering);
    try {
      final payment = await widget.payments.chargeCard(
        terminal: widget.terminal,
        orderId: widget.orderId,
        amount: widget.amount,
        description: widget.description,
        terminalId: widget.terminalId,
        onPosStarted: () => _setPhase(_CardPhase.charging),
      );
      if (!mounted) return;
      _payment = payment;
      if (payment.isApproved) {
        _setPhase(_CardPhase.approved);
        widget.onApproved?.call(payment);
      } else {
        _setPhase(_CardPhase.rejected);
      }
    } on CardTerminalException catch (e) {
      _error = e;
      _setPhase(e.outcomeUnknown ? _CardPhase.unknown : _CardPhase.unreachable);
      widget.onError?.call(e);
    } on PaymentSdkException catch (e) {
      _error = e;
      _setPhase(_CardPhase.notStarted);
      widget.onError?.call(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final Widget child = switch (_phase) {
      _CardPhase.registering => const PulseLoader(
          icon: Icons.credit_card,
          title: 'Preparando el cobro…',
        ),
      _CardPhase.charging => const PulseLoader(
          icon: Icons.contactless_outlined,
          title: 'Sigue las instrucciones del POS',
          message: 'Acerca, inserta o desliza tu tarjeta en el POS.',
        ),
      _CardPhase.approved => _approved(),
      _CardPhase.rejected => _withActions(
          ResultBadge(
            icon: Icons.credit_card_off_outlined,
            color: colors.error,
            title: 'Tarjeta rechazada',
            message: _payment?.message ?? 'El POS no aprobó el pago.',
          ),
          retry: true,
          backLabel: 'Otro método',
        ),
      _CardPhase.notStarted => _withActions(
          ResultBadge(
            icon: Icons.wifi_off_rounded,
            color: colors.error,
            title: 'No pudimos iniciar el cobro',
            message: _error?.message,
          ),
          retry: true,
        ),
      _CardPhase.unreachable => _withActions(
          ResultBadge(
            icon: Icons.portable_wifi_off_outlined,
            color: colors.error,
            title: 'No pudimos comunicarnos con el POS',
            message: 'No se realizó ningún cobro. Revisa que el POS esté '
                'encendido e intenta de nuevo.',
          ),
          retry: true,
        ),
      _CardPhase.unknown => _withActions(
          ResultBadge(
            icon: Icons.help_outline_rounded,
            color: Colors.orange.shade700,
            title: 'No pudimos confirmar el cobro',
            message: 'El cobro pudo haberse realizado. Revisa el POS o '
                'consulta con el personal antes de volver a pagar.',
          ),
          // Charging again could charge the customer twice.
          retry: false,
          backLabel: 'Entendido',
        ),
    };
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      child: KeyedSubtree(key: ValueKey(_phase), child: child),
    );
  }

  Widget _approved() {
    final payment = _payment;
    final details = [
      payment?.maskedCard,
      if (payment?.authCode case final auth?) 'Autorización $auth',
    ].whereType<String>().join(' · ');
    return ResultBadge(
      icon: Icons.check_rounded,
      color: Colors.green.shade600,
      title: '¡Pago aprobado!',
      message: details.isEmpty ? 'Gracias por tu compra' : details,
    );
  }

  Widget _withActions(
    Widget badge, {
    required bool retry,
    String backLabel = 'Volver',
  }) {
    final onBack = widget.onBack;
    final height =
        Responsive.pick<double>(context, compact: 44, regular: 48, large: 56);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        badge,
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            if (onBack != null)
              SizedBox(
                height: height,
                child: TextButton.icon(
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back),
                  label: Text(backLabel),
                ),
              ),
            if (retry)
              SizedBox(
                height: height,
                child: OutlinedButton.icon(
                  onPressed: _charge,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reintentar'),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
