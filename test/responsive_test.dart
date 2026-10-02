import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payment_sdk_flutter/payment_sdk_flutter.dart';

import 'helpers/fake_adapter.dart';

/// Every version on the screens the SDK runs on. A layout overflow fails the
/// test on its own; the checks below make sure the QR fits on screen.
void main() {
  const screens = {
    'small phone': Size(320, 568),
    'phone': Size(390, 844),
    'phone landscape': Size(844, 390),
    'tablet': Size(768, 1024),
    'kiosk portrait': Size(1080, 1920),
    'desktop': Size(1920, 1080),
  };

  late PaymentSdk payments;

  setUp(() {
    final adapter = FakeAdapter((request) {
      if (request.uri.path == '/api/payment-methods') {
        return const FakeResponse(200, {
          'ok': true,
          'message': 'OK',
          'data': [
            {'code': 'QR', 'name': 'Pago QR', 'currency': 'BOB'},
          ],
        });
      }
      if (request.method == 'POST') {
        return FakeResponse.ok({
          'id_payment': 'QR-1',
          'imageQR': tinyPngBase64,
          'status': 'PENDING',
        });
      }
      return FakeResponse.ok({'order': 'ORD-1', 'status': 'PENDING'});
    });
    payments = PaymentSdk(
      config: PaymentSdkConfig(baseUrl: 'http://backend.test/api', apiKey: 'k'),
      httpClientAdapter: adapter,
    );
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 1));
    }
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> show(
    WidgetTester tester,
    Size screen,
    PaymentVersion version, {
    double textScale = 1,
  }) async {
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: PaymentFlow(
              version: version,
              payments: payments,
              amount: 1234.5,
              orderId: 'ORD-1',
              currency: 'Bs',
              description: 'Pedido de prueba con una descripción larga',
              qrSize: 400,
            ),
          ),
        ),
      ),
    ));
    await settle(tester);
  }

  Future<void> chooseQr(WidgetTester tester) async {
    await tester.tap(find.text('Pago QR'));
    await tester.pump(const Duration(milliseconds: 400));
    // With large text the dialog scrolls, as a user would.
    await tester.ensureVisible(find.text('Confirmar'));
    await tester.pump();
    await tester.tap(find.text('Confirmar'));
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);
  }

  void expectQrFits(WidgetTester tester, Size screen) {
    final qr = tester.getRect(find.byType(PaymentQrView));
    expect(qr.left, greaterThanOrEqualTo(0));
    expect(qr.right, lessThanOrEqualTo(screen.width));
    expect(qr.height, lessThanOrEqualTo(screen.height * 0.45 + 0.5));
    expect(qr.height, greaterThanOrEqualTo(120));
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  }

  for (final MapEntry(key: name, value: screen) in screens.entries) {
    group(name, () {
      testWidgets('V1 fits the QR', (tester) async {
        await show(tester, screen, PaymentVersion.v1);
        expectQrFits(tester, screen);
        expect(find.text('Ya pagué'), findsOneWidget);
        await unmount(tester);
      });

      testWidgets('V2 fits the methods and the QR', (tester) async {
        await show(tester, screen, PaymentVersion.v2);
        expect(find.text('Pago QR'), findsOneWidget);
        await chooseQr(tester);
        expectQrFits(tester, screen);
        await unmount(tester);
      });

      testWidgets('V3 fits the button, the window and the QR', (tester) async {
        await show(tester, screen, PaymentVersion.v3);
        final button = tester.getRect(find.byType(FilledButton));
        expect(button.right, lessThanOrEqualTo(screen.width));

        await tester.tap(find.byType(FilledButton));
        await settle(tester);
        await chooseQr(tester);
        expectQrFits(tester, screen);
        await unmount(tester);
      });
    });
  }

  testWidgets('large text on a small phone does not overflow', (tester) async {
    const screen = Size(320, 568);
    await show(tester, screen, PaymentVersion.v2, textScale: 1.4);
    await chooseQr(tester);
    expectQrFits(tester, screen);
    await unmount(tester);
  });
}
