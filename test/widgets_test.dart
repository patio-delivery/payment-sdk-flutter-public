import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payment_sdk_flutter/payment_sdk_flutter.dart';

import 'helpers/fake_adapter.dart';

void main() {
  late FakeAdapter adapter;
  late PaymentSdk payments;
  late List<String> statusScript;

  const pending = {
    'id_payment': 'QR-1',
    'imageQR': tinyPngBase64,
    'dueDate': '29/09/2026',
    'status': 'PENDING',
  };

  setUp(() {
    statusScript = ['PENDING', 'PAID'];
    adapter = FakeAdapter((request) {
      if (request.method == 'POST') return FakeResponse.ok(pending);
      final status =
          statusScript.length > 1 ? statusScript.removeAt(0) : statusScript[0];
      return FakeResponse.ok({'order': 'ORD-1', 'status': status});
    });
    payments = PaymentSdk(
      config: PaymentSdkConfig(baseUrl: 'http://backend.test/api', apiKey: 'k'),
      httpClientAdapter: adapter,
    );
  });

  Widget host(Widget child) => MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: child)),
      );

  const interval = Duration(seconds: 1);

  /// Lets the fake HTTP round trip and the resulting rebuilds complete. Part
  /// of dio's pipeline runs outside the fake clock, hence the real wait.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 1));
    }
  }

  PaymentCheckout checkout({
    bool autoStart = true,
    Duration pollInterval = const Duration(minutes: 1),
    Duration qrTimeout = const Duration(minutes: 5),
    Duration confirmTimeout = const Duration(seconds: 4),
    ValueChanged<QrPayment>? onSuccess,
    ValueChanged<PaymentSdkException>? onError,
    ValueChanged<PaymentStatus>? onStatusChanged,
    VoidCallback? onCancel,
    VoidCallback? onNewQr,
    VoidCallback? onTimeout,
    String Function()? nextOrderId,
  }) =>
      PaymentCheckout(
        payments: payments,
        amount: 150,
        currency: 'BOB',
        orderId: 'ORD-1',
        autoStart: autoStart,
        pollInterval: pollInterval,
        qrTimeout: qrTimeout,
        confirmTimeout: confirmTimeout,
        onSuccess: onSuccess,
        onError: onError,
        onStatusChanged: onStatusChanged,
        onCancel: onCancel,
        onNewQr: onNewQr,
        onTimeout: onTimeout,
        nextOrderId: nextOrderId,
      );

  int posts() => adapter.requests.where((r) => r.method == 'POST').length;

  testWidgets('generates the QR with a countdown and reports success',
      (tester) async {
    QrPayment? paid;
    final statuses = <PaymentStatus>[];
    await tester.pumpWidget(host(checkout(
      autoStart: false,
      pollInterval: interval,
      onSuccess: (p) => paid = p,
      onStatusChanged: statuses.add,
    )));
    expect(find.text('BOB 150.00'), findsOneWidget);

    await tester.tap(find.text('Pagar con QR'));
    await settle(tester);
    expect(find.byType(PaymentQrView), findsOneWidget);
    expect(find.text('05:00'), findsOneWidget);
    expect(find.text('Ya pagué'), findsOneWidget);

    await tester.pump(interval);
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 400)); // state transition
    expect(find.text('¡Pago confirmado!'), findsOneWidget);
    expect(find.byType(PaymentQrView), findsNothing);
    expect(paid?.paymentId, 'QR-1');
    expect(paid?.status, PaymentStatus.paid);
    expect(statuses, [PaymentStatus.pending, PaymentStatus.paid]);
  });

  testWidgets('shows generation errors and retries', (tester) async {
    final errors = <PaymentSdkException>[];
    var failNext = true;
    final original = adapter.handler;
    adapter.handler = (request) {
      if (request.method == 'POST' && failNext) {
        failNext = false;
        return FakeResponse.error(503, 'Proveedor no disponible');
      }
      return original(request);
    };

    await tester.pumpWidget(host(checkout(onError: errors.add)));
    await settle(tester);
    expect(find.text('No pudimos generar el QR'), findsOneWidget);
    expect(find.text('Proveedor no disponible'), findsOneWidget);
    expect(errors.single, isA<ProviderException>());

    await tester.tap(find.text('Reintentar'));
    await settle(tester);
    expect(find.byType(PaymentQrView), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  group('"Ya pagué"', () {
    testWidgets('confirms a payment that arrived', (tester) async {
      statusScript = ['PENDING'];
      QrPayment? paid;
      await tester.pumpWidget(host(checkout(onSuccess: (p) => paid = p)));
      await settle(tester);

      statusScript = ['PAID'];
      await tester.tap(find.text('Ya pagué'));
      await tester.pump();
      expect(find.text('Verificando tu pago…'), findsOneWidget);

      await settle(tester);
      expect(find.text('¡Pago confirmado!'), findsOneWidget);
      expect(paid?.status, PaymentStatus.paid);
    });

    testWidgets('returns to the QR with the remaining time when unpaid',
        (tester) async {
      statusScript = ['PENDING'];
      await tester.pumpWidget(host(checkout()));
      await settle(tester);
      await tester.pump(const Duration(seconds: 30));
      expect(find.text('04:30'), findsOneWidget);

      await tester.tap(find.text('Ya pagué'));
      await settle(tester);
      expect(find.text('Verificando tu pago…'), findsOneWidget);
      for (var i = 0; i < 2; i++) {
        await tester.pump(const Duration(seconds: 2));
        await settle(tester);
      }

      expect(find.text('Aún no recibimos tu pago'), findsOneWidget);
      expect(find.byType(PaymentQrView), findsOneWidget);
      expect(find.textContaining('04:2'), findsOneWidget);

      await tester.pump(const Duration(seconds: 8));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Aún no recibimos tu pago'), findsNothing);

      await tester.pumpWidget(const SizedBox());
    });
  });

  group('countdown', () {
    testWidgets('checks one last time, shows the timeout and leaves',
        (tester) async {
      statusScript = ['PENDING'];
      var left = 0;
      final statuses = <PaymentStatus>[];
      await tester.pumpWidget(host(checkout(
        qrTimeout: const Duration(seconds: 10),
        onTimeout: () => left++,
        onStatusChanged: statuses.add,
      )));
      await settle(tester);
      final checksBefore = adapter.requests.length;

      await tester.pump(const Duration(seconds: 10));
      await settle(tester);
      expect(adapter.requests.length, greaterThan(checksBefore));
      expect(find.text('Tiempo agotado'), findsOneWidget);
      expect(statuses.last, PaymentStatus.expired);
      expect(left, 0);

      await tester.pump(const Duration(seconds: 4));
      expect(left, 1);
    });

    testWidgets('a payment made at the very end still counts', (tester) async {
      statusScript = ['PENDING'];
      QrPayment? paid;
      var left = 0;
      await tester.pumpWidget(host(checkout(
        qrTimeout: const Duration(seconds: 10),
        onSuccess: (p) => paid = p,
        onTimeout: () => left++,
      )));
      await settle(tester);

      statusScript = ['PAID'];
      await tester.pump(const Duration(seconds: 10));
      await settle(tester);
      expect(find.text('¡Pago confirmado!'), findsOneWidget);
      expect(paid, isNotNull);

      await tester.pump(const Duration(seconds: 5));
      expect(left, 0);
    });
  });

  testWidgets('offers a new QR with a new order id after expiry',
      (tester) async {
    statusScript = ['EXPIRED'];
    var n = 0;
    await tester.pumpWidget(host(checkout(
      pollInterval: interval,
      nextOrderId: () => 'ORD-1-R${++n}',
    )));
    await settle(tester);
    await tester.pump(interval);
    await settle(tester);
    expect(find.text('Tiempo agotado'), findsOneWidget);

    await tester.tap(find.text('Generar nuevo QR'));
    await settle(tester);
    final lastPost =
        adapter.requests.lastWhere((r) => r.method == 'POST').data as Map;
    expect(lastPost['order'], 'ORD-1-R1');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('onNewQr lets the host handle a new QR', (tester) async {
    statusScript = ['EXPIRED'];
    var asked = 0;
    await tester.pumpWidget(host(checkout(
      pollInterval: interval,
      onNewQr: () => asked++,
    )));
    await settle(tester);
    await tester.pump(interval);
    await settle(tester);
    await tester.tap(find.text('Generar nuevo QR'));
    await settle(tester);

    expect(asked, 1);
    expect(posts(), 1);
  });

  testWidgets('cancel checks the payment first', (tester) async {
    statusScript = ['PENDING'];
    var cancelled = 0;
    await tester.pumpWidget(host(checkout(onCancel: () => cancelled++)));
    await settle(tester);
    final checksBefore = adapter.requests.length;
    await tester.ensureVisible(find.text('Cancelar'));
    await tester.tap(find.text('Cancelar'));
    await settle(tester);

    expect(cancelled, 1);
    expect(adapter.requests.length, checksBefore + 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('cancel reports success when the QR was already paid',
      (tester) async {
    statusScript = ['PENDING'];
    var cancelled = 0;
    QrPayment? paid;
    await tester.pumpWidget(host(checkout(
      onCancel: () => cancelled++,
      onSuccess: (p) => paid = p,
    )));
    await settle(tester);
    statusScript = ['PAID'];
    await tester.ensureVisible(find.text('Cancelar'));
    await tester.tap(find.text('Cancelar'));
    await settle(tester);

    expect(cancelled, 0);
    expect(paid?.status, PaymentStatus.paid);
    expect(find.text('¡Pago confirmado!'), findsOneWidget);
  });

  testWidgets('PaymentQrView shows a placeholder without an image',
      (tester) async {
    await tester.pumpWidget(
      host(
        const PaymentQrView(
          payment: QrPayment(
            paymentId: 'Q',
            qrImageBase64: '',
            status: PaymentStatus.pending,
          ),
        ),
      ),
    );
    expect(find.text('QR no disponible'), findsOneWidget);
  });
}
