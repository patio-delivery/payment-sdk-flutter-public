import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payment_sdk_flutter/payment_sdk_flutter.dart';

import 'helpers/fake_adapter.dart';

void main() {
  group('PaymentVersion.tryParse', () {
    test('reads v1, v2 and v3 in any case and with spaces', () {
      expect(PaymentVersion.tryParse('v1'), PaymentVersion.v1);
      expect(PaymentVersion.tryParse('V2'), PaymentVersion.v2);
      expect(PaymentVersion.tryParse(' v3 '), PaymentVersion.v3);
    });

    test('anything else means the SDK is off', () {
      for (final value in [null, '', 'off', 'v4', 'checkout', '1']) {
        expect(PaymentVersion.tryParse(value), isNull, reason: '$value');
      }
    });

    test('labels are V1, V2 and V3', () {
      expect(PaymentVersion.values.map((v) => v.label), ['V1', 'V2', 'V3']);
    });
  });

  late FakeAdapter adapter;
  late PaymentSdk payments;
  late List<String> statuses;
  late List<String> events;

  setUp(() {
    events = [];
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

  Map<String, dynamic> lastQrBody() => adapter.requests
      .lastWhere((r) => r.method == 'POST')
      .data as Map<String, dynamic>;

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

  Future<void> show(
    WidgetTester tester,
    PaymentVersion version, {
    String? orderId = 'ORD-1',
    Future<String> Function(PaymentMethodInfo method)? createOrderId,
    bool autoOpen = false,
    VoidCallback? onBack,
    bool autoSelectSingleMethod = false,
  }) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: PaymentFlow(
            version: version,
            payments: payments,
            amount: 150,
            orderId: orderId,
            createOrderId: createOrderId,
            currency: 'Bs',
            descriptionFor: (id) => 'Pedido $id',
            autoOpen: autoOpen,
            pollInterval: const Duration(seconds: 1),
            onSuccess: (payment) => events.add('success ${payment.paymentId}'),
            onCancel: () => events.add('cancel'),
            onTimeout: () => events.add('timeout'),
            onBack: onBack,
            autoSelectSingleMethod: autoSelectSingleMethod,
          ),
        ),
      ),
    ));
    await settle(tester);
  }

  /// Unmounts the flow so its timers stop before the test ends.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  }

  group('V1', () {
    testWidgets('shows the QR right away, without a methods list',
        (tester) async {
      await show(tester, PaymentVersion.v1);

      expect(find.byType(PaymentQrView), findsOneWidget);
      expect(find.text('Pago QR'), findsNothing);
      expect(lastQrBody()['order'], 'ORD-1');
      expect(lastQrBody()['glosa'], 'Pedido ORD-1');

      statuses = ['PAID'];
      await tester.pump(const Duration(seconds: 1));
      await settle(tester);
      expect(events, ['success QR-1']);
      await unmount(tester);
    });

    testWidgets('creates the order first when there is no orderId',
        (tester) async {
      final order = Completer<String>();
      PaymentMethodInfo? asked;
      await show(
        tester,
        PaymentVersion.v1,
        orderId: null,
        createOrderId: (method) {
          asked = method;
          return order.future;
        },
      );
      expect(find.text('Preparando tu pago…'), findsOneWidget);
      expect(asked?.isQr, isTrue);

      order.complete('ORD-9');
      await settle(tester);
      expect(find.byType(PaymentQrView), findsOneWidget);
      expect(lastQrBody()['order'], 'ORD-9');
      await unmount(tester);
    });

    testWidgets('a failed order can be retried or cancelled', (tester) async {
      var attempts = 0;
      await show(
        tester,
        PaymentVersion.v1,
        orderId: null,
        createOrderId: (_) async {
          attempts++;
          if (attempts == 1) throw StateError('backend down');
          return 'ORD-2';
        },
      );
      expect(find.text('No se pudo preparar el pago'), findsOneWidget);
      expect(find.text('Cancelar'), findsOneWidget);

      await tester.tap(find.text('Reintentar'));
      await settle(tester);
      expect(attempts, 2);
      expect(find.byType(PaymentQrView), findsOneWidget);
      await unmount(tester);
    });
  });

  group('V2', () {
    testWidgets('shows the methods, then the QR of the chosen one',
        (tester) async {
      await show(tester, PaymentVersion.v2);

      expect(find.text('¿Con qué vas a pagar hoy?'), findsOneWidget);
      await tester.tap(find.text('Pago QR'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Confirmar'));
      await tester.pump(const Duration(milliseconds: 400));
      await settle(tester);

      expect(find.byType(PaymentQrView), findsOneWidget);
      await unmount(tester);
    });
  });

  group('a single available method', () {
    testWidgets('V2 goes straight to its QR, without list or instructions',
        (tester) async {
      PaymentMethodInfo? asked;
      await show(
        tester,
        PaymentVersion.v2,
        orderId: null,
        createOrderId: (method) async {
          asked = method;
          return 'ORD-5';
        },
        autoSelectSingleMethod: true,
      );

      expect(find.text('¿Con qué vas a pagar hoy?'), findsNothing);
      expect(find.text('Prepárate para escanear'), findsNothing);
      expect(asked?.code, 'QR');
      expect(find.byType(PaymentQrView), findsOneWidget);
      expect(lastQrBody()['order'], 'ORD-5');
      await unmount(tester);
    });

    testWidgets('an unsupported method does not count as a second one',
        (tester) async {
      adapter.handler = (request) {
        if (request.uri.path == '/api/payment-methods') {
          return const FakeResponse(200, {
            'ok': true,
            'message': 'OK',
            'data': [
              {'code': 'QR', 'name': 'Pago QR', 'currency': 'BOB'},
              {'code': 'CARD', 'name': 'Tarjeta', 'currency': 'BOB'},
            ],
          });
        }
        return FakeResponse.ok({
          'id_payment': 'QR-1',
          'imageQR': tinyPngBase64,
          'status': 'PENDING',
        });
      };
      await show(tester, PaymentVersion.v2, autoSelectSingleMethod: true);

      expect(find.byType(PaymentQrView), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('cancelling shows the list instead of a new QR',
        (tester) async {
      await show(tester, PaymentVersion.v2, autoSelectSingleMethod: true);
      expect(find.byType(PaymentQrView), findsOneWidget);
      final qrsBefore =
          adapter.requests.where((r) => r.method == 'POST').length;

      await tester.ensureVisible(find.text('Cancelar'));
      await tester.tap(find.text('Cancelar'));
      await settle(tester);

      expect(events, ['cancel']);
      expect(find.byType(PaymentQrView), findsNothing);
      expect(find.text('Pago QR'), findsOneWidget);
      expect(adapter.requests.where((r) => r.method == 'POST').length,
          qrsBefore);
    });

    testWidgets('V3 opens the window straight on the QR', (tester) async {
      await show(
        tester,
        PaymentVersion.v3,
        autoOpen: true,
        autoSelectSingleMethod: true,
      );

      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('¿Con qué vas a pagar hoy?'), findsNothing);
      expect(find.byType(PaymentQrView), findsOneWidget);

      await tester.tap(find.byTooltip('Cerrar'));
      await settle(tester);
      expect(events, ['cancel']);
    });
  });

  group('V2 with nothing to pay with', () {
    testWidgets('a failed load offers Volver when onBack is set',
        (tester) async {
      adapter.handler =
          (_) => FakeResponse.error(404, 'Cannot GET /api/payment-methods');
      await show(tester, PaymentVersion.v2, onBack: () => events.add('back'));

      expect(find.text('Cannot GET /api/payment-methods'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
      await tester.tap(find.text('Volver'));
      expect(events, ['back']);
    });

    testWidgets('an empty list offers Volver when onBack is set',
        (tester) async {
      adapter.handler = (_) => const FakeResponse(
          200, {'ok': true, 'message': 'OK', 'data': <Object>[]});
      await show(tester, PaymentVersion.v2, onBack: () => events.add('back'));

      expect(find.text('No hay métodos de pago disponibles'), findsOneWidget);
      await tester.tap(find.text('Volver'));
      expect(events, ['back']);
    });

    testWidgets('without onBack there is no back button', (tester) async {
      adapter.handler =
          (_) => FakeResponse.error(404, 'Cannot GET /api/payment-methods');
      await show(tester, PaymentVersion.v2);

      expect(find.text('Reintentar'), findsOneWidget);
      expect(find.text('Volver'), findsNothing);
    });
  });

  group('V3', () {
    testWidgets('a pay button opens the window; a paid QR calls onSuccess',
        (tester) async {
      await show(tester, PaymentVersion.v3);
      expect(find.byType(BottomSheet), findsNothing);

      await tester.tap(find.text('Pagar Bs 150.00'));
      await settle(tester);
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('Procesando tu pago…'), findsOneWidget);

      await tester.tap(find.text('Pago QR'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Confirmar'));
      await tester.pump(const Duration(milliseconds: 400));
      await settle(tester);

      statuses = ['PAID'];
      await tester.pump(const Duration(seconds: 1));
      await settle(tester);
      await tester.pump(const Duration(seconds: 2));
      await settle(tester);

      expect(events, ['success QR-1']);
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('with nothing to pay with, Volver closes the window',
        (tester) async {
      adapter.handler =
          (_) => FakeResponse.error(404, 'Cannot GET /api/payment-methods');
      await show(tester, PaymentVersion.v3, autoOpen: true);
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);

      await tester.tap(find.text('Volver'));
      await settle(tester);

      expect(find.byType(BottomSheet), findsNothing);
      expect(events, ['cancel']);
    });

    testWidgets('autoOpen opens the window; closing it calls onCancel',
        (tester) async {
      await show(tester, PaymentVersion.v3, autoOpen: true);
      expect(find.byType(BottomSheet), findsOneWidget);

      await tester.tap(find.byTooltip('Cerrar'));
      await settle(tester);

      expect(events, ['cancel']);
      expect(find.text('Pagar Bs 150.00'), findsOneWidget);
    });
  });

  testWidgets('changing the version starts over with the new one',
      (tester) async {
    await show(tester, PaymentVersion.v2);
    expect(find.text('¿Con qué vas a pagar hoy?'), findsOneWidget);

    await show(tester, PaymentVersion.v1);
    expect(find.text('¿Con qué vas a pagar hoy?'), findsNothing);
    expect(find.byType(PaymentQrView), findsOneWidget);
    await unmount(tester);
  });
}
