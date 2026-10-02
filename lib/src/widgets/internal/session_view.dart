import 'package:flutter/material.dart';

import '../../session/payment_session.dart';
import 'animations.dart';
import 'qr_panel.dart';
import 'responsive.dart';

/// Renders a [PaymentSession]: an animated view per phase plus its buttons.
/// Shared by every SDK payment view.
class SessionView extends StatelessWidget {
  const SessionView({
    super.key,
    required this.session,
    required this.onNewQr,
    this.onCancel,
    this.qrSize = 240,
  });

  final PaymentSession session;

  /// "Generar nuevo QR" after a rejected or expired QR.
  final VoidCallback onNewQr;

  /// Shows "Cancelar" when set. The caller verifies before leaving.
  final VoidCallback? onCancel;
  final double qrSize;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final theme = Theme.of(context);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween(begin: 0.96, end: 1.0).animate(animation),
                  child: child,
                ),
              ),
              child: KeyedSubtree(
                key: ValueKey(session.phase),
                child: _content(theme),
              ),
            ),
            ..._actions(context),
          ],
        );
      },
    );
  }

  Widget _content(ThemeData theme) {
    final error = theme.colorScheme.error;
    return switch (session.phase) {
      PaymentPhase.idle => const SizedBox.shrink(),
      PaymentPhase.creating => const PulseLoader(
          icon: Icons.qr_code_2,
          title: 'Generando tu código QR…',
        ),
      PaymentPhase.waiting => QrPanel(session: session, qrSize: qrSize),
      PaymentPhase.confirming => const PulseLoader(
          icon: Icons.account_balance_wallet_outlined,
          title: 'Verificando tu pago…',
          message: 'Esto puede tardar unos segundos',
        ),
      PaymentPhase.paid => ResultBadge(
          icon: Icons.check_rounded,
          color: Colors.green.shade600,
          title: '¡Pago confirmado!',
          message: 'Gracias por tu compra',
        ),
      PaymentPhase.failed => ResultBadge(
          icon: Icons.close_rounded,
          color: error,
          title: 'Pago rechazado',
          message: 'Intenta nuevamente con un nuevo QR.',
        ),
      PaymentPhase.expired => ResultBadge(
          icon: Icons.timer_off_outlined,
          color: error,
          title: 'Tiempo agotado',
          message: session.onTimeout != null
              ? 'El QR venció sin recibir el pago. Volviendo…'
              : 'El QR venció sin recibir el pago.',
        ),
      PaymentPhase.error => ResultBadge(
          icon: Icons.wifi_off_rounded,
          color: error,
          title: 'No pudimos generar el QR',
          message: session.error?.message,
        ),
    };
  }

  List<Widget> _actions(BuildContext context) {
    final cancel = onCancel == null
        ? null
        : TextButton(onPressed: onCancel, child: const Text('Cancelar'));

    final (Widget? primary, bool withCancel) = switch (session.phase) {
      PaymentPhase.idle => (
          FilledButton.icon(
            onPressed: session.start,
            icon: const Icon(Icons.qr_code),
            label: const Text('Pagar con QR'),
          ),
          true,
        ),
      PaymentPhase.waiting => (
          FilledButton.icon(
            onPressed: session.confirmPayment,
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Ya pagué'),
          ),
          true,
        ),
      PaymentPhase.failed => (
          FilledButton.icon(
            onPressed: onNewQr,
            icon: const Icon(Icons.refresh),
            label: const Text('Generar nuevo QR'),
          ),
          true,
        ),
      PaymentPhase.expired when session.onTimeout == null => (
          FilledButton.icon(
            onPressed: onNewQr,
            icon: const Icon(Icons.refresh),
            label: const Text('Generar nuevo QR'),
          ),
          true,
        ),
      PaymentPhase.error => (
          OutlinedButton.icon(
            onPressed: session.start,
            icon: const Icon(Icons.refresh),
            label: const Text('Reintentar'),
          ),
          true,
        ),
      _ => (null, false),
    };

    if (primary == null && !(withCancel && cancel != null)) return const [];
    final height =
        Responsive.pick<double>(context, compact: 48, regular: 52, large: 60);
    return [
      SizedBox(height: height * 0.45),
      if (primary != null)
        SizedBox(width: double.infinity, height: height, child: primary),
      if (withCancel && cancel != null) cancel,
    ];
  }
}
