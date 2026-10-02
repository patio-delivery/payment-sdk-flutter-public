import 'package:flutter_test/flutter_test.dart';
import 'package:payment_sdk_flutter/payment_sdk_flutter.dart';

void main() {
  test('applies defaults', () {
    final config =
        PaymentSdkConfig(baseUrl: 'http://localhost:8000/api', apiKey: 'key');

    expect(config.baseUrl, 'http://localhost:8000/api');
    expect(config.timeout, const Duration(seconds: 30));
    expect(config.defaultQrExpiration, const Duration(hours: 24));
    expect(config.enableLogging, isFalse);
  });

  test('trims baseUrl and drops the trailing slash', () {
    final config = PaymentSdkConfig(
        baseUrl: ' https://pay.example.com/api/ ', apiKey: 'key');
    expect(config.baseUrl, 'https://pay.example.com/api');
  });

  for (final url in ['', 'localhost:8000', '/api', 'ftp://host/api']) {
    test('rejects baseUrl "$url"', () {
      expect(() => PaymentSdkConfig(baseUrl: url, apiKey: 'key'),
          throwsArgumentError);
    });
  }

  test('rejects an empty apiKey and non-positive durations', () {
    expect(() => PaymentSdkConfig(baseUrl: 'http://h/api', apiKey: ' '),
        throwsArgumentError);
    expect(
      () => PaymentSdkConfig(
          baseUrl: 'http://h/api', apiKey: 'k', timeout: Duration.zero),
      throwsArgumentError,
    );
    expect(
      () => PaymentSdkConfig(
        baseUrl: 'http://h/api',
        apiKey: 'k',
        defaultQrExpiration: const Duration(seconds: -1),
      ),
      throwsArgumentError,
    );
  });

  test('toString hides the API key', () {
    final config =
        PaymentSdkConfig(baseUrl: 'http://h/api', apiKey: 'super-secret');
    expect(config.toString(), isNot(contains('super-secret')));
  });
}
