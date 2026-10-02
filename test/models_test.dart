import 'package:flutter_test/flutter_test.dart';
import 'package:payment_sdk_flutter/payment_sdk_flutter.dart';

import 'helpers/fake_adapter.dart';

void main() {
  group('PaymentStatus', () {
    test('parses backend values, case-insensitively', () {
      expect(PaymentStatus.fromJson('PENDING'), PaymentStatus.pending);
      expect(PaymentStatus.fromJson('PAID'), PaymentStatus.paid);
      expect(PaymentStatus.fromJson('ERROR'), PaymentStatus.failed);
      expect(PaymentStatus.fromJson('EXPIRED'), PaymentStatus.expired);
      expect(PaymentStatus.fromJson(' paid '), PaymentStatus.paid);
    });

    test('falls back to unknown', () {
      for (final value in ['REFUNDED', 'UNKNOWN', '', null, 3]) {
        expect(PaymentStatus.fromJson(value), PaymentStatus.unknown);
      }
    });

    test('isFinal', () {
      expect(PaymentStatus.pending.isFinal, isFalse);
      expect(PaymentStatus.unknown.isFinal, isFalse);
      expect(PaymentStatus.paid.isFinal, isTrue);
      expect(PaymentStatus.failed.isFinal, isTrue);
      expect(PaymentStatus.expired.isFinal, isTrue);
    });
  });

  group('QrPayment', () {
    final json = {
      'id_payment': 'QR-991',
      'imageQR': tinyPngBase64,
      'dueDate': '29/09/2026',
      'status': 'PENDING',
    };

    test('fromJson / toJson round trip', () {
      final payment = QrPayment.fromJson(json);
      expect(payment.paymentId, 'QR-991');
      expect(payment.status, PaymentStatus.pending);
      expect(payment.toJson(), json);
    });

    test('tolerates missing and non-string fields', () {
      final payment = QrPayment.fromJson({'id_payment': 42});
      expect(payment.paymentId, '42');
      expect(payment.dueDate, isNull);
      expect(payment.status, PaymentStatus.unknown);
      expect(payment.hasQrImage, isFalse);
    });

    test('decodes the Base64 PNG, with or without a data URI prefix', () {
      final plain = QrPayment.fromJson(json).qrImageBytes;
      final dataUri = QrPayment.fromJson({
        ...json,
        'imageQR': 'data:image/png;base64,$tinyPngBase64',
      }).qrImageBytes;

      expect(plain!.sublist(1, 4), 'PNG'.codeUnits);
      expect(dataUri, plain);
    });

    test('invalid Base64 yields no image', () {
      expect(QrPayment.fromJson({...json, 'imageQR': 'not base64!'}).hasQrImage,
          isFalse);
    });

    test('copyWith replaces the status', () {
      final paid =
          QrPayment.fromJson(json).copyWith(status: PaymentStatus.paid);
      expect(paid.status, PaymentStatus.paid);
      expect(paid.paymentId, 'QR-991');
    });
  });

  group('PaymentMethodInfo', () {
    test('fromJson / toJson', () {
      final json = {
        'code': 'QR',
        'name': 'Pago QR',
        'description': 'Escanea',
        'icon': 'https://x/qr.png',
        'currency': 'BOB',
        'position': 2,
      };
      final method = PaymentMethodInfo.fromJson(json);
      expect(method.code, 'QR');
      expect(method.iconUrl, 'https://x/qr.png');
      expect(method.position, 2);
      expect(method.toJson(), json);
    });

    test('tolerates missing fields', () {
      final method = PaymentMethodInfo.fromJson({'code': 'CARD'});
      expect(method.name, '');
      expect(method.currency, isNull);
      expect(method.position, 0);
    });

    test('only QR is supported by this SDK version', () {
      expect(PaymentMethodInfo.fromJson({'code': 'qr'}).isSupported, isTrue);
      expect(PaymentMethodInfo.fromJson({'code': 'CARD'}).isSupported, isFalse);
      expect(PaymentMethodInfo.fromJson({'code': 'NEW'}).isSupported, isFalse);
    });
  });
}
