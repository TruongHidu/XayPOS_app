import '../../../../core/auth/access_policy.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../../menu/domain/entities/menu_item.dart';
import '../../domain/entities/order_entities.dart';
import '../../domain/entities/order_inputs.dart';
import '../../domain/entities/order_quantity.dart';
import '../../domain/entities/order_submission.dart';
import '../../domain/policies/order_access_policy.dart';
import '../../domain/policies/order_submission_failure_policy.dart';
import '../../domain/policies/order_validation.dart';
import '../../domain/use_cases/order_use_cases.dart';
import 'order_controller.dart';
import 'order_draft_controller.dart' show OrderDraftLine;

/// New-line cart and one immutable append intent, independent of old-line edits.
class OrderAppendController extends OrderController {
  OrderAppendController({
    required super.session,
    required super.events,
    super.onAccessDenied,
    required this.id,
    required this.root,
    required this.beforeSend,
    required this.onApplied,
    required this.submitItems,
    required this.keys,
    this.blocked,
    this.retryBlocked,
    this.appliedSource,
  });

  final String id;
  final OrderDetail? Function() root;
  final void Function() beforeSend;
  final void Function(OrderDetail) onApplied;
  final bool Function()? blocked;
  final bool Function()? retryBlocked;
  final Object? Function()? appliedSource;
  final SubmitOrderItems submitItems;
  final OrderKeyGenerator keys;
  final List<OrderDraftLine> _lines = [];
  OrderDetail? _baseline;
  AddOrderItemsInput? _intent;
  String? _key;
  bool uncertain = false, needsReview = false;
  Failure? failure;
  OrderSubmission? result;

  List<OrderDraftLine> get lines => List.unmodifiable(_lines);
  bool get busy => events.pending(id);
  bool get keyConflict => failure?.code == 'IDEMPOTENCY_KEY_REUSED';
  bool get frozen => busy || uncertain || result != null;
  bool get dirty => _lines.isNotEmpty;
  int? get baselineVersion => _baseline?.version;
  bool get authority {
    final target = _baseline ?? root();
    return current &&
        target != null &&
        AccessPolicy.canAppendOrder(
          session(),
          takeaway: target.summary.serviceType == ServiceType.takeaway,
        );
  }

  bool get appendable {
    final target = root();
    return !frozen &&
        !needsReview &&
        blocked?.call() != true &&
        target != null &&
        OrderAccessPolicy.canAppend(target, authority);
  }

  bool get canPick =>
      appendable && AccessPolicy.canMenu(session(), 'MENU_VIEW');
  bool get canRetry =>
      uncertain &&
      !keyConflict &&
      !busy &&
      retryBlocked?.call() != true &&
      authority &&
      _intent != null;
  BigInt get previewMinor =>
      _lines.fold(BigInt.zero, (sum, line) => sum + line.previewMinor);

  // Called once when opening a selected order; later GETs never change its baseline.
  void begin(OrderDetail target) {
    if (result != null && !busy && !uncertain) {
      result = null;
      _baseline = null;
    }
    if (!current || target.id != id || _baseline != null) return;
    _baseline = target;
  }

  void add(MenuItem item) {
    if (!canPick || !item.sellable) return;
    if (_lines.length >= 100) {
      failure = OrderController.invalid({'items': 'Tối đa 100 dòng món.'});
      changed();
      return;
    }
    _baseline ??= root();
    _lines.add(OrderDraftLine(keys.next(), item, OrderQuantity.one, null));
    failure = null;
    changed();
  }

  void edit(String lineId, OrderQuantity quantity, String? note) {
    if (!canPick) return;
    final index = _lines.indexWhere((line) => line.id == lineId);
    if (index < 0) return;
    if (OrderValidation.text(note, 2000) != null) {
      failure = OrderController.invalid({'note': 'Tối đa 2000 ký tự.'});
    } else {
      _lines[index] = OrderDraftLine(
        lineId,
        _lines[index].item,
        quantity,
        note,
      );
      failure = null;
    }
    changed();
  }

  void remove(String lineId) {
    if (!canPick) return;
    _lines.removeWhere((line) => line.id == lineId);
    changed();
  }

  /// Explicit user acknowledgement after a definite refusal, never for unknown outcome.
  bool reviewCurrent() {
    final latest = root();
    if (!current ||
        frozen ||
        !needsReview ||
        latest == null ||
        blocked?.call() == true ||
        !OrderAccessPolicy.canAppend(latest, authority)) {
      return false;
    }
    if (failure?.code == 'CONCURRENT_ORDER_UPDATE' &&
        _baseline != null &&
        latest.version <= _baseline!.version) {
      return false;
    }
    _baseline = latest;
    needsReview = false;
    failure = null;
    changed();
    return true;
  }

  void discard() {
    if (!current || frozen) return;
    _lines.clear();
    _baseline = null;
    _intent = null;
    _key = null;
    needsReview = false;
    failure = null;
    changed();
  }

  Future<Result<OrderDetail>> send() async {
    if (!canPick || busy) return const Error(OrderController.denied);
    _baseline ??= root();
    if (_baseline == null || root()?.version != _baseline!.version) {
      needsReview = true;
      failure = const Failure(
        type: FailureType.conflict,
        code: 'CONCURRENT_ORDER_UPDATE',
        message:
            'Đơn đã đổi so với lúc mở giỏ. Hãy tải lại, đối chiếu rồi xác nhận dùng dữ liệu mới.',
      );
      changed();
      return Error(failure!);
    }
    final input = AddOrderItemsInput(
      expectedVersion: _baseline!.version,
      submissionMode: OrderSubmissionMode.submit,
      items: _lines
          .map(
            (line) => CreateOrderLine(
              itemId: line.item.id,
              quantity: line.quantity,
              note: line.note,
            ),
          )
          .toList(),
    );
    final errors = OrderValidation.lines(input.items);
    if (previewMinor > BigInt.from(99999999999999)) {
      errors['items'] = 'Tổng dự kiến vượt giới hạn tiền.';
    }
    if (errors.isNotEmpty) {
      failure = OrderController.invalid(errors);
      changed();
      return Error(failure!);
    }
    _intent = input;
    _key = keys.next();
    return _execute();
  }

  Future<Result<OrderDetail>> retry() async {
    // Intentionally no cached-version, mutable menu/seating or appendable checks.
    if (!canRetry) return const Error(OrderController.denied);
    return _execute(retrying: true);
  }

  Future<Result<OrderDetail>> _execute({bool retrying = false}) async {
    if (!authority ||
        (retrying ? retryBlocked?.call() : blocked?.call()) == true ||
        _intent == null ||
        !events.lock(id)) {
      return const Error(OrderController.busyFailure);
    }
    final previouslyUncertain = uncertain;
    beforeSend();
    failure = null;
    changed();
    try {
      final response = await invoke(
        'ORDER_UPDATE',
        () => submitItems(id, _intent!, _key!),
      );
      if (!current) return const Error(OrderController.denied);
      switch (response) {
        case Success(value: final value):
          result = value;
          uncertain = false;
          needsReview = false;
          _intent = null;
          _key = null;
          _lines.clear();
          events.markUnresolved(id, false);
          onApplied(value.order);
          events.emit(
            value.order.id,
            value.order.summary.tableSessionId,
            source: appliedSource?.call(),
          );
          return Success(value.order);
        case Error(failure: final error):
          failure = error;
          uncertain = OrderSubmissionFailurePolicy.uncertain(
            error,
            previouslyUncertain: previouslyUncertain,
          );
          needsReview = !uncertain;
          events.markUnresolved(id, uncertain);
          if (!uncertain) {
            _intent = null;
            _key = null;
          }
          return Error(error);
      }
    } finally {
      events.unlock(id);
      changed();
    }
  }

  @override
  void dispose() {
    _lines.clear();
    _intent = null;
    _key = null;
    _baseline = null;
    result = null;
    super.dispose();
  }
}
