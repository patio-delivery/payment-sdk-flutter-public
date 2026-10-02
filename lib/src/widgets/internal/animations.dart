import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Icon with ripples pulsing out of it, for "working on it" moments.
class PulseLoader extends StatefulWidget {
  const PulseLoader({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.color,
    this.size = 150,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Color? color;
  final double size;

  @override
  State<PulseLoader> createState() => _PulseLoaderState();
}

class _PulseLoaderState extends State<PulseLoader>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = widget.color ?? theme.colorScheme.primary;
    final core = widget.size * 0.42;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox.square(
          dimension: widget.size,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final t = _controller.value;
              final breath = 1 + 0.06 * math.sin(t * 2 * math.pi);
              return Stack(
                alignment: Alignment.center,
                children: [
                  for (var i = 0; i < 3; i++) _ripple((t + i / 3) % 1, color),
                  Transform.scale(
                    scale: breath,
                    child: Container(
                      width: core,
                      height: core,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: color.withAlpha(90),
                            blurRadius: 18,
                          ),
                        ],
                      ),
                      child: Icon(
                        widget.icon,
                        color: theme.colorScheme.onPrimary,
                        size: core * 0.5,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        Text(
          widget.title,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge,
        ),
        if (widget.message case final message?) ...[
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }

  Widget _ripple(double t, Color color) {
    final size = widget.size * (0.42 + 0.58 * t);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withAlpha((70 * (1 - t)).round()),
      ),
    );
  }
}

/// Outcome icon that pops in, with a title and message that fade in below.
class ResultBadge extends StatelessWidget {
  const ResultBadge({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    this.message,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 700),
          curve: Curves.elasticOut,
          builder: (context, scale, child) =>
              Transform.scale(scale: scale, child: child),
          child: Container(
            width: 112,
            height: 112,
            decoration: BoxDecoration(
              color: color.withAlpha(30),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 72),
          ),
        ),
        const SizedBox(height: 16),
        FadeSlideIn(
          delay: const Duration(milliseconds: 150),
          child: Column(
            children: [
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall,
              ),
              if (message case final message?) ...[
                const SizedBox(height: 6),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Fades and slides [child] up into place once, after [delay].
class FadeSlideIn extends StatelessWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
  });

  final Widget child;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    const duration = Duration(milliseconds: 450);
    final total = duration + delay;
    final start = delay.inMicroseconds / total.inMicroseconds;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: total,
      curve: Interval(start, 1, curve: Curves.easeOutCubic),
      builder: (context, t, child) => Opacity(
        opacity: t,
        child:
            Transform.translate(offset: Offset(0, 16 * (1 - t)), child: child),
      ),
      child: child,
    );
  }
}
