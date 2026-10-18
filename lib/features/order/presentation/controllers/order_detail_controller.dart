import 'dart:async';
import '../../../../core/auth/access_policy.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/order_entities.dart';
import '../../domain/entities/order_item_action.dart';
import '../../domain/entities/order_inputs.dart';
import '../../domain/policies/order_access_policy.dart';
import '../../domain/policies/order_validation.dart';
import '../../domain/use_cases/order_use_cases.dart';
import 'order_controller.dart';

class OrderDetailController extends OrderController {
  OrderDetailController({
    required super.session,
    required super.events,
    super.onAccessDenied,
    required this.id,
    required this.get,
    required this.updateOrder,
    required this.add,
    required this.updateLine,
    required this.confirmOrder,
    required this.cancelLine,
    required this.cancelOrder,
    this.transitionOrderItem,
    this.externalBlocked,
  }) {
    events.addListener(_event);
  }
  final String id;
  final GetOrderDetail get;
  final UpdateOrder updateOrder;
  final AddOrderItems add;
  final UpdateOrderItem updateLine;
  final ConfirmOrder confirmOrder;
  final CancelOrderItem cancelLine;
  final CancelOrder cancelOrder;
  final TransitionOrderItem? transitionOrderItem;
  final bool Function()? externalBlocked;
  OrderDetail? order;
  Failure? failure;
  bool loading = false;
  bool _requiresVerification = false;
  bool _mutating = false;
  bool get ownsMutationBlock => _mutating || _requiresVerification;
  bool get requiresVerification =>
      _requiresVerification || events.unresolved(id);
  bool get needsLocalVerification => _requiresVerification;
  set requiresVerification(bool value) => _requiresVerification = value;
  int _generation = 0;
  int _eventRevision = 0;
  bool get busy => events.pending(id);
  bool get blocked => externalBlocked?.call() == true;
  bool get editable =>
      order != null &&
      !blocked &&
      !requiresVerification &&
      OrderAccessPolicy.canEdit(order!, can('ORDER_UPDATE'));
  bool get confirmable =>
      order != null &&
      !blocked &&
      !requiresVerification &&
      OrderAccessPolicy.canConfirm(order!, can('ORDER_UPDATE'));
  bool get cancellable =>
      order != null &&
      !blocked &&
      !requiresVerification &&
      OrderAccessPolicy.canCancel(order!, can('ORDER_CANCEL'));
  bool lineCancellable(OrderLine line) =>
      order != null &&
      !blocked &&
      !requiresVerification &&
      OrderAccessPolicy.canCancelLine(
        order!,
        line,
        can(OrderAccessPolicy.lineCancelPermission(order!)),
      );

  bool _canTransition(OrderItemAction action) =>
      current &&
      (action.kitchen
          ? AccessPolicy.canKitchen(session(), action.permission)
          : can(action.permission));

  bool lineTransitionable(OrderLine line, OrderItemAction action) =>
      transitionOrderItem != null &&
      order != null &&
      !loading &&
      !busy &&
      !blocked &&
      !requiresVerification &&
      OrderAccessPolicy.canTransitionLine(
        order!,
        line,
        action,
        _canTransition(action),
      );

  Future<Result<OrderDetail>> transitionLine(
    OrderLine baseline,
    OrderItemAction action,
    int version,
  ) {
    final line = order?.items.where((row) => row.id == baseline.id).firstOrNull;
    if (line == null || !lineTransitionable(line, action)) {
      return Future.value(const Error(OrderController.denied));
    }
    return _mutate(
      action.permission,
      version,
      () => transitionOrderItem!(id, baseline.id, version, action),
      allowed: () => _canTransition(action),
    );
  }

  void seed(OrderDetail value) {
    if (!current ||
        value.id != id ||
        (order != null && order!.version >= value.version)) {
      return;
    }
    order = value;
  }

  /// Invalidate in-flight GETs before an external append mutation starts.
  void beginSubmission() {
    ++_generation;
    loading = false;
  }

  void applySubmission(OrderDetail value) {
    if (!current || value.id != id) return;
    ++_generation;
    loading = false;
    if (order == null || value.version >= order!.version) order = value;
    failure = null;
    _requiresVerification = false;
    changed();
  }

  void _event() {
    if (_eventRevision == events.revision) return;
    if (identical(events.source, this)) {
      _eventRevision = events.revision;
      return;
    }
    if (events.changedId != id) {
      _eventRevision = events.revision;
      return;
    }
    if (busy) return;
    _eventRevision = events.revision;
    if (events.changedId == id &&
        !busy &&
        !requiresVerification &&
        can('ORDER_VIEW')) {
      unawaited(load());
    }
  }

  Future<void> load() async {
    if (!can('ORDER_VIEW') || busy) return;
    final g = ++_generation;
    loading = true;
    changed();
    final response = await invoke('ORDER_VIEW', () => get(id));
    if (!current || g != _generation) return;
    switch (response) {
      case Success(value: final value):
        if (order == null || value.version >= order!.version) order = value;
        failure = null;
        requiresVerification = false;
      case Error(failure: final f):
        failure = f;
        if (f.type == FailureType.notFound) {
          order = null;
          requiresVerification = true;
        }
    }
    loading = false;
    changed();
  }

  Future<Result<OrderDetail>> _mutate(
    String permission,
    int version,
    Future<Result<OrderDetail>> Function() call, {
    Map<String, String> errors = const {},
    bool Function()? allowed,
  }) async {
    bool authorized() => current && (allowed?.call() ?? can(permission));
    if (!authorized() || order == null) {
      return const Error(OrderController.denied);
    }
    if (busy || blocked || requiresVerification) {
      return Error(failure ?? OrderController.busyFailure);
    }
    if (version != order!.version) {
      failure = const Failure(
        type: FailureType.conflict,
        code: 'CONCURRENT_ORDER_UPDATE',
        message:
            'Đơn đã thay đổi so với bản đang sửa. Hãy kiểm tra dữ liệu mới và mở lại thao tác.',
      );
      changed();
      return Error(failure!);
    }
    if (errors.isNotEmpty) {
      failure = OrderController.invalid(errors);
      changed();
      return Error(failure!);
    }
    if (!events.lock(id)) return const Error(OrderController.busyFailure);
    _mutating = true;
    ++_generation;
    loading = false;
    changed();
    try {
      final response = await call();
      if (!authorized()) return const Error(OrderController.denied);
      if (response case Error(failure: final error)) await report(error);
      if (!authorized()) return const Error(OrderController.denied);
      switch (response) {
        case Success(value: final value):
          if (value.id != id || value.version < order!.version) {
            failure = const Failure(
              type: FailureType.internal,
              code: 'INVALID_ORDER_RESPONSE',
              message:
                  'Chưa xác minh được trạng thái đơn. Hãy tải lại để kiểm tra.',
            );
            requiresVerification = true;
            return Error(failure!);
          }
          order = value;
          failure = null;
          events.emit(value.id, value.summary.tableSessionId, source: this);
        case Error(failure: final f):
          failure = f;
          requiresVerification =
              f.isNetwork ||
              f.type == FailureType.internal ||
              f.type == FailureType.conflict ||
              f.type == FailureType.notFound;
      }
      return response;
    } finally {
      _mutating = false;
      if (current) events.unlock(id);
      changed();
    }
  }

  Future<Result<OrderDetail>> update(UpdateOrderInput input) {
    if (!editable) return Future.value(const Error(OrderController.denied));
    final errors = OrderValidation.fields(
      guestCount: input.guestCount,
      customerName: input.customerName,
      customerPhone: input.customerPhone,
      note: input.note,
    );
    if (input.isEmpty) errors['request'] = 'Chưa có thay đổi.';
    return _mutate(
      'ORDER_UPDATE',
      input.expectedVersion,
      () => updateOrder(id, input),
      errors: errors,
    );
  }

  Future<Result<OrderDetail>> addItems(
    int version,
    List<CreateOrderLine> items,
  ) => editable
      ? _mutate(
          'ORDER_UPDATE',
          version,
          () => add(id, version, items),
          errors: OrderValidation.lines(items),
        )
      : Future.value(const Error(OrderController.denied));
  Future<Result<OrderDetail>> editLine(
    String lineId,
    UpdateOrderLineInput input,
  ) {
    final line = order?.items.where((l) => l.id == lineId).firstOrNull;
    if (!editable || line?.status != OrderItemStatus.pending) {
      return Future.value(const Error(OrderController.denied));
    }
    final errors = <String, String>{};
    if (input.isEmpty) errors['request'] = 'Chưa có thay đổi.';
    final noteError = OrderValidation.text(input.note, 2000);
    if (noteError != null) errors['note'] = noteError;
    return _mutate(
      'ORDER_UPDATE',
      input.expectedVersion,
      () => updateLine(id, lineId, input),
      errors: errors,
    );
  }

  Future<Result<OrderDetail>> confirm(int version) => confirmable
      ? _mutate('ORDER_UPDATE', version, () => confirmOrder(id, version))
      : Future.value(const Error(OrderController.denied));
  Future<Result<OrderDetail>> cancel(int version, String reason) => cancellable
      ? _mutate(
          'ORDER_CANCEL',
          version,
          () => cancelOrder(id, version, reason),
          errors: _reason(reason),
        )
      : Future.value(const Error(OrderController.denied));
  Future<Result<OrderDetail>> cancelItem(
    String lineId,
    int version,
    String reason,
  ) {
    final line = order?.items.where((l) => l.id == lineId).firstOrNull;
    if (line == null || !lineCancellable(line)) {
      return Future.value(const Error(OrderController.denied));
    }
    return _mutate(
      OrderAccessPolicy.lineCancelPermission(order!),
      version,
      () => cancelLine(id, lineId, version, reason),
      errors: _reason(reason),
    );
  }

  Map<String, String> _reason(String reason) {
    final error = OrderValidation.text(reason, 1000, required: true);
    return error == null ? {} : {'reason': error};
  }

  @override
  void dispose() {
    ++_generation;
    events.removeListener(_event);
    order = null;
    super.dispose();
  }
}
