import 'package:flutter/material.dart';

import '../../models/payment_method_info.dart';
import 'animations.dart';

/// What to tell the payer before continuing with a method.
class MethodInstructions {
  const MethodInstructions({required this.title, required this.message});

  final String title;
  final String message;
}

/// "How will you pay?": [methods] as animated cards laid out for the
/// available width, with an instructions step for the methods that have one.
///
/// Layout: one column when narrow; otherwise pairs side by side, and with an
/// odd count the first method spans the full width.
class MethodList extends StatefulWidget {
  const MethodList({
    super.key,
    required this.methods,
    required this.onSelected,
    this.instructionsFor,
    this.title,
    this.confirmLabel = 'Confirmar',
    this.backLabel = 'Volver',
    this.emptyText = 'No hay métodos de pago disponibles',
  });

  final List<PaymentMethodInfo> methods;

  /// Called with the chosen method, after its instructions are confirmed.
  final ValueChanged<PaymentMethodInfo> onSelected;

  /// Instructions shown before selecting a method; null skips the step.
  final MethodInstructions? Function(PaymentMethodInfo method)? instructionsFor;
  final String? title;
  final String confirmLabel;
  final String backLabel;
  final String emptyText;

  @override
  State<MethodList> createState() => _MethodListState();
}

class _MethodListState extends State<MethodList> {
  static const _minTwoColumnWidth = 420.0;
  static const _gap = 16.0;

  String? _highlightedId;

  Future<void> _choose(PaymentMethodInfo method) async {
    final instructions = widget.instructionsFor?.call(method);
    if (instructions == null) return widget.onSelected(method);

    setState(() => _highlightedId = method.code);
    final confirmed = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: widget.backLabel,
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (context, _, __) => _InstructionsDialog(
        method: method,
        instructions: instructions,
        confirmLabel: widget.confirmLabel,
        backLabel: widget.backLabel,
      ),
      transitionBuilder: (context, animation, _, child) {
        final curved =
            CurvedAnimation(parent: animation, curve: Curves.easeOutBack);
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween(begin: 0.9, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    );
    if (!mounted) return;
    setState(() => _highlightedId = null);
    if (confirmed ?? false) widget.onSelected(method);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = widget.title;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (title != null) ...[
          FadeSlideIn(
            child: Text(
              title,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
        if (widget.methods.isEmpty)
          Text(widget.emptyText, textAlign: TextAlign.center)
        else
          LayoutBuilder(builder: (context, constraints) {
            final twoColumns = constraints.maxWidth >= _minTwoColumnWidth;
            return Column(children: _rows(twoColumns));
          }),
      ],
    );
  }

  List<Widget> _rows(bool twoColumns) {
    final methods = widget.methods;
    final rows = <Widget>[];
    var index = 0;

    Widget card(PaymentMethodInfo method, {required bool wide}) => FadeSlideIn(
          delay: Duration(milliseconds: 70 * methods.indexOf(method)),
          child: _MethodCard(
            method: method,
            wide: wide,
            highlighted: method.code == _highlightedId,
            onTap: () => _choose(method),
          ),
        );

    if (!twoColumns || methods.length.isOdd) {
      rows.add(card(methods.first, wide: true));
      index = 1;
    }
    for (; index < methods.length; index += twoColumns ? 2 : 1) {
      rows.add(
        twoColumns && index + 1 < methods.length
            ? Row(
                children: [
                  Expanded(child: card(methods[index], wide: false)),
                  const SizedBox(width: _gap),
                  Expanded(child: card(methods[index + 1], wide: false)),
                ],
              )
            : card(methods[index], wide: !twoColumns),
      );
    }
    return [
      for (var i = 0; i < rows.length; i++) ...[
        if (i > 0) const SizedBox(height: _gap),
        rows[i],
      ],
    ];
  }
}

class _MethodCard extends StatefulWidget {
  const _MethodCard({
    required this.method,
    required this.wide,
    required this.highlighted,
    required this.onTap,
  });

  final PaymentMethodInfo method;
  final bool wide;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  State<_MethodCard> createState() => _MethodCardState();
}

class _MethodCardState extends State<_MethodCard> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final method = widget.method;
    final active = widget.highlighted || _hovered;

    final icon = SizedBox.square(
      dimension: widget.wide ? 88 : 72,
      child: FittedBox(child: _MethodIcon(method: method)),
    );
    final label = Text(
      method.name,
      textAlign: TextAlign.center,
      style: (widget.wide
              ? theme.textTheme.headlineSmall
              : theme.textTheme.titleMedium)
          ?.copyWith(fontWeight: FontWeight.w700),
    );

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1,
          duration: const Duration(milliseconds: 120),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            constraints: BoxConstraints(minHeight: widget.wide ? 150 : 180),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: active ? colors.primary : colors.outlineVariant,
                width: active ? 2 : 1,
              ),
              boxShadow: [
                if (active)
                  BoxShadow(
                    color: colors.primary.withAlpha(40),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
              ],
            ),
            child: widget.wide
                ? Row(
                    children: [
                      icon,
                      const SizedBox(width: 20),
                      Expanded(child: label),
                    ],
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [icon, const SizedBox(height: 16), label],
                  ),
          ),
        ),
      ),
    );
  }
}

class _MethodIcon extends StatelessWidget {
  const _MethodIcon({required this.method});

  final PaymentMethodInfo method;

  @override
  Widget build(BuildContext context) {
    final fallback = Icon(
      method.isQr ? Icons.qr_code_2 : Icons.payments_outlined,
      color: Theme.of(context).colorScheme.primary,
    );
    final url = method.iconUrl;
    if (url == null || url.isEmpty) return fallback;
    return Image.network(url, errorBuilder: (_, __, ___) => fallback);
  }
}

class _InstructionsDialog extends StatelessWidget {
  const _InstructionsDialog({
    required this.method,
    required this.instructions,
    required this.confirmLabel,
    required this.backLabel,
  });

  final PaymentMethodInfo method;
  final MethodInstructions instructions;
  final String confirmLabel;
  final String backLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Material(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox.square(
                    dimension: 96,
                    child: FittedBox(child: _MethodIcon(method: method)),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    instructions.title,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    instructions.message,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 52,
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: Text(backLabel),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SizedBox(
                          height: 52,
                          child: FilledButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            child: Text(confirmLabel),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
