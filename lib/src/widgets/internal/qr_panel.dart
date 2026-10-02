import 'package:flutter/material.dart';

import '../../session/payment_session.dart';
import 'animations.dart';
import '../payment_qr_view.dart';

/// The QR while it can be paid: optional "not received yet" notice, the
/// framed QR, the scan hint and the countdown.
class QrPanel extends StatelessWidget {
  const QrPanel({super.key, required this.session, this.qrSize = 240});

  final PaymentSession session;
  final double qrSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          child: session.showNotPaid
              ? const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: FadeSlideIn(child: _NotPaidNotice()),
                )
              : const SizedBox(width: double.infinity),
        ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: PaymentQrView(payment: session.payment!, size: qrSize),
        ),
        const SizedBox(height: 12),
        Text(
          'Escanea el código con la app de tu banco',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        _Countdown(remaining: session.remaining),
      ],
    );
  }
}

class _Countdown extends StatelessWidget {
  const _Countdown({required this.remaining});

  final Duration remaining;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final urgent = remaining < const Duration(minutes: 1);
    final color = urgent ? theme.colorScheme.error : theme.colorScheme.primary;
    // Round up, like any countdown: 4:59.3 left still reads 05:00.
    final total = (remaining.inMilliseconds / 1000).ceil();
    final minutes = (total ~/ 60).toString().padLeft(2, '0');
    final seconds = (total % 60).toString().padLeft(2, '0');

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: color.withAlpha(24),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withAlpha(90)),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.timer_outlined, color: color, size: 20),
            const SizedBox(width: 8),
            Text('Tiempo restante', style: TextStyle(color: color)),
            const SizedBox(width: 10),
            Text(
              '$minutes:$seconds',
              style: theme.textTheme.titleLarge?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotPaidNotice extends StatelessWidget {
  const _NotPaidNotice();

  @override
  Widget build(BuildContext context) {
    final color = Colors.orange.shade800;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 600),
            curve: Curves.elasticOut,
            builder: (context, scale, child) =>
                Transform.scale(scale: scale, child: child),
            child: Icon(Icons.hourglass_empty_rounded, color: color, size: 28),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Aún no recibimos tu pago',
                  style: TextStyle(color: color, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  'Si ya pagaste, espera unos segundos y vuelve a intentar.',
                  style: TextStyle(color: color),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
