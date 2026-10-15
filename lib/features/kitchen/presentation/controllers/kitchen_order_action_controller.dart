import 'dart:async';
import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../../order/domain/entities/order_entities.dart';
import '../../../order/presentation/controllers/order_events.dart';
import '../../domain/entities/kitchen_queue.dart';
import '../../domain/use_cases/kitchen_use_cases.dart';
import 'kitchen_controller.dart';
import 'kitchen_display_controller.dart';

class KitchenOrderActionState {
  final Object owner = Object();
  KitchenItemTransition? intent;
  String? sessionId;
  Failure? failure;
  OrderDetail? lastResponse;
  bool busy = false, uncertain = false, needsReview = false;
}

class KitchenOrderActionController extends KitchenController {
  KitchenOrderActionController({
    required super.session,
    super.onAccessDenied,
    required this.transition,
    required this.display,
    required this.events,
    this.externalBlocked,
    this.onSessionBlocked,
  });
  final TransitionKitchenItem transition;
  final KitchenDisplayController display;
  final OrderEvents events;
  final bool Function(String? sessionId, Object owner)? externalBlocked;
  final void Function(Object owner, String? sessionId, bool blocked)?
  onSessionBlocked;
  final Map<String, KitchenOrderActionState> _states = {};
  Map<String, KitchenOrderActionState> get states => Map.unmodifiable(_states);
  KitchenOrderActionState? state(String id) => _states[id];
  bool get retained => _states.values.any((s) => s.busy || s.uncertain);
  bool _blocked(KitchenQueueItem row, KitchenOrderActionState? s) =>
      events.pending(row.orderId) ||
      events.unresolved(row.orderId) ||
      s?.needsReview == true ||
      s?.uncertain == true ||
      externalBlocked?.call(row.sessionId, s?.owner ?? this) == true;
  bool canAct(KitchenQueueItem row, KitchenAction action) =>
      can('KITCHEN_VIEW') &&
      can(action.permission) &&
      row.itemStatus == action.source &&
      display.find(row.key)?.orderVersion == row.orderVersion &&
      !display.failures.containsKey(row.itemStatus) &&
      !display.inconsistentOrders.contains(row.orderId) &&
      !_blocked(row, state(row.orderId));
  bool canReadyOrder(String id) {
    final rows = display.forOrder(id);
    return rows.isNotEmpty &&
        display.orderComplete(id) &&
        !rows.any((r) => r.itemStatus == OrderItemStatus.pending) &&
        rows.any(
          (r) =>
              r.itemStatus == OrderItemStatus.cooking &&
              canAct(r, KitchenAction.markReady),
        );
  }

  bool canRetry(String id) {
    final s = state(id);
    return s != null &&
        s.uncertain &&
        !s.busy &&
        s.intent != null &&
        !events.pending(id) &&
        can('KITCHEN_VIEW') &&
        can(s.intent!.action.permission) &&
        externalBlocked?.call(s.sessionId, s.owner) != true;
  }

  Future<Result<OrderDetail>> act(
    KitchenQueueItem row,
    KitchenAction action,
  ) async {
    if (!canAct(row, action)) return const Error(KitchenController.busy);
    final s = _states.putIfAbsent(row.orderId, KitchenOrderActionState.new);
    s.sessionId = row.sessionId;
    final intent = KitchenItemTransition(
      orderId: row.orderId,
      orderItemId: row.orderItemId,
      expectedOrderVersion: row.orderVersion,
      action: action,
    );
    return _run(s, intent);
  }

  Future<Result<OrderDetail>> retry(String id) async {
    if (!canRetry(id)) return const Error(KitchenController.busy);
    final s = _states[id]!;
    // Exact retry is valid even if a fresh queue shows a later/terminal state.
    return _run(s, s.intent!);
  }

  Future<Result<OrderDetail>> _run(
    KitchenOrderActionState s,
    KitchenItemTransition intent,
  ) async {
    if (!events.lock(intent.orderId)) {
      return const Error(KitchenController.busy);
    }
    s.busy = true;
    s.failure = null;
    s.intent = intent;
    display.invalidateReads();
    onSessionBlocked?.call(s.owner, s.sessionId, true);
    changed();
    try {
      return await _post(s, intent);
    } finally {
      _release(s, intent.orderId);
      if (current) unawaited(display.refresh());
    }
  }

  Future<Result<OrderDetail>> _post(
    KitchenOrderActionState s,
    KitchenItemTransition intent,
  ) async {
    if (!can(intent.action.permission) || !can('KITCHEN_VIEW')) {
      return const Error(KitchenController.denied);
    }
    final result = await transition(intent);
    if (!current) return const Error(KitchenController.denied);
    switch (result) {
      case Success(value: final order):
        s.lastResponse = order;
        s.intent = null;
        s.failure = null;
        s.uncertain = false;
        s.needsReview = false;
        events.markUnresolved(intent.orderId, false);
        display.applyOrder(order);
        events.emit(order.id, order.summary.tableSessionId, source: this);
      case Error(failure: final f):
        s.failure = f;
        // Loss of authority on a retry does not prove the first POST failed.
        s.uncertain =
            s.uncertain || f.isNetwork || f.type == FailureType.internal;
        if (!s.uncertain) {
          s.intent = null;
          s.needsReview =
              f.type == FailureType.conflict || f.type == FailureType.notFound;
        }
        events.markUnresolved(intent.orderId, s.uncertain);
        await report(f);
    }
    changed();
    return result;
  }

  void _release(KitchenOrderActionState s, String id) {
    s.busy = false;
    if (!current) return;
    events.unlock(id);
    onSessionBlocked?.call(
      s.owner,
      s.sessionId,
      current && (s.uncertain || s.needsReview),
    );
    changed();
  }

  Future<Result<OrderDetail>> readyOrder(String id) async {
    if (!canReadyOrder(id)) return const Error(KitchenController.busy);
    final rows = display.forOrder(id);
    final s = _states.putIfAbsent(id, KitchenOrderActionState.new);
    if (!events.lock(id)) return const Error(KitchenController.busy);
    s.sessionId = rows.first.sessionId;
    s.busy = true;
    s.failure = null;
    display.invalidateReads();
    onSessionBlocked?.call(s.owner, s.sessionId, true);
    changed();
    var version = rows
        .map((r) => r.orderVersion)
        .reduce((a, b) => a > b ? a : b);
    OrderDetail? latest;
    try {
      for (final row in rows.where(
        (r) => r.itemStatus == OrderItemStatus.cooking,
      )) {
        if (!current || !can(KitchenAction.markReady.permission)) {
          return const Error(KitchenController.denied);
        }
        if (latest != null) {
          if (latest.items.any(
            (line) => line.status == OrderItemStatus.pending,
          )) {
            s.needsReview = true;
            s.failure = const Failure(
              type: FailureType.conflict,
              code: 'KITCHEN_NEW_ITEMS',
              message:
                  'Đơn có món chờ nấu mới. Đã giữ các món vừa xác nhận; hãy xem lại đơn.',
            );
            return Error(s.failure!);
          }
          final line = latest.items
              .where((line) => line.id == row.orderItemId)
              .firstOrNull;
          if (line == null ||
              line.status == OrderItemStatus.cancelled ||
              line.status == OrderItemStatus.ready ||
              line.status == OrderItemStatus.served) {
            continue;
          }
          if (line.status != OrderItemStatus.cooking) break;
        }
        final intent = KitchenItemTransition(
          orderId: id,
          orderItemId: row.orderItemId,
          expectedOrderVersion: version,
          action: KitchenAction.markReady,
        );
        s.intent = intent;
        final response = await _post(s, intent);
        if (response case Error<OrderDetail>()) return response;
        latest = (response as Success<OrderDetail>).value;
        version = latest.version;
      }
      if (latest == null) return const Error(KitchenController.busy);
      // Even the final response may contain a newly appended PENDING line.
      if (latest.summary.status != OrderStatus.ready &&
          latest.summary.status != OrderStatus.served) {
        s.failure = const Failure(
          type: FailureType.conflict,
          code: 'KITCHEN_ORDER_NOT_READY',
          message: 'Các món đã xác nhận được lưu; đơn vẫn còn món cần xử lý.',
        );
      }
      return Success(latest);
    } finally {
      _release(s, id);
      if (current) unawaited(display.refresh());
    }
  }

  void review(String id) {
    final s = state(id);
    if (!current || s == null || s.busy || s.uncertain || !display.complete) {
      return;
    }
    s.needsReview = false;
    s.failure = null;
    onSessionBlocked?.call(s.owner, s.sessionId, false);
    changed();
  }

  void signalsChanged() {
    changed();
  }

  @override
  void dispose() {
    for (final e in _states.entries) {
      if (current) {
        if (e.value.uncertain) events.markUnresolved(e.key, false);
        onSessionBlocked?.call(e.value.owner, null, false);
      }
    }
    super.dispose();
  }
}
