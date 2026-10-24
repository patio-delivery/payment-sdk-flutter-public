import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payment_sdk_flutter/payment_sdk_flutter.dart';

import 'helpers/fake_adapter.dart';

const _cashBody = {
  'code': 'EF-7K3M9QX2',
  'order': 'ORD-1',
  'glosa': 'Pedido 1',
  'amount': 150,
  'currency': 'BOB',
  'status': 'PENDING',
  'createdAt': '2026-10-24T10:00:00.000Z',
};

void main() {
  group('models', () {
    test('CashPayment reads the backend payment', () {
      final cash = CashPayment.fromJson({..._cashBody, 'amount': '150.50'});

      expect(cash.code, 'EF-7K3M9QX2');
      expect(cash.orderId, 'ORD-1');
      expect(cash.amount, 150.5);
      expect(cash.currency, 'BOB');
      expect(cash.description, 'Pedido 1');
      expect(cash.status, PaymentStatus.pending);
      expect(cash.isPending, isTrue);
      expect(cash.createdAt, DateTime.utc(2026, 10, 24, 10));
    });

    test('CANCELLED is a final status', () {
      expect(PaymentStatus.fromJson('cancelled'), PaymentStatus.cancelled);
      expect(PaymentStatus.cancelled.isFinal, isTrue);
    });

    test('EFECTIVO is a supported method', () {
      const cash = PaymentMethodInfo(code: 'efectivo', name: 'Efectivo');
      expect(cash.isCash, isTrue);
      expect(cash.isQr, isFalse);
      expect(cash.isSupported, isTrue);
    });
  });

  group('PaymentSdk', () {
    late FakeAdapter adapter;
    late PaymentSdk payments;

    setUp(() {
      adapter = FakeAdapter((request) {
        if (request.uri.path == '/api/cash/status/ORD-404') {
          return FakeResponse.error(404, 'Pago no encontrado');
        }
        if (request.uri.path.startsWith('/api/cash/status/')) {
          return FakeResponse.ok({'order': 'ORD-1', 'status': 'PAID'});
        }
        return FakeResponse.ok(_cashBody, statusCode: 201);
      });
      payments = PaymentSdk(
        config:
            PaymentSdkConfig(baseUrl: 'http://backend.test/api', apiKey: 'k'),
        httpClientAdapter: adapter,
      );
    });

    test('createCashPayment posts the order and returns its code', () async {
      final cash = await payments.createCashPayment(
        orderId: ' ORD-1 ',
        amount: 150,
        description: 'Pedido 1',
      );

      final request = adapter.requests.single;
      expect(request.method, 'POST');
      expect(request.uri.path, '/api/cash');
      expect(
          request.data, {'order': 'ORD-1', 'amount': 150, 'glosa': 'Pedido 1'});
      expect(cash.code, 'EF-7K3M9QX2');
    });

    test('createCashPayment leaves out an empty description', () async {
      await payments.createCashPayment(orderId: 'ORD-1', amount: 150);

      expect(adapter.requests.single.data, {'order': 'ORD-1', 'amount': 150});
    });

    test('createCashPayment validates before calling the backend', () async {
      await expectLater(
        payments.createCashPayment(orderId: ' ', amount: 0),
        throwsA(isA<ValidationException>()),
      );
      expect(adapter.requests, isEmpty);
    });

    test('getCashPaymentStatus reads the cash status by order', () async {
      expect(await payments.getCashPaymentStatus('ORD-1'), PaymentStatus.paid);
      expect(adapter.requests.single.uri.path, '/api/cash/status/ORD-1');
    });

    test('getCashPaymentStatus throws for an unknown order', () async {
      await expectLater(
        payments.getCashPaymentStatus('ORD-404'),
        throwsA(isA<PaymentNotFoundException>()),
      );
    });
  });

  group('widgets', () {
    late FakeAdapter adapter;
    late PaymentSdk payments;
    late List<Map<String, dynamic>> methods;
    late FakeResponse cashResponse;

    setUp(() {
      methods = [
        {'code': 'QR', 'name': 'Pago QR', 'currency': 'BOB', 'position': 0},
        {
          'code': 'EFECTIVO',
          'name': 'Pago en efectivo',
          'currency': 'BOB',
          'position': 1,
        },
      ];
      cashResponse = FakeResponse.ok(_cashBody, statusCode: 201);
      adapter = FakeAdapter((request) {
        final path = request.uri.path;
        if (path == '/api/payment-methods') {
          return FakeResponse(
              200, {'ok': true, 'message': 'OK', 'data': methods});
        }
        if (path == '/api/cash') return cashResponse;
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
        config:
            PaymentSdkConfig(baseUrl: 'http://backend.test/api', apiKey: 'k'),
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

    Future<void> pumpApp(WidgetTester tester, Widget child) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ));
      await settle(tester);
    }

    Future<void> chooseCash(WidgetTester tester) async {
      await tester.tap(find.text('Pago en efectivo'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Pagarás en caja'), findsOneWidget);
      await tester.tap(find.text('Confirmar'));
      await tester.pump(const Duration(milliseconds: 400));
      await settle(tester);
    }

    Iterable<String> cashPosts() => adapter.requests
        .where((r) => r.uri.path == '/api/cash')
        .map((r) => (r.data as Map)['order'] as String);

    group('PaymentMethods (V2)', () {
      PaymentMethods view({
        ValueChanged<CashPayment>? onCashPayment,
        String? orderId = 'ORD-1',
        Future<String> Function(PaymentMethodInfo)? createOrderId,
      }) =>
          PaymentMethods(
            payments: payments,
            amount: 150,
            orderId: orderId,
            createOrderId: createOrderId,
            pollInterval: const Duration(minutes: 1),
            onCashPayment: onCashPayment,
          );

      testWidgets('hides cash when the app does not handle it', (tester) async {
        await pumpApp(tester, view());

        // Only QR is left, so the single method goes straight to its QR.
        expect(find.text('Pago en efectivo'), findsNothing);
        expect(find.byType(PaymentQrView), findsOneWidget);
        expect(cashPosts(), isEmpty);
        await tester.pumpWidget(const SizedBox());
      });

      testWidgets('choosing cash shows its code and reports it',
          (tester) async {
        CashPayment? reported;
        await pumpApp(tester, view(onCashPayment: (cash) => reported = cash));
        await chooseCash(tester);

        expect(cashPosts(), ['ORD-1']);
        expect(find.text('EF-7K3M9QX2'), findsOneWidget);
        expect(find.text('BOB 150.00'), findsOneWidget);
        expect(reported?.code, 'EF-7K3M9QX2');
        // V2 has no button: the app leaves when it wants, as after onSuccess.
        expect(find.text('Listo'), findsNothing);
      });

      testWidgets('the code fits a small phone with large text',
          (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MaterialApp(
          home: MediaQuery.withClampedTextScaling(
            minScaleFactor: 1.6,
            maxScaleFactor: 1.6,
            child: Scaffold(
              body: SingleChildScrollView(
                child: view(onCashPayment: (_) {}),
              ),
            ),
          ),
        ));
        await settle(tester);
        await tester.scrollUntilVisible(find.text('Pago en efectivo'), 100);
        await chooseCash(tester);

        expect(find.text('EF-7K3M9QX2'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('createOrderId is told the customer chose cash',
          (tester) async {
        PaymentMethodInfo? asked;
        await pumpApp(
          tester,
          view(
            orderId: null,
            onCashPayment: (_) {},
            createOrderId: (method) async {
              asked = method;
              return 'ORD-CASH';
            },
          ),
        );
        await chooseCash(tester);

        expect(asked?.isCash, isTrue);
        expect(cashPosts(), ['ORD-CASH']);
      });

      testWidgets('a single cash method is not chosen on its own',
          (tester) async {
        methods = [methods.last];
        await pumpApp(tester, view(onCashPayment: (_) {}));

        expect(find.text('Pago en efectivo'), findsOneWidget);
        expect(cashPosts(), isEmpty);
      });

      testWidgets('a failed code can be retried for the same order',
          (tester) async {
        cashResponse = FakeResponse.error(503, 'Sin conexión');
        await pumpApp(tester, view(onCashPayment: (_) {}));
        await chooseCash(tester);
        expect(find.text('No pudimos generar tu código'), findsOneWidget);

        cashResponse = FakeResponse.ok(_cashBody, statusCode: 201);
        await tester.tap(find.text('Reintentar'));
        await settle(tester);

        expect(cashPosts(), ['ORD-1', 'ORD-1']);
        expect(find.text('EF-7K3M9QX2'), findsOneWidget);
      });

      testWidgets('"Volver" after a failed code shows the methods again',
          (tester) async {
        cashResponse = FakeResponse.error(503, 'Sin conexión');
        await pumpApp(tester, view(onCashPayment: (_) {}));
        await chooseCash(tester);

        await tester.tap(find.text('Volver'));
        await settle(tester);
        expect(find.text('Pago QR'), findsOneWidget);
        expect(find.text('Pago en efectivo'), findsOneWidget);
      });
    });

    group('PaymentSheet (V3)', () {
      PaymentSheetResult? result;

      Future<void> open(WidgetTester tester, {bool acceptCash = true}) async {
        result = null;
        tester.view.physicalSize = const Size(400, 1400);
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
                      acceptCash: acceptCash,
                      pollInterval: const Duration(minutes: 1),
                    );
                  },
                  child: const Text('Abrir'),
                ),
              ),
            ),
          ),
        ));
        await tester.tap(find.text('Abrir'));
        await settle(tester);
      }

      testWidgets('without acceptCash cash is not offered', (tester) async {
        await open(tester, acceptCash: false);

        expect(find.text('Pago en efectivo'), findsNothing);
        await tester.tap(find.byTooltip('Cerrar'));
        await settle(tester);
      });

      testWidgets('"Listo" closes as cash pending with the code',
          (tester) async {
        await open(tester);
        await chooseCash(tester);
        expect(find.text('EF-7K3M9QX2'), findsOneWidget);

        await tester.tap(find.text('Listo'));
        await settle(tester);

        expect(result?.status, PaymentSheetStatus.cashPending);
        expect(result?.isCashPending, isTrue);
        expect(result?.cashPayment?.code, 'EF-7K3M9QX2');
        expect(result?.method?.isCash, isTrue);
      });

      testWidgets('closing with the code on screen is cash pending, not cancel',
          (tester) async {
        await open(tester);
        await chooseCash(tester);

        await tester.tap(find.byTooltip('Cerrar'));
        await settle(tester);

        expect(result?.status, PaymentSheetStatus.cashPending);
        expect(result?.cashPayment?.code, 'EF-7K3M9QX2');
      });
    });

    group('PaymentFlow', () {
      testWidgets('V3 reports the cash payment through onCashPayment',
          (tester) async {
        CashPayment? reported;
        var cancelled = false;
        await pumpApp(
          tester,
          PaymentFlow(
            version: PaymentVersion.v3,
            payments: payments,
            amount: 150,
            orderId: 'ORD-1',
            pollInterval: const Duration(minutes: 1),
            onCashPayment: (cash) => reported = cash,
            onCancel: () => cancelled = true,
          ),
        );
        await tester.tap(find.text('Pagar 150.00'));
        await settle(tester);
        await chooseCash(tester);
        await tester.tap(find.text('Listo'));
        await settle(tester);

        expect(reported?.code, 'EF-7K3M9QX2');
        expect(cancelled, isFalse);
      });

      testWidgets('V2 offers cash only with onCashPayment', (tester) async {
        await pumpApp(
          tester,
          PaymentFlow(
            version: PaymentVersion.v2,
            payments: payments,
            amount: 150,
            orderId: 'ORD-1',
            onCashPayment: (_) {},
          ),
        );

        expect(find.text('Pago en efectivo'), findsOneWidget);
      });
    });
  });
}
