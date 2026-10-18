import '../../../../core/auth/access_policy.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/order_entities.dart';
import '../../domain/entities/order_inputs.dart';
import '../../domain/entities/order_payment.dart';
import '../../domain/policies/order_access_policy.dart';
import '../../domain/use_cases/order_use_cases.dart';
import 'order_controller.dart';

/// One payment intent per order, kept intact until its outcome is established.
class OrderSettlementController extends OrderController {
  OrderSettlementController({
    required super.session,
    required super.events,
    super.onAccessDenied,
    required this.id,
    required this.root,
    required this.beforeSend,
    required this.onApplied,
    required this.getOrder,
    required this.recordPayment,
    required this.completeOrder,
    this.markAllServed,
    required this.keys,
    this.externalBlocked,
    this.appliedSource,
    this.onCompleted,
  });

  final String id;
  final OrderDetail? Function() root;
  final void Function() beforeSend;
  final void Function(OrderDetail) onApplied;
  final GetOrderDetail getOrder;
  final RecordOrderPayment recordPayment;
  final CompleteOrder completeOrder;
  final MarkAllOrderItemsServed? markAllServed;
  final OrderKeyGenerator keys;
  final bool Function()? externalBlocked;
  final Object? Function()? appliedSource;
  final void Function(OrderDetail)? onCompleted;

  RecordOrderPaymentInput? _pending;
  String? _key;
  int? _baselineVersion;
  String? _currencyCode;
  bool _keyRejected = false;
  bool _paymentUnknown = false;
  bool _completeUnknown = false;
  bool _awaitingPaymentReadback = false;
  bool _working = false;
  bool _reviewLoaded = false;
  bool _reviewNeedsNewVersion = false;
  bool _completionAttempt = false;
  bool _servingAttempt = false;
  bool _servedBeforeCompletion = false;
  int _generation = 0;
  bool needsReview = false;
  Failure? failure;
  OrderPayment? payment;

  RecordOrderPaymentInput? get pending => _pending;
  int? get baselineVersion => _baselineVersion;
  bool get busy => events.pending(id);
  bool get uncertain => _paymentUnknown || _completeUnknown;
  bool get paymentOutcomeUnknown => _paymentUnknown;
  bool get completeOutcomeUnknown => _completeUnknown;
  bool get completionAttempt => _completionAttempt;
  bool get servingOutcomeUnknown => _completeUnknown && _servingAttempt;
  bool get servedBeforeCompletion => _servedBeforeCompletion;
  bool get paymentRecordedAwaitingRefresh => _awaitingPaymentReadback;
  bool get ownsMutationBlock =>
      _working || uncertain || _awaitingPaymentReadback || needsReview;
  bool get keyConflict => _keyRejected;
  bool get authorityPayment =>
      current && AccessPolicy.canRecordOrderPayment(session());
  bool get authorityComplete {
    final target = root();
    return current &&
        target != null &&
        AccessPolicy.canCompleteOrder(
          session(),
          takeaway: target.summary.serviceType == ServiceType.takeaway,
        );
  }

  bool get _canRead => current && can('ORDER_VIEW');
  bool get _blocked => externalBlocked?.call() == true;
  bool get _fresh =>
      !busy && !ownsMutationBlock && !_blocked && !events.unresolved(id);
  bool get canPay {
    final target = root();
    return _fresh &&
        payment == null &&
        target != null &&
        OrderAccessPolicy.canPay(target, authorityPayment);
  }

  bool get canComplete {
    final target = root();
    return _fresh &&
        target != null &&
        OrderAccessPolicy.canComplete(target, authorityComplete);
  }

  bool get canServeAndComplete {
    final target = root();
    return _fresh &&
        markAllServed != null &&
        target != null &&
        can('ORDER_MARK_SERVED') &&
        OrderAccessPolicy.canServeAndComplete(target, authorityComplete);
  }

  bool get canBeginCompletion => canComplete || canServeAndComplete;

  bool get canRetryPayment =>
      current &&
      authorityPayment &&
      !busy &&
      !_blocked &&
      _paymentUnknown &&
      !_awaitingPaymentReadback &&
      !keyConflict &&
      _pending != null &&
      _key != null;

  Future<Result<OrderDetail>> pay(
    OrderDetail baseline,
    OrderPaymentMethod method, {
    String? referenceNo,
  }) async {
    if (!canPay) return const Error(OrderController.denied);
    if (!_sameBaseline(baseline)) return _stale(baseline.version);
    final input = RecordOrderPaymentInput(
      expectedOrderVersion: baseline.version,
      paymentMethod: method,
      amount: baseline.summary.totalAmount,
      referenceNo: referenceNo?.trim(),
    );
    if (input.validationErrors.isNotEmpty) {
      failure = OrderController.invalid(input.validationErrors);
      changed();
      return Error(failure!);
    }
    _pending = input;
    _completionAttempt = false;
    _baselineVersion = baseline.version;
    _currencyCode = baseline.summary.currencyCode;
    _keyRejected = false;
    _key = keys.next();
    return _sendPayment();
  }

  Future<Result<OrderDetail>> retryPayment() async {
    // A replay uses the original version and amount, even if the visible order
    // has changed. A new intent could otherwise charge the same order twice.
    if (!canRetryPayment) return const Error(OrderController.denied);
    return _sendPayment();
  }

  Future<Result<OrderDetail>> _sendPayment() async {
    if (!authorityPayment || _blocked || !events.lock(id)) {
      return const Error(OrderController.busyFailure);
    }
    final generation = _begin();
    final previouslyUnknown = _paymentUnknown;
    try {
      final response = await recordPayment(id, _pending!, _key!);
      if (!_valid(generation) || !authorityPayment) {
        return const Error(OrderController.denied);
      }
      switch (response) {
        case Success(value: final receipt):
          if (!_matchesReceipt(receipt)) {
            return _unknownPayment(_invalidResponse, previouslyUnknown);
          }
          payment = receipt;
          _paymentUnknown = false;
          _awaitingPaymentReadback = true;
          needsReview = false;
          events.markUnresolved(id, true);
          changed();
          return await _read(generation);
        case Error(failure: final error):
          await report(error);
          if (!_valid(generation)) return const Error(OrderController.denied);
          return _unknownPayment(error, previouslyUnknown);
      }
    } catch (_) {
      if (!_valid(generation)) return const Error(OrderController.denied);
      if (_awaitingPaymentReadback) {
        failure = _invalidResponse;
        return const Error(_invalidResponse);
      }
      return _unknownPayment(_invalidResponse, previouslyUnknown);
    } finally {
      _finish();
    }
  }

  bool _matchesReceipt(OrderPayment receipt) =>
      receipt.orderId == id &&
      receipt.successful &&
      receipt.amount == _pending!.amount &&
      receipt.paymentMethod == _pending!.paymentMethod &&
      receipt.currencyCode == _currencyCode;

  Result<OrderDetail> _unknownPayment(Failure error, bool previouslyUnknown) {
    failure = error;
    _keyRejected =
        _keyRejected ||
        const {
          'PAYMENT_IDEMPOTENCY_KEY_REUSED',
          'IDEMPOTENCY_KEY_REUSED',
        }.contains(error.code);
    _paymentUnknown = _unknown(error, previouslyUnknown);
    needsReview =
        !_paymentUnknown &&
        const {FailureType.conflict, FailureType.notFound}.contains(error.type);
    _reviewLoaded = false;
    _reviewNeedsNewVersion = error.code == 'CONCURRENT_ORDER_UPDATE';
    if (!_paymentUnknown) {
      _pending = null;
      _key = null;
    }
    events.markUnresolved(id, _paymentUnknown || needsReview);
    changed();
    return Error(error);
  }

  Future<Result<OrderDetail>> serveAllAndComplete(OrderDetail baseline) =>
      complete(baseline, serveAllFirst: true);

  Future<Result<OrderDetail>> complete(
    OrderDetail baseline, {
    bool serveAllFirst = false,
  }) async {
    if (!(serveAllFirst ? canBeginCompletion : canComplete)) {
      return const Error(OrderController.denied);
    }
    _completionAttempt = true;
    if (!_sameBaseline(baseline)) return _stale(baseline.version);
    if (!events.lock(id)) return const Error(OrderController.busyFailure);
    _baselineVersion = baseline.version;
    _servedBeforeCompletion = false;
    _servingAttempt = false;
    final generation = _begin();
    try {
      var latest = baseline;
      if (serveAllFirst &&
          latest.items.any(
            (line) =>
                line.status != OrderItemStatus.cancelled &&
                line.status != OrderItemStatus.served,
          )) {
        if (!can('ORDER_MARK_SERVED') || markAllServed == null) {
          return const Error(OrderController.denied);
        }
        _servingAttempt = true;
        final served = await markAllServed!(id, latest.version);
        if (!_valid(generation) ||
            !authorityComplete ||
            !can('ORDER_MARK_SERVED')) {
          return const Error(OrderController.denied);
        }
        switch (served) {
          case Error(failure: final error):
            await report(error);
            if (!_valid(generation)) return const Error(OrderController.denied);
            return _completionFailure(error);
          case Success(value: final value):
            final expectedIds = baseline.items.map((line) => line.id).toSet();
            final cancelledIds = baseline.items
                .where((line) => line.status == OrderItemStatus.cancelled)
                .map((line) => line.id)
                .toSet();
            if (value.id != id ||
                value.version <= latest.version ||
                value.version < (root()?.version ?? 0) ||
                value.summary.totalAmount != baseline.summary.totalAmount ||
                value.summary.currencyCode != baseline.summary.currencyCode ||
                value.summary.tableSessionId !=
                    baseline.summary.tableSessionId ||
                value.summary.serviceType != baseline.summary.serviceType ||
                value.items.length != expectedIds.length ||
                !value.items.every((line) => expectedIds.contains(line.id)) ||
                value.items.any(
                  (line) =>
                      cancelledIds.contains(line.id) &&
                      line.status != OrderItemStatus.cancelled,
                ) ||
                !OrderAccessPolicy.canComplete(value, true)) {
              return _completionFailure(_invalidResponse);
            }
            latest = value;
            _servedBeforeCompletion = true;
            _servingAttempt = false;
            _baselineVersion = latest.version;
            _apply(latest);
            changed();
        }
      }
      if (!_valid(generation) || !authorityComplete || _blocked) {
        return const Error(OrderController.denied);
      }
      final response = await completeOrder(id, latest.version);
      if (!_valid(generation) || !authorityComplete) {
        return const Error(OrderController.denied);
      }
      switch (response) {
        case Success(value: final order):
          if (order.id != id ||
              !_completed(order) ||
              order.version <= latest.version ||
              order.version < (root()?.version ?? 0)) {
            return _completionFailure(_invalidResponse);
          }
          _resolve();
          _apply(order);
          return Success(order);
        case Error(failure: final error):
          await report(error);
          if (!_valid(generation)) return const Error(OrderController.denied);
          return _completionFailure(error);
      }
    } catch (_) {
      if (!_valid(generation)) return const Error(OrderController.denied);
      return _completionFailure(_invalidResponse);
    } finally {
      _finish();
    }
  }

  Result<OrderDetail> _completionFailure(Failure error) {
    failure = error;
    _completeUnknown = _unknown(error, _completeUnknown);
    needsReview =
        !_completeUnknown &&
        const {FailureType.conflict, FailureType.notFound}.contains(error.type);
    _reviewLoaded = false;
    _reviewNeedsNewVersion = error.code == 'CONCURRENT_ORDER_UPDATE';
    events.markUnresolved(id, _completeUnknown || needsReview);
    changed();
    return Error(error);
  }

  /// Reads directly while holding the order lock: the detail controller's
  /// ordinary load intentionally skips reads while an order mutation is busy.
  Future<Result<OrderDetail>> refresh() async {
    if (!_canRead) return const Error(OrderController.denied);
    if (!events.lock(id)) return const Error(OrderController.busyFailure);
    final generation = _begin();
    try {
      return await _read(generation);
    } catch (_) {
      if (!_valid(generation)) return const Error(OrderController.denied);
      failure = _invalidResponse;
      return const Error(_invalidResponse);
    } finally {
      _finish();
    }
  }

  Future<Result<OrderDetail>> check() => refresh();

  Future<Result<OrderDetail>> _read(int generation) async {
    if (!_canRead) {
      failure = const Failure(
        type: FailureType.forbidden,
        code: 'ORDER_VIEW_REQUIRED',
        message:
            'Đã ghi nhận kết quả. Cần quyền xem đơn để xác minh trạng thái mới.',
      );
      return Error(failure!);
    }
    final response = await getOrder(id);
    if (!_valid(generation) || !_canRead) {
      return const Error(OrderController.denied);
    }
    switch (response) {
      case Error(failure: final error):
        failure = error;
        await report(error);
        return _valid(generation)
            ? Error(error)
            : const Error(OrderController.denied);
      case Success(value: final order):
        if (order.id != id ||
            order.version < (_baselineVersion ?? 0) ||
            order.version < (root()?.version ?? 0) ||
            (order.summary.status == OrderStatus.completed &&
                !_completed(order))) {
          failure = _invalidResponse;
          return const Error(_invalidResponse);
        }
        if (_paymentUnknown && !_awaitingPaymentReadback) {
          // GET can show that somebody has paid, but cannot identify which
          // payment intent succeeded. Keep the exact key until POST replay
          // returns its receipt; never turn this into a new charge.
          _apply(order);
          failure = const Failure(
            type: FailureType.conflict,
            code: 'PAYMENT_AWAITING_VERIFICATION',
            message:
                'Đã tải lại đơn. Cần kiểm tra lại đúng yêu cầu thanh toán ban đầu để xác nhận kết quả.',
          );
          return Error(failure!);
        }
        if (_awaitingPaymentReadback) {
          if (!_fullyPaid(order) ||
              order.summary.totalAmount != _pending?.amount ||
              order.summary.currencyCode != _currencyCode ||
              order.version <= _pending!.expectedOrderVersion) {
            failure = const Failure(
              type: FailureType.conflict,
              code: 'PAYMENT_AWAITING_VERIFICATION',
              message:
                  'Chưa xác minh được thanh toán trên đơn. Hãy kiểm tra lại; không tạo lần thanh toán mới.',
            );
            return Error(failure!);
          }
          _resolve();
        } else if (_completeUnknown) {
          if (order.summary.status == OrderStatus.completed) {
            if (!_completed(order) ||
                order.version <= (_baselineVersion ?? order.version)) {
              failure = _invalidResponse;
              return const Error(_invalidResponse);
            }
            _resolve();
          } else {
            // A fresh completion, if requested explicitly after review, still
            // carries the optimistic version and cannot complete twice.
            _completeUnknown = false;
            needsReview = true;
            _reviewLoaded = true;
            _reviewNeedsNewVersion = false;
            failure = null;
          }
        } else if (needsReview) {
          _reviewLoaded = true;
          failure = null;
          if (order.summary.status == OrderStatus.completed ||
              order.summary.status == OrderStatus.cancelled) {
            _resolve();
          }
        } else {
          failure = null;
        }
        _apply(order);
        return Success(order);
    }
  }

  bool get canReviewCurrent {
    final order = root();
    return current &&
        _canRead &&
        !busy &&
        !uncertain &&
        !_awaitingPaymentReadback &&
        needsReview &&
        _reviewLoaded &&
        order != null &&
        (!_reviewNeedsNewVersion ||
            order.version > (_baselineVersion ?? order.version));
  }

  /// Only a user's explicit acknowledgement can replace a refused baseline.
  bool reviewCurrent() {
    if (!canReviewCurrent) return false;
    final order = root()!;
    needsReview = false;
    _reviewLoaded = false;
    _reviewNeedsNewVersion = false;
    _baselineVersion = order.version;
    _completionAttempt = false;
    _servingAttempt = false;
    _servedBeforeCompletion = false;
    failure = null;
    events.markUnresolved(id, false);
    changed();
    return true;
  }

  bool _sameBaseline(OrderDetail baseline) =>
      baseline.id == id &&
      root()?.id == id &&
      root()?.version == baseline.version &&
      root()?.summary.totalAmount == baseline.summary.totalAmount &&
      root()?.summary.paymentStatus == baseline.summary.paymentStatus;

  Result<OrderDetail> _stale(int version) {
    _baselineVersion = version;
    needsReview = true;
    _reviewLoaded = false;
    _reviewNeedsNewVersion = true;
    failure = const Failure(
      type: FailureType.conflict,
      code: 'CONCURRENT_ORDER_UPDATE',
      message:
          'Đơn đã thay đổi. Hãy tải lại, đối chiếu rồi mở lại thao tác với dữ liệu mới.',
    );
    events.markUnresolved(id, true);
    changed();
    return Error(failure!);
  }

  int _begin() {
    _working = true;
    beforeSend();
    failure = null;
    changed();
    return ++_generation;
  }

  bool _valid(int generation) => current && generation == _generation;

  void _finish() {
    _working = false;
    // Scoped providers may already have disposed the old event bus.
    if (current) events.unlock(id);
    changed();
  }

  void _resolve() {
    _pending = null;
    _key = null;
    _paymentUnknown = false;
    _completeUnknown = false;
    _awaitingPaymentReadback = false;
    _currencyCode = null;
    _keyRejected = false;
    _completionAttempt = false;
    _servingAttempt = false;
    _servedBeforeCompletion = false;
    needsReview = false;
    _reviewLoaded = false;
    _reviewNeedsNewVersion = false;
    failure = null;
    events.markUnresolved(id, false);
  }

  void _apply(OrderDetail order) {
    onApplied(order);
    events.emit(
      order.id,
      order.summary.tableSessionId,
      source: appliedSource?.call(),
    );
    if (order.summary.status == OrderStatus.completed) onCompleted?.call(order);
  }

  static bool _fullyPaid(OrderDetail order) =>
      order.summary.paymentStatus == OrderPaymentStatus.paid &&
      order.summary.totalAmount.minorUnits > 0 &&
      order.summary.paidAmount == order.summary.totalAmount;

  static bool _completed(OrderDetail order) {
    final live = order.items.where(
      (line) => line.status != OrderItemStatus.cancelled,
    );
    return order.summary.status == OrderStatus.completed &&
        order.completedAt != null &&
        _fullyPaid(order) &&
        live.isNotEmpty &&
        live.every((line) => line.status == OrderItemStatus.served);
  }

  static bool _unknown(Failure error, bool previous) =>
      error.isNetwork ||
      error.type == FailureType.internal ||
      const {
        'PAYMENT_IDEMPOTENCY_KEY_REUSED',
        'IDEMPOTENCY_KEY_REUSED',
      }.contains(error.code) ||
      (previous &&
          const {
            FailureType.unauthorized,
            FailureType.forbidden,
            FailureType.featureNotEntitled,
            FailureType.subscriptionNotActive,
            FailureType.restaurantInactive,
          }.contains(error.type));

  static const _invalidResponse = Failure(
    type: FailureType.internal,
    code: 'INVALID_SETTLEMENT_RESPONSE',
    message:
        'Chưa xác minh được kết quả thao tác. Hãy kiểm tra lại đơn trước khi tiếp tục.',
  );

  @override
  void dispose() {
    ++_generation;
    _pending = null;
    _key = null;
    payment = null;
    super.dispose();
  }
}
