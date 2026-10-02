import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payment_sdk_flutter/payment_sdk_flutter.dart';
import 'package:payment_sdk_flutter/src/session/payment_session.dart';

import 'helpers/fake_adapter.dart';

/// PaymentSession on its own, without any widget. testWidgets is used only
/// for its fake clock.
void main() {
  late FakeAdapter adapter;
  late PaymentSdk payments;
  late List<String> statuses;

  setUp(() {
    statuses = ['PENDING'];
    adapter = FakeAdapter((request) {
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

  /// Lets the fake HTTP round trip complete (part of dio runs outside the
  /// fake clock).
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 1));
    }
  }

  PaymentSession session({
    ValueChanged<QrPayment>? onSuccess,
    VoidCallback? onTimeout,
    Duration qrTimeout = const Duration(minutes: 5),
  }) =>
      PaymentSession(
        payments: payments,
        orderId: 'ORD-1',
        amount: 10,
        qrTimeout: qrTimeout,
        confirmTimeout: const Duration(seconds: 4),
        pollInterval: const Duration(minutes: 1),
        onSuccess: onSuccess,
        onTimeout: onTimeout,
      );

  int gets() => adapter.requests.where((r) => r.method == 'GET').length;

  testWidgets('start generates the QR and counts down', (tester) async {
    final s = session();
    expect(s.phase, PaymentPhase.idle);

    unawaited(s.start());
    await settle(tester);
    expect(s.phase, PaymentPhase.waiting);
    expect(s.payment?.paymentId, 'QR-1');
    expect(s.remaining, greaterThan(const Duration(minutes: 4, seconds: 59)));

    await tester.pump(const Duration(seconds: 30));
    expect(s.remaining.inSeconds, inInclusiveRange(269, 270));
    s.dispose();
  });

  testWidgets('confirmPayment reports success when paid', (tester) async {
    QrPayment? paid;
    final s = session(onSuccess: (p) => paid = p);
    unawaited(s.start());
    await settle(tester);

    statuses = ['PAID'];
    unawaited(s.confirmPayment());
    expect(s.phase, PaymentPhase.confirming);
    await settle(tester);

    expect(s.phase, PaymentPhase.paid);
    expect(paid?.status, PaymentStatus.paid);
    s.dispose();
  });

  testWidgets('confirmPayment goes back to the QR when unpaid', (tester) async {
    final s = session();
    unawaited(s.start());
    await settle(tester);

    unawaited(s.confirmPayment());
    for (var i = 0; i < 3; i++) {
      await settle(tester);
      await tester.pump(PaymentSession.confirmInterval);
    }
    await settle(tester);

    expect(s.phase, PaymentPhase.waiting);
    expect(s.showNotPaid, isTrue);
    await tester.pump(PaymentSession.noticeDuration);
    expect(s.showNotPaid, isFalse);
    s.dispose();
  });

  testWidgets('verifyBeforeLeaving blocks leaving a paid QR', (tester) async {
    QrPayment? paid;
    final s = session(onSuccess: (p) => paid = p);
    unawaited(s.start());
    await settle(tester);

    statuses = ['PAID'];
    bool? canLeave;
    unawaited(s.verifyBeforeLeaving().then((v) => canLeave = v));
    await settle(tester);

    expect(canLeave, isFalse);
    expect(paid, isNotNull);
    s.dispose();
  });

  testWidgets('expiry verifies once, then times out after the exit delay',
      (tester) async {
    var left = 0;
    final s = session(
      qrTimeout: const Duration(seconds: 10),
      onTimeout: () => left++,
    );
    unawaited(s.start());
    await settle(tester);
    final before = gets();

    await tester.pump(const Duration(seconds: 10));
    await settle(tester);
    expect(gets(), greaterThan(before));
    expect(s.phase, PaymentPhase.expired);
    expect(left, 0);

    await tester.pump(PaymentSession.timeoutExitDelay);
    expect(left, 1);
    s.dispose();
  });

  testWidgets('dispose stops all polling', (tester) async {
    final s = PaymentSession(
      payments: payments,
      orderId: 'ORD-1',
      amount: 10,
      pollInterval: const Duration(seconds: 1),
    );
    unawaited(s.start());
    await settle(tester);
    s.dispose();
    final count = adapter.requests.length;

    await tester.pump(const Duration(seconds: 5));
    await settle(tester);
    expect(adapter.requests, hasLength(count));
  });
}
