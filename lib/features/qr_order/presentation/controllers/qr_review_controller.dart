import 'dart:async';
import '../../../../core/auth/access_policy.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../../order/presentation/controllers/order_controller.dart';
import '../../../order/domain/entities/order_entities.dart';
import '../../../tables/presentation/controllers/table_events.dart';
import '../../domain/entities/qr_request.dart';
import '../../domain/use_cases/qr_request_use_cases.dart';

class QrReviewController extends OrderController {
  QrReviewController({
    required super.session,
    required super.events,
    super.onAccessDenied,
    required this.id,
    required this.getReview,
    required this.approveRequest,
    required this.rejectRequest,
    required this.tableEvents,
    required this.onResolved,
    this.beforeApprove,
    this.onApproved,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;
  final String id;
  final GetQrRequestReview getReview;
  final ApproveQrRequest approveRequest;
  final RejectQrRequest rejectRequest;
  final TableEvents tableEvents;
  final void Function(QrRequest) onResolved;
  final void Function(String)? beforeApprove;
  final void Function(QrApproval)? onApproved;
  final DateTime Function() clock;
  QrRequestReview? review;
  Failure? failure;
  bool loading = false, busy = false, uncertain = false, needsReload = false;
  bool resolved = false;
  DateTime? retryAt;
  Timer? _cooldownTimer, _expiryTimer;
  int _generation = 0;
  Future<void>? _reading;
  bool _readAgain = false;
  String? _lockedOrder, _session;
  bool _ownsUnresolved = false;
  bool get coolingDown => retryAt?.isAfter(clock()) == true;
  bool get pending => review?.request.pendingAt(clock()) == true;
  bool get canReject =>
      can('ORDER_VIEW') &&
      can('ORDER_UPDATE') &&
      !busy &&
      !loading &&
      !uncertain &&
      !needsReload &&
      !resolved &&
      !coolingDown &&
      review?.request.status == QrRequestStatus.pending;
  bool get _localBlocked {
    final order = review?.context?.order?.id;
    final session = review?.context?.sessionId;
    return (order != null &&
            (events.pending(order) || events.unresolved(order))) ||
        tableEvents.sessionTransferBlocked(session) ||
        (session != null &&
            tableEvents.externalSessionBlocked(session, except: this));
  }

  bool get localBlocked => _localBlocked;
  bool get canApprove =>
      can('ORDER_VIEW') &&
      pending &&
      !busy &&
      !loading &&
      !uncertain &&
      !needsReload &&
      !resolved &&
      !coolingDown &&
      !_localBlocked &&
      review?.canApprove == true &&
      review?.hash != null &&
      review?.quote != null &&
      AccessPolicy.canApproveQrRequest(
        session(),
        takeaway: review!.request.entryType == QrEntryType.restaurant,
        opensSession:
            review!.request.entryType == QrEntryType.table &&
            review!.context?.sessionId == null,
      );

  /// Never invalidate a running command's generation or release its locks.
  void invalidate() {
    if (!can('ORDER_VIEW')) return;
    needsReload = true;
    _readAgain = true;
    if (!busy) ++_generation;
    changed();
    if (!busy && !uncertain && !coolingDown) unawaited(load());
  }

  Future<void> load() {
    if (!can('ORDER_VIEW') || busy || coolingDown) return Future.value();
    if (_reading != null) {
      _readAgain = true;
      return _reading!;
    }
    final future = _readLoop().whenComplete(() => _reading = null);
    _reading = future;
    return future;
  }

  Future<void> _readLoop() async {
    do {
      _readAgain = false;
      await _load();
    } while (_readAgain && can('ORDER_VIEW') && !busy && !coolingDown);
  }

  Future<void> _load() async {
    if (!can('ORDER_VIEW') || busy || coolingDown) return;
    final generation = ++_generation;
    loading = true;
    changed();
    final result = await invoke('ORDER_VIEW', () => getReview(id));
    if (!current || generation != _generation) return;
    switch (result) {
      case Success(value: final value):
        if (value.request.id != id) {
          failure = _invalid;
          break;
        }
        review = value;
        resolved = value.request.status != QrRequestStatus.pending;
        failure = null;
        uncertain = false;
        needsReload = false;
        retryAt = null;
        _cooldownTimer?.cancel();
        _expiryTimer?.cancel();
        final remaining = value.request.expiresAt.difference(clock());
        if (value.request.status == QrRequestStatus.pending &&
            remaining > Duration.zero) {
          _expiryTimer = Timer(remaining, changed);
        }
        _release();
        if (value.request.status != QrRequestStatus.pending) {
          onResolved(value.request);
        }
      case Error(failure: final error):
        failure = error;
        if (error is QrCooldownFailure) _cooldown(error);
    }
    loading = false;
    changed();
  }

  Future<bool> approve(
    QrRequestReview baseline, {
    required bool confirmed,
  }) async {
    if (!confirmed || !identical(baseline, review) || !canApprove) return false;
    _lockedOrder = baseline.context?.order?.id;
    _session = baseline.context?.sessionId;
    if (_lockedOrder != null && !events.lock(_lockedOrder!)) {
      _lockedOrder = null;
      return false;
    }
    if (_lockedOrder != null) beforeApprove?.call(_lockedOrder!);
    busy = true;
    failure = null;
    tableEvents.markExternalSessionBlocked(this, _session, true);
    final generation = ++_generation;
    changed();
    try {
      final result = await approveRequest(
        id,
        ApproveQrRequestInput(
          baseline.request.version,
          baseline.hash!,
          baseline.context?.sessionId,
        ),
      );
      if (!current || generation != _generation || !can('ORDER_VIEW')) {
        return false;
      }
      switch (result) {
        case Success(value: final value):
          if (value.requestId != id ||
              value.version <= baseline.request.version ||
              value.order.id.isEmpty ||
              (baseline.request.entryType == QrEntryType.table &&
                  (value.order.summary.serviceType != ServiceType.dineIn ||
                      value.sessionId == null)) ||
              (baseline.context?.order != null &&
                  value.order.id != baseline.context!.order!.id) ||
              (baseline.context?.sessionId != null &&
                  value.sessionId != baseline.context!.sessionId) ||
              value.itemIds.length != baseline.request.items.length ||
              (baseline.context?.order != null &&
                  value.order.version <= baseline.context!.order!.version)) {
            _failed(_invalid);
            return false;
          }
          uncertain = false;
          needsReload = false;
          resolved = true;
          _release();
          onApproved?.call(value);
          events.emit(value.order.id, value.sessionId);
          tableEvents.emit(
            TableChange(
              TableChangeKind.refresh,
              baseline.request.tableId ?? '',
              sessionId: value.sessionId,
            ),
          );
          return true;
        case Error(failure: final error):
          await report(error);
          if (current) _failed(error);
          return false;
      }
    } catch (_) {
      if (current) _failed(_invalid);
      return false;
    } finally {
      busy = false;
      if (current) {
        if (_lockedOrder != null) events.unlock(_lockedOrder!);
        if (!uncertain) _release();
      }
      changed();
      if (_readAgain && current && !uncertain) unawaited(load());
    }
  }

  Future<bool> reject(QrRequestReview baseline, String reason) async {
    if (!identical(baseline, review) || !canReject) return false;
    final text = reason.trim();
    if (text.isEmpty || text.length > 1000) {
      failure = OrderController.invalid({
        'reason': 'Nhập lý do từ chối từ 1 đến 1000 ký tự.',
      });
      changed();
      return false;
    }
    busy = true;
    failure = null;
    final generation = ++_generation;
    changed();
    try {
      final result = await rejectRequest(id, baseline.request.version, text);
      if (!current || generation != _generation) return false;
      switch (result) {
        case Success(value: final value):
          if (value.id != id || value.status != QrRequestStatus.rejected) {
            _failed(_invalid);
            return false;
          }
          uncertain = false;
          needsReload = false;
          resolved = true;
          onResolved(value);
          return true;
        case Error(failure: final error):
          await report(error);
          if (current) _failed(error);
          return false;
      }
    } catch (_) {
      if (current) _failed(_invalid);
      return false;
    } finally {
      busy = false;
      changed();
      if (_readAgain && current && !uncertain) unawaited(load());
    }
  }

  void _failed(Failure error) {
    failure = error;
    needsReload = true;
    uncertain = error.isNetwork || error.type == FailureType.internal;
    if (error is QrCooldownFailure) {
      uncertain = false;
      _cooldown(error);
    }
    if (uncertain && _lockedOrder != null) {
      _ownsUnresolved = true;
      events.markUnresolved(_lockedOrder!, true);
    }
  }

  void _cooldown(QrCooldownFailure failure) {
    retryAt = clock().add(failure.retryAfter);
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer(failure.retryAfter, changed);
  }

  void stopVisibleTimers() {
    _expiryTimer?.cancel();
  }

  void _release() {
    if (!current) return;
    if (_lockedOrder != null) {
      events.unlock(_lockedOrder!);
      if (_ownsUnresolved) events.markUnresolved(_lockedOrder!, false);
    }
    _ownsUnresolved = false;
    _lockedOrder = null;
    tableEvents.markExternalSessionBlocked(this, null, false);
  }

  static const _invalid = Failure(
    type: FailureType.internal,
    code: 'INVALID_QR_RESPONSE',
    message:
        'Chưa xác minh được kết quả xử lý QR. Hãy tải lại yêu cầu trước khi tiếp tục.',
  );
  @override
  void dispose() {
    ++_generation;
    _cooldownTimer?.cancel();
    _expiryTimer?.cancel();
    if (current) _release();
    super.dispose();
  }
}
