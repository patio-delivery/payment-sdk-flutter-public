import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config/payment_sdk_config.dart';
import '../exceptions/payment_sdk_exception.dart';

/// The only place the SDK makes HTTP calls. Returns the `data` of the
/// backend's `{ ok, message, data }` envelope and turns every failure into a
/// [PaymentSdkException].
class ApiClient {
  ApiClient(this.config, {HttpClientAdapter? httpClientAdapter})
      : _dio = Dio(
          BaseOptions(
            baseUrl: '${config.baseUrl}/',
            connectTimeout: config.timeout,
            sendTimeout: config.timeout,
            receiveTimeout: config.timeout,
            contentType: Headers.jsonContentType,
            headers: {
              Headers.acceptHeader: Headers.jsonContentType,
              'Authorization': 'Bearer ${config.apiKey}',
            },
          ),
        ) {
    if (httpClientAdapter != null) _dio.httpClientAdapter = httpClientAdapter;
    if (config.enableLogging) _dio.interceptors.add(_logger);
  }

  final PaymentSdkConfig config;
  final Dio _dio;

  Future<Map<String, dynamic>> get(String path) =>
      _send(() => _dio.get<Object?>(path));

  /// `GET` for endpoints whose `data` is a list.
  Future<List<dynamic>> getList(String path) =>
      _send(() => _dio.get<Object?>(path));

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) =>
      _send(() => _dio.post<Object?>(path, data: body));

  void close() => _dio.close(force: true);

  Future<T> _send<T>(Future<Response<Object?>> Function() request) async {
    final Response<Object?> response;
    try {
      response = await request();
    } on DioException catch (e) {
      throw _mapDioException(e);
    }

    final body = response.data;
    if (body is Map<String, dynamic> && body['ok'] == true) {
      final data = body['data'];
      if (data is T) return data;
    }
    final message = body is Map && body['ok'] == false
        ? '${body['message'] ?? 'Request failed'}'
        : 'Unexpected response format';
    throw BackendException(
      message,
      statusCode: response.statusCode,
      details: body,
    );
  }

  static PaymentSdkException _mapDioException(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return RequestTimeoutException(
          'The backend did not answer in time',
          cause: e,
        );
      case DioExceptionType.badResponse:
        return _fromResponse(e.response);
      default:
        return e.response != null
            ? _fromResponse(e.response)
            : NetworkException(
                'Could not reach the backend: ${e.message ?? e.error}',
                cause: e,
              );
    }
  }

  /// NestJS errors look like `{ statusCode, message: string | string[], error }`.
  static PaymentSdkException _fromResponse(Response<Object?>? response) {
    final status = response?.statusCode;
    final body = response?.data;
    final errors = _messages(body);
    final message = errors.isEmpty ? 'HTTP $status' : errors.join('; ');

    return switch (status) {
      400 || 422 => ValidationException(
          message,
          errors: errors,
          statusCode: status,
          details: body,
        ),
      401 ||
      403 =>
        AuthenticationException(message, statusCode: status, details: body),
      404 =>
        PaymentNotFoundException(message, statusCode: status, details: body),
      429 => RateLimitException(message, statusCode: status, details: body),
      503 => ProviderException(message, statusCode: status, details: body),
      _ => BackendException(message, statusCode: status, details: body),
    };
  }

  static List<String> _messages(Object? body) {
    if (body is! Map) return const [];
    final message = body['message'] ?? body['error'];
    if (message is List) return message.map((m) => '$m').toList();
    if (message is String && message.isNotEmpty) return [message];
    return const [];
  }

  /// Logs method, URL and status only: headers carry the API key.
  static final _logger = InterceptorsWrapper(
    onRequest: (options, handler) {
      debugPrint('[PaymentSdk] --> ${options.method} ${options.uri}');
      handler.next(options);
    },
    onResponse: (response, handler) {
      final request = response.requestOptions;
      debugPrint(
        '[PaymentSdk] <-- ${response.statusCode} ${request.method} ${request.uri}',
      );
      handler.next(response);
    },
    onError: (error, handler) {
      final request = error.requestOptions;
      final status = error.response?.statusCode ?? error.type.name;
      debugPrint('[PaymentSdk] <-- $status ${request.method} ${request.uri}');
      handler.next(error);
    },
  );
}
