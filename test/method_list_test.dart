import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payment_sdk_flutter/payment_sdk_flutter.dart';
import 'package:payment_sdk_flutter/src/widgets/internal/method_list.dart';

void main() {
  const qr = PaymentMethodInfo(code: 'QR', name: 'QR');
  const card = PaymentMethodInfo(code: 'CARD', name: 'Tarjeta');
  const chip = PaymentMethodInfo(code: 'CHIP', name: 'Chip');

  MethodInstructions? qrOnly(PaymentMethodInfo m) => m.isQr
      ? const MethodInstructions(
          title: 'Prepárate para escanear',
          message: 'Tu QR aparecerá en la siguiente pantalla.',
        )
      : null;

  Future<void> show(
    WidgetTester tester,
    List<PaymentMethodInfo> methods,
    ValueChanged<PaymentMethodInfo> onSelected, {
    double width = 800,
  }) async {
    tester.view.physicalSize = Size(width, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: MethodList(
            methods: methods,
            title: '¿Con qué vas a pagar hoy?',
            instructionsFor: qrOnly,
            onSelected: onSelected,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  double widthOf(WidgetTester tester, String label) => tester
      .getSize(find.ancestor(
        of: find.text(label),
        matching: find.byType(AnimatedContainer),
      ))
      .width;

  testWidgets('odd count: first method full width, the rest in pairs',
      (tester) async {
    await show(tester, const [qr, card, chip], (_) {});

    expect(find.text('¿Con qué vas a pagar hoy?'), findsOneWidget);
    expect(
        widthOf(tester, 'QR'), greaterThan(widthOf(tester, 'Tarjeta') * 1.8));
    expect(widthOf(tester, 'Tarjeta'), widthOf(tester, 'Chip'));
  });

  testWidgets('narrow screens use a single column', (tester) async {
    await show(tester, const [card, chip], (_) {}, width: 360);
    expect(widthOf(tester, 'Tarjeta'), widthOf(tester, 'Chip'));
    expect(
      tester.getTopLeft(find.text('Chip')).dy,
      greaterThan(tester.getTopLeft(find.text('Tarjeta')).dy),
    );
  });

  testWidgets('confirming the instructions selects the method', (tester) async {
    PaymentMethodInfo? selected;
    await show(tester, const [qr], (m) => selected = m);

    await tester.tap(find.text('QR'));
    await tester.pumpAndSettle();
    expect(find.text('Prepárate para escanear'), findsOneWidget);

    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();
    expect(selected?.isQr, isTrue);
  });

  testWidgets('going back from the instructions selects nothing',
      (tester) async {
    PaymentMethodInfo? selected;
    await show(tester, const [qr], (m) => selected = m);

    await tester.tap(find.text('QR'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Volver'));
    await tester.pumpAndSettle();

    expect(selected, isNull);
    expect(find.text('Prepárate para escanear'), findsNothing);
  });

  testWidgets('without instructions a tap selects directly', (tester) async {
    PaymentMethodInfo? selected;
    await show(tester, const [card], (m) => selected = m);

    await tester.tap(find.text('Tarjeta'));
    await tester.pumpAndSettle();
    expect(selected?.code, 'CARD');
  });

  testWidgets('shows the empty text without methods', (tester) async {
    await show(tester, const [], (_) {});
    expect(find.text('No hay métodos de pago disponibles'), findsOneWidget);
  });
}
