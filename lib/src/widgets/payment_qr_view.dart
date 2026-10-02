import 'package:flutter/material.dart';

import '../models/qr_payment.dart';

/// Shows the QR image of a [QrPayment], or [unavailableText] when there is
/// none.
class PaymentQrView extends StatelessWidget {
  const PaymentQrView({
    super.key,
    required this.payment,
    this.size = 240,
    this.unavailableText = 'QR no disponible',
  });

  final QrPayment payment;
  final double size;
  final String unavailableText;

  @override
  Widget build(BuildContext context) {
    final bytes = payment.qrImageBytes;
    final placeholder = _Placeholder(text: unavailableText);
    return SizedBox.square(
      dimension: size,
      child: bytes == null
          ? placeholder
          : Image.memory(
              bytes,
              fit: BoxFit.contain,
              gaplessPlayback: true,
              filterQuality: FilterQuality.none,
              semanticLabel: 'Código QR de pago',
              errorBuilder: (_, __, ___) => placeholder,
            ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall,
        ),
      ),
    );
  }
}
