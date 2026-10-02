import 'package:flutter/material.dart';

/// The payment card: "Total a pagar", the amount, the description and
/// [child] below.
class PaymentCard extends StatelessWidget {
  const PaymentCard({
    super.key,
    required this.amount,
    required this.child,
    this.currency,
    this.description = '',
  });

  final num amount;
  final String? currency;
  final String description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Card(
        elevation: 0,
        color: theme.colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Total a pagar',
                style: theme.textTheme.titleSmall?.copyWith(color: muted),
              ),
              const SizedBox(height: 4),
              Text(
                [currency, amount.toStringAsFixed(2)]
                    .whereType<String>()
                    .join(' '),
                style: theme.textTheme.displaySmall
                    ?.copyWith(fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
              if (description.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  description,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                ),
              ],
              const SizedBox(height: 24),
              child,
            ],
          ),
        ),
      ),
    );
  }
}
