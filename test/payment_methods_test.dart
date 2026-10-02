import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payment_sdk_flutter/payment_sdk_flutter.dart';

import 'helpers/fake_adapter.dart';

void main() {
  late FakeAdapter adapter;
  late PaymentSdk payments;
  late FakeResponse methodsResponse;

  const methodsBody = {
    'ok': true,
    'message': 'OK',
    'data': [
      {'code': 'QR', 'name': 'Pago QR', 'currency': 'BOB', 'position': 0},
      {'code': 'CARD', 'name': 'Tarjeta', 'currency': 'BOB', 'position': 1},
    ],
  };

  setUp(() {
    methodsResponse = const FakeResponse(200, methodsBody);
    adapter = FakeAdapter((request) {
      final path = request.uri.path;
      if (path == '/api/payment-methods') return methodsResponse;
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

  Future<void> show(WidgetTester tester, PaymentMethods widget) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: widget)),
    ));
    await settle(tester);
  }

  Future<void> chooseQr(WidgetTester tester) async {
    await tester.tap(find.text('Pago QR'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Confirmar'));
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);
  }

  List<Map<dynamic, dynamic>> posts() => adapter.requests
      .where((r) => r.method == 'POST')
      .map((r) => r.data as Map)
      .toList();

  PaymentMethods view({
    String? orderId = 'ORD-1',
    Future<String> Function(PaymentMethodInfo)? createOrderId,
    ValueChanged<PaymentMethodInfo>? onMethodSelected,
  }) =>
      PaymentMethods(
        payments: payments,
        amount: 150,
        orderId: orderId,
        createOrderId: createOrderId,
        pollInterval: const Duration(minutes: 1),
        onMethodSelected: onMethodSelected,
      );

  testWidgets('shows only the methods this SDK supports, from the backend',
      (tester) async {
    await show(tester, view());

    expect(adapter.requests.first.uri.path, '/api/payment-methods');
    expect(find.text('¿Con qué vas a pagar hoy?'), findsOneWidget);
    expect(find.text('Pago QR'), findsOneWidget);
    expect(find.text('Tarjeta'), findsNothing);
    expect(posts(), isEmpty);
  });

  testWidgets('choosing QR generates it with the backend currency',
      (tester) async {
    PaymentMethodInfo? chosen;
    await show(tester, view(onMethodSelected: (m) => chosen = m));
    await chooseQr(tester);

    expect(chosen?.code, 'QR');
    expect(posts().single['order'], 'ORD-1');
    expect(find.byType(PaymentQrView), findsOneWidget);
    expect(find.text('BOB 150.00'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('createOrderId runs once the method is chosen', (tester) async {
    final created = Completer<String>();
    var asked = 0;
    await show(
      tester,
      view(
        orderId: null,
        createOrderId: (_) {
          asked++;
          return created.future;
        },
      ),
    );
    expect(asked, 0);

    await tester.tap(find.text('Pago QR'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Confirmar'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(asked, 1);
    expect(find.text('Preparando tu pago…'), findsOneWidget);

    created.complete('ORD-NEW');
    await settle(tester);
    expect(posts().single['order'], 'ORD-NEW');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('descriptionFor builds the glosa with the new order id',
      (tester) async {
    await show(
      tester,
      PaymentMethods(
        payments: payments,
        amount: 150,
        createOrderId: (_) async => 'ORD-9',
        description: 'ignored',
        descriptionFor: (orderId) => 'Pago comercio 64 - $orderId',
        pollInterval: const Duration(minutes: 1),
      ),
    );
    await chooseQr(tester);

    expect(posts().single['glosa'], 'Pago comercio 64 - ORD-9');
    expect(find.text('Pago comercio 64 - ORD-9'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('without descriptionFor the description is sent as is',
      (tester) async {
    await show(
      tester,
      PaymentMethods(
        payments: payments,
        amount: 150,
        orderId: 'ORD-1',
        description: 'Pedido 1',
        pollInterval: const Duration(minutes: 1),
      ),
    );
    await chooseQr(tester);

    expect(posts().single['glosa'], 'Pedido 1');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a failed order creation returns to the methods', (tester) async {
    await show(
      tester,
      view(orderId: null, createOrderId: (_) async => throw StateError('x')),
    );
    await chooseQr(tester);

    expect(find.text('No se pudo preparar el pago. Intenta de nuevo.'),
        findsOneWidget);
    expect(find.text('Pago QR'), findsOneWidget);
    expect(posts(), isEmpty);
  });

  testWidgets('cancel verifies, goes back to the methods and tells the app',
      (tester) async {
    var cancelled = 0;
    await show(
      tester,
      PaymentMethods(
        payments: payments,
        amount: 150,
        orderId: 'ORD-1',
        pollInterval: const Duration(minutes: 1),
        onCancel: () => cancelled++,
      ),
    );
    await chooseQr(tester);

    await tester.ensureVisible(find.text('Cancelar'));
    await tester.tap(find.text('Cancelar'));
    await settle(tester);

    expect(find.byType(PaymentQrView), findsNothing);
    expect(find.text('Pago QR'), findsOneWidget);
    expect(cancelled, 1);
  });

  testWidgets('a methods load error can be retried', (tester) async {
    methodsResponse = FakeResponse.error(503, 'Servicio no disponible');
    await show(tester, view());
    expect(find.text('Servicio no disponible'), findsOneWidget);

    methodsResponse = const FakeResponse(200, methodsBody);
    await tester.tap(find.text('Reintentar'));
    await settle(tester);
    expect(find.text('Pago QR'), findsOneWidget);
  });
}
