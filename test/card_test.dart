import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payment_sdk_flutter/payment_sdk_flutter.dart';

import 'helpers/fake_adapter.dart';

const _terminalBody = {
  'code': 'TOTEM100',
  'name': 'Totem Santa Cruz 1',
  'connection': 'BRIDGE',
  'posIp': '192.168.0.34',
  'posPort': 3000,
  'bridgeUrl': null,
};

Map<String, dynamic> _cardBody({
  String status = 'PENDING',
  Map<String, dynamic>? card,
}) =>
    {
      'id': 99,
      'order': 'ORD-1',
      'glosa': 'Pedido 1',
      'amount': 150,
      'currency': 'BOB',
      'status': status,
      'terminal': {'code': 'TOTEM100', 'name': 'Totem Santa Cruz 1'},
      'card': card,
      'createdAt': '2026-11-20T10:00:00.000Z',
      'resolvedAt': card == null ? null : '2026-11-20T10:01:00.000Z',
    };

/// The local service's answer to a sale.
Map<String, dynamic> _bridgeSale({String code = '00', String? message}) => {
      'message': [
        {'name': 'authCode', 'value': '575849'},
        {'name': 'purchaseAmount', 'value': '150.00'},
        {'name': 'receiptNumber', 'value': '000270613845'},
        {'name': 'terminalID', 'value': '5051107'},
        {'name': 'responseCode', 'value': code},
        {'name': 'errorMessage', 'value': message ?? ''},
        {'name': 'last4Digits', 'value': '1234'},
        {'name': 'cardBINTarjeta', 'value': '489997'},
        {'name': 'merchantID', 'value': 'M-1'},
        {'name': 'status', 'value': code == '00' ? 'APROBADA' : 'NEGADA'},
        {'name': 'paymentMethod', 'value': 'Tarjeta'},
        {'name': 'cardNetwork', 'value': 'VISA'},
      ],
    };

void main() {
  group('models', () {
    test('CARD is a supported method', () {
      const card = PaymentMethodInfo(code: 'card', name: 'Tarjeta');
      expect(card.isCard, isTrue);
      expect(card.isQr, isFalse);
      expect(card.isCash, isFalse);
      expect(card.isSupported, isTrue);
    });

    test('CardTerminalConfig reads the terminal, BRIDGE by default', () {
      final config = CardTerminalConfig.fromJson(_terminalBody);
      expect(config.code, 'TOTEM100');
      expect(config.connection, CardConnection.bridge);
      expect(config.posIp, '192.168.0.34');
      expect(config.posPort, 3000);
      expect(config.effectiveBridgeUrl, 'http://127.0.0.1:8000');

      final direct = CardTerminalConfig.fromJson({
        ..._terminalBody,
        'connection': 'direct',
        'posPort': '3001',
        'bridgeUrl': 'http://10.0.0.2:8000',
      });
      expect(direct.connection, CardConnection.direct);
      expect(direct.posPort, 3001);
      expect(direct.effectiveBridgeUrl, 'http://10.0.0.2:8000');
      expect(CardConnection.fromJson('OTRA'), CardConnection.bridge);
    });

    test('CardPayment reads the payment and what the POS answered', () {
      final payment = CardPayment.fromJson(_cardBody(
        status: 'PAID',
        card: {
          'responseCode': '00',
          'authCode': '575849',
          'receiptNumber': '000270613845',
          'last4': '1234',
          'bin': '489997',
          'cardNetwork': 'VISA',
          'entryLabel': 'Tarjeta',
          'message': 'APROBADA',
        },
      ));

      expect(payment.id, 99);
      expect(payment.orderId, 'ORD-1');
      expect(payment.isApproved, isTrue);
      expect(payment.terminalId, 'TOTEM100');
      expect(payment.authCode, '575849');
      expect(payment.maskedCard, 'VISA •••• 1234');
      expect(payment.bin, '489997');
      expect(payment.recorded, isTrue);
    });

    test('ERROR is a rejected card payment', () {
      final payment = CardPayment.fromJson(_cardBody(status: 'ERROR'));
      expect(payment.isRejected, isTrue);
      expect(payment.isApproved, isFalse);
    });
  });

  group('BancardResponse', () {
    test("reads the POS's own sale answer and masks the card", () {
      final result = BancardResponse.fromSale({
        'mensaje': 'APROBADA',
        'respuestaTransacción': '00',
        'merchID': 'M-1',
        'terminalID': 'T-9',
        'pan': '4899971234561234',
        'autorizacion': '575849',
        'fecha': '20/11/2026',
        'hora': '10:00:00',
        'referencia': '000270613845',
        'estado': 'APROBADA',
      });

      expect(result.approved, isTrue);
      expect(result.responseCode, '00');
      expect(result.authCode, '575849');
      expect(result.receiptNumber, '000270613845');
      expect(result.posTerminalId, 'T-9');
      expect(result.posMerchantId, 'M-1');
      expect(result.last4, '1234');
      expect(result.bin, '489997');
      expect(result.cardNetwork, 'VISA');
      expect(result.entryLabel, 'Tarjeta');
      expect(result.raw['pan'], '489997XXXXXX1234');
    });

    test('a code other than 00 is a rejection', () {
      final result = BancardResponse.fromSale({
        'respuestaTransaccion': '05',
        'mensaje': 'NEGADA',
        'pan': '',
      });
      expect(result.approved, isFalse);
      expect(result.message, 'NEGADA');
      expect(result.last4, isNull);
    });

    test('tells QR Simple, Tigo Money and cards apart like the service', () {
      expect(BancardResponse.entryLabelOf('215141XXXXXX2548'), 'QR Simple');
      expect(BancardResponse.entryLabelOf('71234567'), 'Tigo Money');
      expect(BancardResponse.entryLabelOf('489997XXXXXX1234'), 'Tarjeta');
      expect(BancardResponse.cardNetworkOf('5412XXXXXXXX0001'),
          'MASTERCARD_LEGACY');
      expect(BancardResponse.cardNetworkOf('3782XXXXXXXX0001'), 'AMEX');
    });

    test("reads the local service's name/value answer", () {
      final result = BancardResponse.fromNameValues(
          _bridgeSale()['message'] as List<dynamic>);

      expect(result.approved, isTrue);
      expect(result.authCode, '575849');
      expect(result.last4, '1234');
      expect(result.bin, '489997');
      expect(result.cardNetwork, 'VISA');
      expect(result.entryLabel, 'Tarjeta');
      expect(result.toJson(), containsPair('approved', true));
    });
  });

  group('PaymentSdk', () {
    late FakeAdapter adapter;
    late PaymentSdk payments;
    late FakeHandler pos;
    late FakeResponse reportResponse;

    setUp(() {
      pos = (_) => FakeResponse(200, _bridgeSale());
      reportResponse = FakeResponse.ok(_cardBody(
        status: 'PAID',
        card: {'authCode': '575849', 'last4': '1234', 'cardNetwork': 'VISA'},
      ));
      adapter = FakeAdapter((request) {
        final uri = request.uri;
        if (uri.host != 'backend.test') return pos(request);
        if (uri.path == '/api/card/terminals/TOTEM100') {
          return FakeResponse.ok(_terminalBody);
        }
        if (uri.path == '/api/card/terminals/OTRO') {
          return FakeResponse.error(404, 'Terminal no encontrado o inactivo');
        }
        if (uri.path == '/api/card/99/result') return reportResponse;
        if (uri.path == '/api/card/status/ORD-1') {
          return FakeResponse.ok({'order': 'ORD-1', 'status': 'PAID'});
        }
        return FakeResponse.ok(_cardBody(), statusCode: 201);
      });
      payments = PaymentSdk(
        config:
            PaymentSdkConfig(baseUrl: 'http://backend.test/api', apiKey: 'k'),
        httpClientAdapter: adapter,
      );
    });

    Iterable<RequestOptions> backend(String path) =>
        adapter.requests.where((r) => r.uri.path == path);

    test('getCardTerminal reads how to reach the POS', () async {
      final config = await payments.getCardTerminal('TOTEM100');
      expect(config.posIp, '192.168.0.34');
      expect(adapter.requests.single.uri.path, '/api/card/terminals/TOTEM100');
    });

    test('getCardTerminal throws for an unknown terminal', () async {
      await expectLater(
        payments.getCardTerminal('OTRO'),
        throwsA(isA<PaymentNotFoundException>()),
      );
    });

    test('resolveCardTerminal builds the terminal for the connection',
        () async {
      final bridge = await payments
          .resolveCardTerminal(const CardOptions(terminalId: 'TOTEM100'));
      expect(bridge, isA<BancardBridgeTerminal>());

      final direct = await payments.resolveCardTerminal(
        const CardOptions.manual(CardTerminalConfig(
          posIp: '10.0.0.5',
          posPort: 3000,
          connection: CardConnection.direct,
        )),
      );
      expect(direct, isA<BancardDirectTerminal>());
    });

    test('createCardPayment posts the order with its terminal', () async {
      final payment = await payments.createCardPayment(
        orderId: ' ORD-1 ',
        amount: 150,
        description: 'Pedido 1',
        terminalId: 'TOTEM100',
      );

      final request = adapter.requests.single;
      expect(request.method, 'POST');
      expect(request.uri.path, '/api/card');
      expect(request.data, {
        'order': 'ORD-1',
        'amount': 150,
        'glosa': 'Pedido 1',
        'terminalId': 'TOTEM100',
      });
      expect(payment.id, 99);
      expect(payment.status, PaymentStatus.pending);
    });

    test('createCardPayment validates before calling the backend', () async {
      await expectLater(
        payments.createCardPayment(orderId: ' ', amount: 0),
        throwsA(isA<ValidationException>()),
      );
      expect(adapter.requests, isEmpty);
    });

    test('getCardPaymentStatus reads the card status by order', () async {
      expect(await payments.getCardPaymentStatus('ORD-1'), PaymentStatus.paid);
    });

    group('chargeCard', () {
      late CardTerminal terminal;

      setUp(() {
        terminal = BancardBridgeTerminal(
          posIp: '192.168.0.34',
          posPort: 3000,
          httpClientAdapter: adapter,
        );
      });

      test('registers, charges on the POS through the service and records it',
          () async {
        var posStarted = false;
        final payment = await payments.chargeCard(
          terminal: terminal,
          orderId: 'ORD-1',
          amount: 150,
          terminalId: 'TOTEM100',
          onPosStarted: () => posStarted = true,
        );

        final paths = adapter.requests.map((r) => r.uri.path).toList();
        expect(paths, [
          '/api/card',
          '/pago/device001/ctl/150.00',
          '/api/card/99/result',
        ]);
        final sale = adapter.requests[1];
        expect(sale.uri.host, '127.0.0.1');
        expect(sale.uri.queryParameters,
            {'posIp': '192.168.0.34', 'posPort': '3000'});
        // The API key never goes to the POS.
        expect(sale.headers['Authorization'], isNull);
        final report = backend('/api/card/99/result').single.data as Map;
        expect(report['approved'], isTrue);
        expect(report['authCode'], '575849');
        expect(report['last4'], '1234');
        expect(posStarted, isTrue);
        expect(payment.isApproved, isTrue);
        expect(payment.recorded, isTrue);
      });

      test('a rejection is recorded and returned', () async {
        pos = (_) => FakeResponse(200, _bridgeSale(code: '05'));
        reportResponse = FakeResponse.ok(_cardBody(status: 'ERROR'));

        final payment = await payments.chargeCard(
          terminal: terminal,
          orderId: 'ORD-1',
          amount: 150,
        );

        final report = backend('/api/card/99/result').single.data as Map;
        expect(report['approved'], isFalse);
        expect(report['responseCode'], '05');
        expect(payment.isRejected, isTrue);
      });

      test('a POS that could not be reached charged nothing', () async {
        pos = (request) =>
            throw transportError(request, DioExceptionType.connectionError);

        await expectLater(
          payments.chargeCard(terminal: terminal, orderId: 'ORD-1', amount: 1),
          throwsA(isA<CardTerminalException>()
              .having((e) => e.outcomeUnknown, 'outcomeUnknown', isFalse)),
        );
        expect(backend('/api/card/99/result'), isEmpty);
      });

      test('the service saying it could not reach the POS charged nothing',
          () async {
        pos = (_) => FakeResponse.error(502, 'POS_UNREACHABLE');

        await expectLater(
          payments.chargeCard(terminal: terminal, orderId: 'ORD-1', amount: 1),
          throwsA(isA<CardTerminalException>()
              .having((e) => e.outcomeUnknown, 'outcomeUnknown', isFalse)),
        );
      });

      test('a lost answer may have charged the customer', () async {
        pos = (request) =>
            throw transportError(request, DioExceptionType.receiveTimeout);

        await expectLater(
          payments.chargeCard(terminal: terminal, orderId: 'ORD-1', amount: 1),
          throwsA(isA<CardTerminalException>()
              .having((e) => e.outcomeUnknown, 'outcomeUnknown', isTrue)),
        );
        expect(backend('/api/card/99/result'), isEmpty);
      });

      test('a failed registration never touches the POS', () async {
        adapter.handler = (request) => request.uri.host == 'backend.test'
            ? FakeResponse.error(400, 'CARD no habilitado')
            : pos(request);

        await expectLater(
          payments.chargeCard(terminal: terminal, orderId: 'ORD-1', amount: 1),
          throwsA(isA<ValidationException>()),
        );
        expect(adapter.requests.where((r) => r.uri.host != 'backend.test'),
            isEmpty);
      });

      test('the POS result is kept when it could not be recorded', () async {
        reportResponse = FakeResponse.error(500, 'caído');

        final payment = await payments.chargeCard(
          terminal: terminal,
          orderId: 'ORD-1',
          amount: 150,
        );

        expect(backend('/api/card/99/result'), hasLength(3));
        expect(payment.isApproved, isTrue);
        expect(payment.recorded, isFalse);
        expect(payment.authCode, '575849');
      });

      test('reads the POS answer even when it is not sent as JSON', () async {
        for (final type in ['text/plain', 'text/html; charset=utf-8']) {
          final direct = BancardDirectTerminal(
            posIp: '192.168.0.34',
            posPort: 3000,
            httpClientAdapter: _TextAdapter(
              '{"respuestaTransacción":"00","autorizacion":"222",'
              '"referencia":"R-1","pan":"489997XXXXXX1234"}',
              type,
            ),
          );

          final result = await direct.charge(amount: 1, orderId: 'ORD-1');

          expect(result.approved, isTrue, reason: type);
          expect(result.authCode, '222');
          expect(result.last4, '1234');
        }
      });

      test('an answer that is not JSON may have charged, and says what came',
          () async {
        final direct = BancardDirectTerminal(
          posIp: '192.168.0.34',
          posPort: 3000,
          httpClientAdapter: _TextAdapter('<html>OK</html>', 'text/html'),
        );

        await expectLater(
          direct.charge(amount: 1, orderId: 'ORD-1'),
          throwsA(isA<CardTerminalException>()
              .having((e) => e.outcomeUnknown, 'outcomeUnknown', isTrue)
              .having(
                  (e) => e.message, 'message', contains('<html>OK</html>'))),
        );
      });

      test('the direct terminal calls the POS like the service does', () async {
        pos = (_) => const FakeResponse(200, {
              'respuestaTransacción': '00',
              'autorizacion': '111',
              'pan': '4899971234561234',
            });
        final direct = BancardDirectTerminal(
          posIp: '192.168.0.34',
          posPort: 3000,
          httpClientAdapter: adapter,
        );

        final result = await direct.charge(
            amount: 150.5, orderId: 'ORD-1', currency: 'BOB');

        final sale = adapter.requests.single;
        expect(sale.uri.toString(),
            'http://192.168.0.34:3000/sale?monto=15050&cod_moneda=068');
        expect(result.approved, isTrue);
        expect(result.cardNetwork, 'VISA');
      });
    });
  });

  group('widgets', () {
    late FakeAdapter adapter;
    late PaymentSdk payments;
    late List<Map<String, dynamic>> methods;
    late FakeHandler pos;
    late FakeResponse terminalResponse;

    setUp(() {
      methods = [
        {'code': 'QR', 'name': 'Pago QR', 'currency': 'BOB', 'position': 0},
        {'code': 'CARD', 'name': 'Tarjeta', 'currency': 'BOB', 'position': 1},
      ];
      terminalResponse = FakeResponse.ok(_terminalBody);
      pos = (request) => request.uri.path.endsWith('/health')
          ? const FakeResponse(200, {'status': 'ok'})
          : FakeResponse(200, _bridgeSale());
      adapter = FakeAdapter((request) {
        final path = request.uri.path;
        if (request.uri.host != 'backend.test') return pos(request);
        if (path == '/api/payment-methods') {
          return FakeResponse(
              200, {'ok': true, 'message': 'OK', 'data': methods});
        }
        if (path.startsWith('/api/card/terminals/')) return terminalResponse;
        if (path == '/api/card/99/result') {
          final approved = (request.data as Map)['approved'] == true;
          return FakeResponse.ok(_cardBody(
            status: approved ? 'PAID' : 'ERROR',
            card: {
              'authCode': '575849',
              'last4': '1234',
              'cardNetwork': 'VISA',
              'message': approved ? 'APROBADA' : 'Fondos insuficientes',
            },
          ));
        }
        if (path == '/api/card') {
          return FakeResponse.ok(_cardBody(), statusCode: 201);
        }
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
      for (var i = 0; i < 4; i++) {
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

    Future<void> chooseCard(WidgetTester tester) async {
      await tester.tap(find.text('Tarjeta'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Paga con tarjeta'), findsOneWidget);
      await tester.tap(find.text('Confirmar'));
      await tester.pump(const Duration(milliseconds: 400));
      await settle(tester);
    }

    Iterable<String> sales() => adapter.requests
        .where((r) => r.uri.path.startsWith('/pago/device001/ctl/'))
        .map((r) => r.uri.path);

    PaymentMethods view({
      CardOptions? card = const CardOptions(terminalId: 'TOTEM100'),
      ValueChanged<CardPayment>? onCardPayment,
      ValueChanged<PaymentSdkException>? onError,
      VoidCallback? onBackToMethods,
    }) =>
        PaymentMethods(
          payments: payments,
          amount: 150,
          orderId: 'ORD-1',
          pollInterval: const Duration(minutes: 1),
          card: card,
          onCardPayment: card == null ? null : onCardPayment ?? (_) {},
          onError: onError,
          onBackToMethods: onBackToMethods,
        );

    group('PaymentMethods (V2)', () {
      testWidgets('hides card when the app does not turn it on',
          (tester) async {
        await pumpApp(tester, view(card: null));

        expect(find.text('Tarjeta'), findsNothing);
        expect(
          adapter.requests.where((r) => r.uri.path.contains('/card')),
          isEmpty,
        );
        await tester.pumpWidget(const SizedBox());
      });

      testWidgets('hides card when the terminal is not registered',
          (tester) async {
        terminalResponse = FakeResponse.error(404, 'Terminal no encontrado');
        await pumpApp(tester, view());

        expect(find.text('Tarjeta'), findsNothing);
        await tester.pumpWidget(const SizedBox());
      });

      testWidgets("hides card when the POS's service does not answer",
          (tester) async {
        pos = (request) =>
            throw transportError(request, DioExceptionType.connectionError);
        await pumpApp(tester, view());

        expect(find.text('Tarjeta'), findsNothing);
        await tester.pumpWidget(const SizedBox());
      });

      testWidgets('shows card when its POS answers, and never picks it alone',
          (tester) async {
        methods = [methods.last];
        await pumpApp(tester, view());

        expect(find.text('Tarjeta'), findsOneWidget);
        expect(sales(), isEmpty);
      });

      testWidgets('choosing card charges on the POS and reports the approval',
          (tester) async {
        CardPayment? approved;
        await pumpApp(tester, view(onCardPayment: (p) => approved = p));
        await chooseCard(tester);

        expect(sales(), ['/pago/device001/ctl/150.00']);
        expect(find.text('¡Pago aprobado!'), findsOneWidget);
        expect(find.textContaining('VISA •••• 1234'), findsOneWidget);
        expect(approved?.authCode, '575849');
        expect(approved?.terminalId, 'TOTEM100');
        final created = adapter.requests
            .singleWhere((r) => r.uri.path == '/api/card')
            .data as Map;
        expect(created['terminalId'], 'TOTEM100');
      });

      testWidgets('shows the POS while it waits for the card', (tester) async {
        final sale = Completer<FakeResponse>();
        pos = (request) => request.uri.path.endsWith('/health')
            ? const FakeResponse(200, {'status': 'ok'})
            : sale.future;
        await pumpApp(tester, view());
        await chooseCard(tester);

        expect(find.text('Sigue las instrucciones del POS'), findsOneWidget);
        expect(find.text('Volver'), findsNothing);

        sale.complete(FakeResponse(200, _bridgeSale()));
        await settle(tester);
        expect(find.text('¡Pago aprobado!'), findsOneWidget);
      });

      testWidgets('a rejected card can be retried or changed', (tester) async {
        pos = (request) => request.uri.path.endsWith('/health')
            ? const FakeResponse(200, {'status': 'ok'})
            : FakeResponse(200, _bridgeSale(code: '51'));
        CardPayment? approved;
        var backToMethods = 0;
        await pumpApp(
          tester,
          view(
            onCardPayment: (p) => approved = p,
            onBackToMethods: () => backToMethods++,
          ),
        );
        await chooseCard(tester);

        expect(find.text('Tarjeta rechazada'), findsOneWidget);
        expect(find.text('Fondos insuficientes'), findsOneWidget);
        expect(approved, isNull);

        await tester.tap(find.text('Reintentar'));
        await settle(tester);
        expect(sales(), hasLength(2));

        expect(backToMethods, 0);
        await tester.tap(find.text('Otro método'));
        await settle(tester);
        expect(find.text('Pago QR'), findsOneWidget);
        expect(backToMethods, 1);
      });

      testWidgets('an unreachable POS charged nothing and can be retried',
          (tester) async {
        var calls = 0;
        pos = (request) {
          if (request.uri.path.endsWith('/health')) {
            return const FakeResponse(200, {'status': 'ok'});
          }
          calls++;
          throw transportError(request, DioExceptionType.connectionError);
        };
        PaymentSdkException? error;
        await pumpApp(tester, view(onError: (e) => error = e));
        await chooseCard(tester);

        expect(find.text('No pudimos comunicarnos con el POS'), findsOneWidget);
        expect(error, isA<CardTerminalException>());
        await tester.tap(find.text('Reintentar'));
        await settle(tester);
        expect(calls, 2);
      });

      testWidgets('a lost POS answer is never charged again from the SDK',
          (tester) async {
        pos = (request) {
          if (request.uri.path.endsWith('/health')) {
            return const FakeResponse(200, {'status': 'ok'});
          }
          throw transportError(request, DioExceptionType.receiveTimeout);
        };
        await pumpApp(tester, view());
        await chooseCard(tester);

        expect(find.text('No pudimos confirmar el cobro'), findsOneWidget);
        expect(find.text('Reintentar'), findsNothing);
        expect(
          adapter.requests.where((r) => r.uri.path == '/api/card/99/result'),
          isEmpty,
        );

        await tester.tap(find.text('Entendido'));
        await settle(tester);
        expect(find.text('Tarjeta'), findsOneWidget);
      });
    });

    group('PaymentSheet (V3) and PaymentFlow', () {
      testWidgets('the window stays open while the POS charges, then is paid',
          (tester) async {
        final sale = Completer<FakeResponse>();
        pos = (request) => request.uri.path.endsWith('/health')
            ? const FakeResponse(200, {'status': 'ok'})
            : sale.future;
        CardPayment? approved;
        var succeeded = false;
        var cancelled = false;
        await pumpApp(
          tester,
          PaymentFlow(
            version: PaymentVersion.v3,
            payments: payments,
            amount: 150,
            orderId: 'ORD-1',
            pollInterval: const Duration(minutes: 1),
            successDelay: const Duration(milliseconds: 100),
            card: const CardOptions(terminalId: 'TOTEM100'),
            onCardPayment: (p) => approved = p,
            onSuccess: (_) => succeeded = true,
            onCancel: () => cancelled = true,
          ),
        );
        await tester.tap(find.text('Pagar 150.00'));
        await settle(tester);
        await chooseCard(tester);

        await tester.tap(find.byTooltip('Cerrar'));
        await settle(tester);
        expect(find.text('Sigue las instrucciones del POS'), findsOneWidget);
        expect(cancelled, isFalse);

        sale.complete(FakeResponse(200, _bridgeSale()));
        await settle(tester);
        await tester.pump(const Duration(milliseconds: 200));
        await settle(tester);

        expect(approved?.authCode, '575849');
        expect(succeeded, isFalse);
        expect(cancelled, isFalse);
        expect(find.text('¡Pago aprobado!'), findsNothing);
      });

      testWidgets('PaymentSheet.show resolves paid with the card payment',
          (tester) async {
        PaymentSheetResult? result;
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
                      card: const CardOptions(terminalId: 'TOTEM100'),
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
        await chooseCard(tester);
        expect(find.text('¡Pago aprobado!'), findsOneWidget);

        // Closing before the success delay is still paid.
        await tester.tap(find.byTooltip('Cerrar'));
        await settle(tester);

        expect(result?.status, PaymentSheetStatus.paid);
        expect(result?.isPaid, isTrue);
        expect(result?.payment, isNull);
        expect(result?.cardPayment?.authCode, '575849');
        expect(result?.method?.isCard, isTrue);
      });

      testWidgets('V2 offers card only with card options', (tester) async {
        await pumpApp(
          tester,
          PaymentFlow(
            version: PaymentVersion.v2,
            payments: payments,
            amount: 150,
            orderId: 'ORD-1',
            card: const CardOptions(terminalId: 'TOTEM100'),
            onCardPayment: (_) {},
          ),
        );

        expect(find.text('Tarjeta'), findsOneWidget);
      });
    });
  });
}

/// Answers every request with [body] and the given Content-Type, like a POS
/// that sends JSON as text.
class _TextAdapter implements HttpClientAdapter {
  _TextAdapter(this.body, this.contentType);

  final String body;
  final String contentType;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async =>
      ResponseBody.fromString(body, 200, headers: {
        Headers.contentTypeHeader: [contentType],
      });

  @override
  void close({bool force = false}) {}
}
