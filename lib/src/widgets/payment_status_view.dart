import 'package:flutter/material.dart';

import '../models/payment_status.dart';

const defaultPaymentStatusLabels = {
  PaymentStatus.pending: 'Esperando pago',
  PaymentStatus.paid: 'Pago confirmado',
  PaymentStatus.failed: 'Pago rechazado',
  PaymentStatus.expired: 'QR vencido',
  PaymentStatus.unknown: 'Estado desconocido',
};

/// Icon and label for a [PaymentStatus].
class PaymentStatusView extends StatelessWidget {
  const PaymentStatusView({
    super.key,
    required this.status,
    this.labels = defaultPaymentStatusLabels,
  });

  final PaymentStatus status;
  final Map<PaymentStatus, String> labels;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (icon, color) = switch (status) {
      PaymentStatus.pending => (Icons.hourglass_top, colors.primary),
      PaymentStatus.paid => (Icons.check_circle, Colors.green.shade700),
      PaymentStatus.failed => (Icons.cancel, colors.error),
      PaymentStatus.expired => (Icons.timer_off, colors.error),
      PaymentStatus.unknown => (Icons.help_outline, colors.outline),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            labels[status] ?? status.value,
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
