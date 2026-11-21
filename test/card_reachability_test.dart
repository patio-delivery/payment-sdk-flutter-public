import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:payment_sdk_flutter/payment_sdk_flutter.dart';

/// `isReachable` against real sockets on loopback: what a POS does on the
/// network, not what a fake adapter says.
void main() {
  late ServerSocket server;

  tearDown(() async => server.close());

  Future<int> serve(void Function(Socket) onClient) async {
    server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(onClient);
    return server.port;
  }

  group('BancardDirectTerminal.isReachable', () {
    test('a POS that only answers /sale (closes on anything else) is there',
        () async {
      // Like Linkser's POS: accepts the connection and closes it without
      // an HTTP answer ("Empty reply from server").
      final port = await serve((client) => client.destroy());
      final terminal = BancardDirectTerminal(posIp: '127.0.0.1', posPort: port);

      expect(await terminal.isReachable(), isTrue);
      terminal.close();
    });

    test('a POS that answers any HTTP status is there', () async {
      final port = await serve((client) {
        client
          ..write('HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n'
              'Connection: close\r\n\r\n')
          ..close();
      });
      final terminal = BancardDirectTerminal(posIp: '127.0.0.1', posPort: port);

      expect(await terminal.isReachable(), isTrue);
      terminal.close();
    });

    test('a POS that accepts but never answers is there (busy)', () async {
      final clients = <Socket>[];
      final port = await serve(clients.add);
      final terminal = BancardDirectTerminal(posIp: '127.0.0.1', posPort: port);

      expect(await terminal.isReachable(), isTrue);
      terminal.close();
      for (final client in clients) {
        client.destroy();
      }
    });

    test('nothing listening on the port: not there', () async {
      final port = await serve((_) {});
      await server.close();
      final terminal = BancardDirectTerminal(posIp: '127.0.0.1', posPort: port);

      expect(await terminal.isReachable(), isFalse);
      terminal.close();
    });
  });
}
