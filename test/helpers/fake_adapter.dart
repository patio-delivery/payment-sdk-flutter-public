import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// 1x1 PNG, Base64 encoded — the format the backend returns in `imageQR`.
const tinyPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';

/// A canned HTTP response.
class FakeResponse {
  const FakeResponse(this.statusCode, this.body);

  /// `{ ok: true, message: 'OK', data: ... }`, as the backend wraps successes.
  factory FakeResponse.ok(Map<String, dynamic> data, {int statusCode = 200}) =>
      FakeResponse(statusCode, {'data': data, 'ok': true, 'message': 'OK'});

  /// NestJS error body.
  factory FakeResponse.error(int statusCode, Object message) => FakeResponse(
        statusCode,
        {'statusCode': statusCode, 'message': message, 'error': 'Error'},
      );

  final int statusCode;
  final Object? body;
}

typedef FakeHandler = FutureOr<FakeResponse> Function(RequestOptions request);

/// Records every request and answers it with [handler]. Throwing a
/// [DioException] from the handler simulates transport failures.
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.handler);

  FakeHandler handler;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final response = await handler(options);
    final body = response.body;
    return ResponseBody.fromString(
      body is String ? body : jsonEncode(body),
      response.statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

DioException transportError(RequestOptions request, DioExceptionType type) =>
    DioException(requestOptions: request, type: type, message: type.name);
