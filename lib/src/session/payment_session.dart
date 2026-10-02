import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

import '../core/payment_sdk.dart';
import '../exceptions/payment_sdk_exception.dart';
import '../models/payment_status.dart';
import '../models/qr_payment.dart';

/// Where a [PaymentSession] is.
enum PaymentPhase {
  idle,
  creating,
  waiting,
  confirming,
  paid,
  failed,
  expired,
  error
}

/// The lifecycle of one QR payment, without UI: generate the QR, count down,
/// watch its status, confirm on request, verify before leaving and at the
/// end. Every SDK payment view renders one of these.
///
/// Callbacks are plain fields so the owning widget can refresh them when it
/// is rebuilt.
class PaymentSession extends ChangeNotifier {
  PaymentSession({
    required this.payments,
    required String orderId,
    required this.amount,
    this.description = '',
    this.qrTimeout = const Duration(minutes: 5),
    this.confirmTimeout = const Duration(seconds: 20),
    this.pollInterval = const Duration(seconds: 3),
    this.onSuccess,
    this.onError,
    this.onStatusChanged,
    this.onTimeout,
  }) : _orderId = orderId;

  static const confirmInterval = Duration(seconds: 2);
  static const timeoutExitDelay = Duration(seconds: 4);
  static const noticeDuration = Duration(seconds: 8);

  final PaymentSdk payments;

  // Read when each QR is generated, so the owning widget can update them.
  num amount;
  String description;
  Duration qrTimeout;
  Duration confirmTimeout;
  Duration pollInterval;

  ValueChanged<QrPayment>? onSuccess;
  ValueChanged<PaymentSdkException>? onError;
  ValueChanged<PaymentStatus>? onStatusChanged;

  /// Called [timeoutExitDelay] after the QR expires unpaid.
  VoidCallback? onTimeout;

  String _orderId;
  PaymentPhase _phase = PaymentPhase.idle;
  QrPayment? _payment;
  PaymentStatus? _lastStatus;
  PaymentSdkException? _error;
  DateTime? _expiresAt;
  bool _expiryPending = false;
  bool _showNotPaid = false;
  bool _disposed = false;

  StreamSubscription<PaymentStatus>? _watch;
  Timer? _ticker;
  Timer? _noticeTimer;
  Timer? _exitTimer;

  /// Updates what the owning widget may change between builds. Values are
  /// read when each QR is generated.
  void configure({
    required num amount,
    required String description,
    required Duration qrTimeout,
    required Duration confirmTimeout,
    required Duration pollInterval,
    ValueChanged<QrPayment>? onSuccess,
    ValueChanged<PaymentSdkException>? onError,
    ValueChanged<PaymentStatus>? onStatusChanged,
    VoidCallback? onTimeout,
  }) {
    this.amount = amount;
    this.description = description;
    this.qrTimeout = qrTimeout;
    this.confirmTimeout = confirmTimeout;
    this.pollInterval = pollInterval;
    this.onSuccess = onSuccess;
    this.onError = onError;
    this.onStatusChanged = onStatusChanged;
    this.onTimeout = onTimeout;
  }

  String get orderId => _orderId;
  PaymentPhase get phase => _phase;
  QrPayment? get payment => _payment;
  PaymentSdkException? get error => _error;

  /// Whether to show the "payment not received yet" notice.
  bool get showNotPaid => _showNotPaid;

  Duration get remaining {
    final left = _expiresAt?.difference(clock.now()) ?? Duration.zero;
    return left.isNegative ? Duration.zero : left;
  }

  /// Generates the QR and starts the countdown and the status watch. Pass
  /// [orderId] to start over with a new order.
  Future<void> start({String? orderId}) async {
    if (orderId != null) _orderId = orderId;
    _stopAll();
    _phase = PaymentPhase.creating;
    _payment = null;
    _lastStatus = null;
    _error = null;
    _expiryPending = false;
    _showNotPaid = false;
    _notify();
    try {
      final payment = await payments.generateQr(
        orderId: _orderId,
        amount: amount,
        description: description,
        dueDate: clock.now().add(qrTimeout),
      );
      if (_disposed) return;
      _payment = payment;
      _expiresAt = clock.now().add(qrTimeout);
      _setPhase(PaymentPhase.waiting);
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
      _watch = payments
          .watchPaymentStatus(_orderId,
              interval: pollInterval, timeout: qrTimeout)
          .listen(_onStatus, onError: _onWatchError);
      _onStatus(payment.status);
    } on PaymentSdkException catch (e) {
      if (_disposed) return;
      _error = e;
      _setPhase(PaymentPhase.error);
      onError?.call(e);
    }
  }

  /// "Ya pagué": checks every [confirmInterval] for [confirmTimeout] while
  /// the background watch keeps running. Unpaid, it goes back to the QR with
  /// the time that was left and shows the not-paid notice.
  Future<void> confirmPayment() async {
    _noticeTimer?.cancel();
    _phase = PaymentPhase.confirming;
    _showNotPaid = false;
    _notify();
    final deadline = clock.now().add(confirmTimeout);
    while (!_disposed && _phase == PaymentPhase.confirming) {
      if (await _isPaid()) return _succeed();
      if (_disposed || _phase != PaymentPhase.confirming) return;
      if (!clock.now().add(confirmInterval).isBefore(deadline)) break;
      await Future<void>.delayed(confirmInterval);
    }
    if (_disposed || _phase != PaymentPhase.confirming) return;

    if (_expiryPending || remaining == Duration.zero) {
      _expiryPending = false;
      return _expire(verify: false);
    }
    _phase = PaymentPhase.waiting;
    _showNotPaid = true;
    _notify();
    _noticeTimer = Timer(noticeDuration, () {
      if (_disposed) return;
      _showNotPaid = false;
      _notify();
    });
  }

  /// Before leaving: while the QR is up, checks once whether it was paid.
  /// Resolves to true when it is safe to leave; to false when the payment
  /// was in fact made (the session then reports success).
  Future<bool> verifyBeforeLeaving() async {
    if (_phase == PaymentPhase.waiting) {
      _setPhase(PaymentPhase.confirming);
      await _watch?.cancel();
      _watch = null;
      if (await _isPaid()) {
        _succeed();
        return false;
      }
      if (_disposed) return false;
    }
    _stopAll();
    return true;
  }

  @override
  void dispose() {
    _disposed = true;
    _stopAll();
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _setPhase(PaymentPhase phase) {
    if (_disposed) return;
    _phase = phase;
    notifyListeners();
  }

  void _stopAll() {
    _watch?.cancel();
    _watch = null;
    _ticker?.cancel();
    _noticeTimer?.cancel();
    _exitTimer?.cancel();
  }

  void _onWatchError(Object error) {
    // The countdown, not the watch, decides when the QR is over.
    if (error is StatusWatchTimeoutException) return;
    if (error is PaymentSdkException) onError?.call(error);
  }

  void _onStatus(PaymentStatus status) {
    if (_disposed || status == _lastStatus) return;
    _lastStatus = status;
    onStatusChanged?.call(status);
    switch (status) {
      case PaymentStatus.paid:
        _succeed();
      case PaymentStatus.failed:
        _stopAll();
        _setPhase(PaymentPhase.failed);
      case PaymentStatus.expired:
        _expire(verify: false);
      case PaymentStatus.pending:
      case PaymentStatus.unknown:
        break;
    }
  }

  void _succeed() {
    if (_phase == PaymentPhase.paid) return;
    _stopAll();
    _setPhase(PaymentPhase.paid);
    if (_lastStatus != PaymentStatus.paid) {
      _lastStatus = PaymentStatus.paid;
      onStatusChanged?.call(PaymentStatus.paid);
    }
    onSuccess?.call(_payment!.copyWith(status: PaymentStatus.paid));
  }

  void _tick() {
    if (_disposed) return;
    if (remaining > Duration.zero) {
      notifyListeners();
      return;
    }
    _ticker?.cancel();
    if (_phase == PaymentPhase.confirming) {
      _expiryPending = true;
    } else if (_phase == PaymentPhase.waiting) {
      _expire();
    }
  }

  /// The QR is over. With [verify], one last check first: a payment made at
  /// the very end must still count.
  Future<void> _expire({bool verify = true}) async {
    await _watch?.cancel();
    _watch = null;
    if (verify) {
      _setPhase(PaymentPhase.confirming);
      if (await _isPaid()) return _succeed();
      if (_disposed) return;
    }
    _stopAll();
    _setPhase(PaymentPhase.expired);
    if (_lastStatus != PaymentStatus.expired) {
      _lastStatus = PaymentStatus.expired;
      onStatusChanged?.call(PaymentStatus.expired);
    }
    if (onTimeout case final onTimeout?) {
      _exitTimer = Timer(timeoutExitDelay, onTimeout);
    }
  }

  Future<bool> _isPaid() async {
    try {
      return await payments.getPaymentStatus(_orderId) == PaymentStatus.paid;
    } on PaymentSdkException catch (e) {
      onError?.call(e);
      return false;
    }
  }
}
