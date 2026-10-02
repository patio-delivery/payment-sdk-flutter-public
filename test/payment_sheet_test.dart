import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payment_sdk_flutter/payment_sdk_flutter.dart';

import 'helpers/fake_adapter.dart';

void main() {
  late FakeAdapter adapter;
  late PaymentSdk payments;
  late List<String> statuses;
  PaymentSheetResult? result;

  setUp(() {
    result = null;
    statuses = ['PENDING'];
    adapter = FakeAdapter((request) {
      final path = request.uri.path;
      if (path == '/api/payment-methods') {
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
      final status = statuses.length > 1 ? statuses.removeAt(0) : statuses[0];
      return FakeResponse.ok({'order': 'ORD-1', 'status': status});
    });
    payments = PaymentSdk(
      config: PaymentSdkConfig(baseUrl: 'http://backend.test/api', apiKey: 'k'),
      httpClientAdapter: adapter,
    );
  });

  int posts() => adapter.requests.where((r) => r.method == 'POST').length;

  int statusChecks() =>
      adapter.requests.where((r) => r.uri.path.contains('/qr/status/')).length;

  /// Lets the fake HTTP round trip complete (part of dio runs outside the
  /// fake clock) and the widgets rebuild.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 1));
    }
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> open(
    WidgetTester tester, {
    double width = 400,
    Duration qrTimeout = const Duration(minutes: 5),
  }) async {
    tester.view.physicalSize = Size(width, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () async {
                result = await PaymentSheet.show(
                  context,
                  payments: payments,
                  amount: 150,
                  orderId: 'ORD-1',
                  currency: 'Bs',
                  qrTimeout: qrTimeout,
                  pollInterval: const Duration(seconds: 1),
                );
              },
              child: const Text('Pagar'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Pagar'));
    await settle(tester);
  }

  Future<void> chooseQr(WidgetTester tester) async {
    await tester.tap(find.text('Pago QR'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Confirmar'));
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);
  }

  Future<void> close(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Cerrar'));
    await settle(tester);
  }

  testWidgets('slides up from the bottom on narrow screens', (tester) async {
    await open(tester);

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('Bs 150.00'), findsOneWidget);
    expect(find.text('¿Con qué vas a pagar?'), findsOneWidget);
    expect(find.text('Pago QR'), findsOneWidget);
    await close(tester);
  });

  testWidgets('opens as a dialog on wide screens', (tester) async {
    await open(tester, width: 1000);

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    await close(tester);
  });

  testWidgets('a confirmed payment closes the sheet as paid', (tester) async {
    await open(tester);
    await chooseQr(tester);
    expect(find.byType(PaymentQrView), findsOneWidget);
    expect(find.text('BOB 150.00'), findsOneWidget);

    statuses = ['PAID'];
    await tester.pump(const Duration(seconds: 1));
    await settle(tester);
    expect(find.text('¡Pago confirmado!'), findsOneWidget);
    expect(result, isNull);

    await tester.pump(const Duration(seconds: 2));
    await settle(tester);
    expect(result?.status, PaymentSheetStatus.paid);
    expect(result?.payment?.paymentId, 'QR-1');
    expect(result?.method?.code, 'QR');
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('closing before choosing a method cancels', (tester) async {
    await open(tester);
    await close(tester);

    expect(result?.status, PaymentSheetStatus.cancelled);
    expect(posts(), 0);
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('closing an unpaid QR checks it, then cancels', (tester) async {
    await open(tester);
    await chooseQr(tester);
    final checksBefore = statusChecks();

    await close(tester);
    expect(statusChecks(), checksBefore + 1);
    expect(result?.status, PaymentSheetStatus.cancelled);
  });

  testWidgets('closing a QR that was paid reports paid, not cancelled',
      (tester) async {
    await open(tester);
    await chooseQr(tester);

    statuses = ['PAID'];
    await close(tester);
    expect(find.text('¡Pago confirmado!'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await settle(tester);
    expect(result?.status, PaymentSheetStatus.paid);
  });

  testWidgets('an expired QR closes the sheet as expired', (tester) async {
    await open(tester, qrTimeout: const Duration(seconds: 10));
    await chooseQr(tester);

    await tester.pump(const Duration(seconds: 10));
    await settle(tester);
    expect(find.text('Tiempo agotado'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    await settle(tester);
    expect(result?.status, PaymentSheetStatus.expired);
  });
}
