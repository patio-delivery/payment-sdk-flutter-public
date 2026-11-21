import '../models/payment_status.dart';

/// Base type of every error the SDK throws. Sealed, so it can be switched on
/// exhaustively.
sealed class PaymentSdkException implements Exception {
  const PaymentSdkException(
    this.message, {
    this.statusCode,
    this.details,
    this.cause,
  });

  /// The backend's own message when there is one.
  final String message;

  /// HTTP status code, when the error came from a response.
  final int? statusCode;

  /// Raw response body, when there is one.
  final Object? details;

  /// Wrapped error, when there is one.
  final Object? cause;

  /// Whether the same call can succeed later. Status polling keeps going only
  /// after retryable errors.
  bool get isRetryable => false;

  @override
  String toString() {
    final code = statusCode == null ? '' : ' ($statusCode)';
    return '$runtimeType$code: $message';
  }
}

/// The backend could not be reached.
class NetworkException extends PaymentSdkException {
  const NetworkException(super.message, {super.cause});

  @override
  bool get isRetryable => true;
}

/// A request exceeded `PaymentSdkConfig.timeout`.
class RequestTimeoutException extends NetworkException {
  const RequestTimeoutException(super.message, {super.cause});
}

/// Missing, invalid or unauthorized API key (HTTP 401/403).
class AuthenticationException extends PaymentSdkException {
  const AuthenticationException(super.message,
      {super.statusCode, super.details});
}

/// Invalid request data (HTTP 400/422, or rejected before sending).
class ValidationException extends PaymentSdkException {
  const ValidationException(
    super.message, {
    this.errors = const [],
    super.statusCode,
    super.details,
  });

  final List<String> errors;
}

/// The payment does not exist for this account (HTTP 404).
class PaymentNotFoundException extends PaymentSdkException {
  const PaymentNotFoundException(
    super.message, {
    super.statusCode,
    super.details,
  });
}

/// The payment provider behind the backend failed (HTTP 503).
class ProviderException extends PaymentSdkException {
  const ProviderException(super.message, {super.statusCode, super.details});

  @override
  bool get isRetryable => true;
}

/// Too many requests (HTTP 429).
class RateLimitException extends PaymentSdkException {
  const RateLimitException(super.message, {super.statusCode, super.details});

  @override
  bool get isRetryable => true;
}

/// Any other backend failure or unexpected response.
class BackendException extends PaymentSdkException {
  const BackendException(super.message, {super.statusCode, super.details});

  @override
  bool get isRetryable => (statusCode ?? 0) >= 500;
}

/// Status polling hit its time limit before a final status.
class StatusWatchTimeoutException extends PaymentSdkException {
  const StatusWatchTimeoutException(super.message, {this.lastStatus});

  final PaymentStatus? lastStatus;
}

/// The card terminal failed: the POS, or the local service in front of it
/// (totem_bancard_pos), could not be reached or answered something
/// unreadable.
class CardTerminalException extends PaymentSdkException {
  const CardTerminalException(
    super.message, {
    required this.outcomeUnknown,
    super.statusCode,
    super.details,
    super.cause,
  });

  /// True when the sale may have reached the POS, so the customer may have
  /// been charged: never charge again without checking the POS's receipts.
  /// False when the POS was never reached, and charging again is safe.
  final bool outcomeUnknown;

  @override
  bool get isRetryable => !outcomeUnknown;
}
