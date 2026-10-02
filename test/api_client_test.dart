import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payment_sdk_flutter/payment_sdk_flutter.dart';
import 'package:payment_sdk_flutter/src/core/api_client.dart';

import 'helpers/fake_adapter.dart';

void main() {
  late FakeAdapter adapter;

  ApiClient client({bool log = false}) => ApiClient(
        PaymentSdkConfig(
          baseUrl: 'http://backend.test/api/',
          apiKey: 'secret-key',
          timeout: const Duration(seconds: 7),
          enableLogging: log,
        ),
        httpClientAdapter: adapter,
      );

  setUp(() => adapter = FakeAdapter((_) => FakeResponse.ok({'value': 1})));

  test('sends base URL, JSON headers, Bearer key and timeouts', () async {
    await client().get('qr/status/A');
    final request = adapter.requests.single;

    expect(request.uri.toString(), 'http://backend.test/api/qr/status/A');
    expect(request.headers['Authorization'], 'Bearer secret-key');
    expect(request.headers['Accept'], Headers.jsonContentType);
    expect(request.connectTimeout, const Duration(seconds: 7));
  });

  test('POST sends JSON and returns the envelope data', () async {
    expect(await client().post('qr', {'order': 'A'}), {'value': 1});
    expect(adapter.requests.single.method, 'POST');
    expect(adapter.requests.single.data, {'order': 'A'});
  });

  group('unexpected responses are BackendException', () {
    for (final (name, body) in [
      ('ok: false', {'ok': false, 'message': 'Nope'}),
      ('not an envelope', ['a']),
      ('no data', {'ok': true, 'message': 'OK'}),
    ]) {
      test(name, () async {
        adapter.handler = (_) => FakeResponse(200, body);
        await expectLater(client().get('x'), throwsA(isA<BackendException>()));
      });
    }
  });

  group('HTTP errors', () {
    Future<PaymentSdkException> failWith(FakeResponse response) async {
      adapter.handler = (_) => response;
      try {
        await client().get('x');
      } on PaymentSdkException catch (e) {
        return e;
      }
      fail('expected an exception');
    }

    test('400 → ValidationException with every message', () async {
      final e = await failWith(
        FakeResponse.error(
            400, ['order must be a string', 'amount must be a number']),
      );
      expect(e, isA<ValidationException>());
      expect((e as ValidationException).errors, hasLength(2));
      expect(e.message, 'order must be a string; amount must be a number');
      expect(e.isRetryable, isFalse);
    });

    test('status codes map to their exception', () async {
      expect(await failWith(FakeResponse.error(401, 'Invalid API key')),
          isA<AuthenticationException>());
      expect(await failWith(FakeResponse.error(403, 'Forbidden')),
          isA<AuthenticationException>());
      expect(await failWith(FakeResponse.error(404, 'QR no encontrado')),
          isA<PaymentNotFoundException>());
      expect(await failWith(FakeResponse.error(429, 'Too Many Requests')),
          isA<RateLimitException>());
      expect(await failWith(FakeResponse.error(503, 'provider down')),
          isA<ProviderException>());
      expect(await failWith(FakeResponse.error(500, 'boom')),
          isA<BackendException>());
    });

    test('keeps the backend message and body', () async {
      final e = await failWith(FakeResponse.error(401, 'Invalid API key'));
      expect(e.message, 'Invalid API key');
      expect(e.statusCode, 401);
      expect(e.details, isA<Map<String, dynamic>>());
    });

    test('falls back to the status without a message', () async {
      expect((await failWith(const FakeResponse(502, {}))).message, 'HTTP 502');
    });

    test('5xx, 429 and 503 are retryable', () async {
      for (final code in [500, 429, 503]) {
        expect((await failWith(FakeResponse.error(code, 'x'))).isRetryable,
            isTrue);
      }
    });
  });

  group('transport errors', () {
    Future<void> expectMapped(DioExceptionType type, Matcher matcher) async {
      adapter.handler = (request) => throw transportError(request, type);
      await expectLater(client().get('x'), throwsA(matcher));
    }

    test('timeouts → RequestTimeoutException', () async {
      for (final type in [
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
      ]) {
        await expectMapped(type, isA<RequestTimeoutException>());
      }
    });

    test('connection error → retryable NetworkException', () async {
      await expectMapped(
        DioExceptionType.connectionError,
        isA<NetworkException>()
            .having((e) => e.isRetryable, 'isRetryable', isTrue),
      );
    });
  });

  test('logging never includes the API key', () async {
    final logs = <String>[];
    final original = debugPrint;
    debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
    addTearDown(() => debugPrint = original);

    final api = client(log: true);
    await api.get('qr/status/A');
    adapter.handler = (_) => FakeResponse.error(401, 'Invalid API key');
    await expectLater(api.get('x'), throwsA(anything));

    expect(
        logs.first, '[PaymentSdk] --> GET http://backend.test/api/qr/status/A');
    expect(logs.join('\n'), isNot(contains('secret-key')));
  });
}
