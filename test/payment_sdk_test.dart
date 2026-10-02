import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payment_sdk_flutter/payment_sdk_flutter.dart';

import 'helpers/fake_adapter.dart';

void main() {
  late FakeAdapter adapter;
  late PaymentSdk payments;

  setUp(() {
    adapter = FakeAdapter((_) => FakeResponse.ok({}));
    payments = PaymentSdk(
      config: PaymentSdkConfig(
        baseUrl: 'http://backend.test/api',
        apiKey: 'k',
        defaultQrExpiration: const Duration(hours: 2),
      ),
      httpClientAdapter: adapter,
    );
  });

  group('generateQr', () {
    test('posts the backend body and parses the QR', () async {
      adapter.handler = (_) => FakeResponse.ok(
            {
              'id_payment': 'QR-1',
              'imageQR': tinyPngBase64,
              'status': 'PENDING'
            },
            statusCode: 201,
          );
      final due = DateTime.now().add(const Duration(hours: 1));

      final qr = await payments.generateQr(
        orderId: ' ORD-1 ',
        amount: 100,
        description: 'Pedido 1',
        dueDate: due,
      );

      final request = adapter.requests.single;
      expect(request.method, 'POST');
      expect(request.uri.path, '/api/qr');
      expect(request.data, {
        'order': 'ORD-1',
        'glosa': 'Pedido 1',
        'amount': 100,
        'dueDate': due.toUtc().toIso8601String(),
      });
      expect(qr.paymentId, 'QR-1');
      expect(qr.status, PaymentStatus.pending);
      expect(qr.hasQrImage, isTrue);
    });

    test('defaults dueDate from the config', () async {
      final expected = DateTime.now().add(const Duration(hours: 2));
      await payments.generateQr(orderId: 'ORD-1', amount: 1);

      final sent =
          DateTime.parse(adapter.requests.single.data['dueDate'] as String);
      expect(sent.difference(expected).inSeconds.abs(), lessThan(5));
    });

    test('validates locally, reporting every problem', () async {
      await expectLater(
        payments.generateQr(
          orderId: ' ',
          amount: double.nan,
          dueDate: DateTime.now().subtract(const Duration(minutes: 1)),
        ),
        throwsA(isA<ValidationException>()
            .having((e) => e.errors, 'errors', hasLength(3))),
      );
      expect(adapter.requests, isEmpty);
    });
  });

  group('getPayment', () {
    test('reads /qr/by-id with the id encoded', () async {
      adapter.handler = (_) => FakeResponse.ok(
          {'id_payment': 'A/B 1', 'imageQR': '', 'status': 'PAID'});
      final payment = await payments.getPayment(' A/B 1 ');

      expect(adapter.requests.single.uri.path, '/api/qr/by-id/A%2FB%201');
      expect(payment.status, PaymentStatus.paid);
    });

    test('rejects an empty id without calling the backend', () async {
      await expectLater(
          payments.getPayment(' '), throwsA(isA<ValidationException>()));
      expect(adapter.requests, isEmpty);
    });
  });

  test('getPaymentStatus reads /qr/status/:order', () async {
    adapter.handler =
        (_) => FakeResponse.ok({'order': 'ORD-1', 'status': 'EXPIRED'});

    expect(await payments.getPaymentStatus('ORD-1'), PaymentStatus.expired);
    expect(adapter.requests.single.uri.path, '/api/qr/status/ORD-1');
  });

  group('getPaymentMethods', () {
    test('reads /payment-methods in the backend order', () async {
      adapter.handler = (_) => const FakeResponse(200, {
            'ok': true,
            'message': 'OK',
            'data': [
              {
                'code': 'QR',
                'name': 'Pago QR',
                'currency': 'BOB',
                'position': 0
              },
              {'code': 'CARD', 'name': 'Tarjeta', 'position': 1},
            ],
          });

      final methods = await payments.getPaymentMethods();

      expect(adapter.requests.single.method, 'GET');
      expect(adapter.requests.single.uri.path, '/api/payment-methods');
      expect(methods.map((m) => m.code), ['QR', 'CARD']);
      expect(methods.first.currency, 'BOB');
    });

    test('an envelope without a list is a BackendException', () async {
      adapter.handler = (_) => FakeResponse.ok({'code': 'QR'});
      await expectLater(
        payments.getPaymentMethods(),
        throwsA(isA<BackendException>()),
      );
    });

    test('maps HTTP errors like every other call', () async {
      adapter.handler = (_) => FakeResponse.error(401, 'Invalid API key');
      await expectLater(
        payments.getPaymentMethods(),
        throwsA(isA<AuthenticationException>()),
      );
    });
  });

  group('watchPaymentStatus', () {
    const interval = Duration(milliseconds: 10);

    /// Answers each poll with the next step: a status string, a
    /// [FakeResponse], or a [DioExceptionType] to throw.
    void script(List<Object> steps) {
      var i = 0;
      adapter.handler = (request) {
        final step = steps[i < steps.length ? i++ : steps.length - 1];
        if (step is FakeResponse) return step;
        if (step is DioExceptionType) throw transportError(request, step);
        return FakeResponse.ok({'order': 'ORD-1', 'status': step});
      };
    }

    Stream<PaymentStatus> watch(
            {Duration timeout = const Duration(minutes: 1)}) =>
        payments.watchPaymentStatus('ORD-1',
            interval: interval, timeout: timeout);

    test('emits changes only and closes on a final status', () async {
      script(['PENDING', 'PENDING', 'PAID']);

      expect(
          await watch().toList(), [PaymentStatus.pending, PaymentStatus.paid]);
      expect(adapter.requests, hasLength(3));
    });

    test('keeps polling after retryable errors', () async {
      script([
        'PENDING',
        DioExceptionType.connectionError,
        FakeResponse.error(503, 'provider down'),
        'EXPIRED',
      ]);

      await expectLater(
        watch(),
        emitsInOrder([
          PaymentStatus.pending,
          emitsError(isA<NetworkException>()),
          emitsError(isA<ProviderException>()),
          PaymentStatus.expired,
          emitsDone,
        ]),
      );
    });

    test('stops after a non-retryable error', () async {
      script([FakeResponse.error(401, 'Invalid API key'), 'PAID']);

      await expectLater(
          watch(),
          emitsInOrder(
              [emitsError(isA<AuthenticationException>()), emitsDone]));
      expect(adapter.requests, hasLength(1));
    });

    test('gives up with StatusWatchTimeoutException', () async {
      script(['PENDING']);

      await expectLater(
        watch(timeout: const Duration(milliseconds: 45)),
        emitsInOrder([
          PaymentStatus.pending,
          emitsError(isA<StatusWatchTimeoutException>().having(
              (e) => e.lastStatus, 'lastStatus', PaymentStatus.pending)),
          emitsDone,
        ]),
      );
    });

    test('stops polling when cancelled', () async {
      script(['PENDING']);
      final subscription = watch().listen((_) {});
      while (adapter.requests.length < 2) {
        await Future<void>.delayed(interval);
      }
      await subscription.cancel();
      final count = adapter.requests.length;
      await Future<void>.delayed(interval * 5);

      expect(count, greaterThan(1));
      expect(adapter.requests, hasLength(count));
    });

    test('does nothing until listened to', () async {
      watch();
      await Future<void>.delayed(interval * 3);
      expect(adapter.requests, isEmpty);
    });
  });
}
