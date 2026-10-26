import '../../../menu/domain/entities/menu_item.dart';
import '../../../../core/auth/access_policy.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/order_entities.dart';
import '../../domain/entities/order_inputs.dart';
import '../../domain/entities/order_quantity.dart';
import '../../domain/entities/order_submission.dart';
import '../../domain/policies/order_submission_failure_policy.dart';
import '../../domain/policies/order_validation.dart';
import '../../domain/use_cases/order_use_cases.dart';
import 'order_controller.dart';

class OrderDraftLine {
  const OrderDraftLine(this.id, this.item, this.quantity, this.note);
  final String id;
  final MenuItem item;
  final OrderQuantity quantity;
  final String? note;
  BigInt get previewMinor =>
      (BigInt.from(item.salePrice.minorUnits) *
              BigInt.from(quantity.milliUnits) +
          BigInt.from(500)) ~/
      BigInt.from(1000);
}

class OrderDraftController extends OrderController {
  OrderDraftController({
    required super.session,
    required super.events,
    super.onAccessDenied,
    required this.createOrder,
    required this.keys,
    required this.context,
  }) : _sessionAlreadyOpen = context.sessionAlreadyOpen;
  final CreateOrder createOrder;
  final OrderKeyGenerator keys;
  final OrderCreationContext context;
  bool _sessionAlreadyOpen;

  /// Display-only hint adopted on widget remount; it never changes a frozen intent.
  void adoptSeatingHint(OrderCreationContext latest) {
    if (current && !frozen && latest == context) {
      _sessionAlreadyOpen = latest.sessionAlreadyOpen;
    }
  }

  final List<OrderDraftLine> _lines = [];
  List<OrderDraftLine> get lines => List.unmodifiable(_lines);
  bool busy = false, uncertain = false;
  bool needsTableReview = false;
  bool get keyConflict => failure?.code == 'IDEMPOTENCY_KEY_REUSED';
  bool acknowledgeTableContext(OrderCreationContext latest) {
    if (!current || frozen || !needsTableReview || latest != context) {
      return false;
    }
    _sessionAlreadyOpen = latest.sessionAlreadyOpen;
    needsTableReview = false;
    failure = null;
    changed();
    return true;
  }

  Failure? failure;
  OrderDetail? result;
  bool? replayed;
  String? _key;
  CreateOrderInput? _submitted;
  String? customerName, customerPhone, note;
  int? guestCount;
  bool get dirty =>
      _lines.isNotEmpty ||
      customerName != null ||
      customerPhone != null ||
      note != null ||
      guestCount != null;
  bool get frozen => busy || uncertain || result != null;
  bool get canCreate =>
      can('ORDER_CREATE') &&
      AccessPolicy.canCreateOrder(
        session(),
        takeaway: context.serviceType == ServiceType.takeaway,
      );
  bool get canPick => canCreate && AccessPolicy.canMenu(session(), 'MENU_VIEW');
  bool get canDraft => canCreate && !context.fromTable;
  bool get canSubmit =>
      !needsTableReview &&
      canCreate &&
      can('ORDER_UPDATE') &&
      (!context.fromTable ||
          _sessionAlreadyOpen ||
          AccessPolicy.canTables(session(), 'TABLE_OPEN'));
  bool get canRetry =>
      uncertain &&
      !keyConflict &&
      !busy &&
      _submitted != null &&
      canCreate &&
      (_submitted!.submissionMode != OrderSubmissionMode.submit ||
          can('ORDER_UPDATE'));
  BigInt get previewMinor =>
      _lines.fold(BigInt.zero, (sum, line) => sum + line.previewMinor);
  void add(MenuItem item) {
    if (!current ||
        frozen ||
        !canPick ||
        !item.active ||
        !item.sellable ||
        item.availabilityStatus != AvailabilityStatus.available) {
      return;
    }
    if (_lines.length >= 100) {
      failure = OrderController.invalid({'items': 'Tối đa 100 dòng món.'});
      changed();
      return;
    }
    _lines.add(OrderDraftLine(keys.next(), item, OrderQuantity.one, null));
    failure = null;
    changed();
  }

  void edit(String id, OrderQuantity quantity, String? note) {
    if (!current || frozen || !canPick) return;
    final i = _lines.indexWhere((l) => l.id == id);
    if (i < 0) return;
    if (OrderValidation.text(note, 2000) != null) {
      failure = OrderController.invalid({'note': 'Tối đa 2000 ký tự.'});
      changed();
      return;
    }
    _lines[i] = OrderDraftLine(id, _lines[i].item, quantity, note);
    failure = null;
    changed();
  }

  void remove(String id) {
    if (!current || frozen || !canPick) return;
    _lines.removeWhere((l) => l.id == id);
    changed();
  }

  void setFields({
    String? customerName,
    String? customerPhone,
    String? note,
    int? guestCount,
  }) {
    if (!current || frozen) return;
    this.customerName = customerName;
    this.customerPhone = customerPhone;
    this.note = note;
    this.guestCount = guestCount;
    changed();
  }

  Future<Result<OrderDetail>> submit({OrderSubmissionMode? mode}) async {
    final effectiveMode =
        _submitted?.submissionMode ?? mode ?? OrderSubmissionMode.draft;
    if (mode != null &&
        _submitted != null &&
        mode != _submitted!.submissionMode) {
      return const Error(OrderController.busyFailure);
    }
    if (uncertain && keyConflict) {
      return const Error(OrderController.busyFailure);
    }
    if (!canCreate ||
        (effectiveMode == OrderSubmissionMode.submit && !can('ORDER_UPDATE')) ||
        (_submitted == null &&
            effectiveMode == OrderSubmissionMode.submit &&
            !canSubmit)) {
      return const Error(OrderController.denied);
    }
    if (context.fromTable && effectiveMode != OrderSubmissionMode.submit) {
      failure = OrderController.invalid({
        'submissionMode': 'Gửi từ bàn phải dùng SUBMIT.',
      });
      changed();
      return Error(failure!);
    }
    if (busy || result != null) return const Error(OrderController.busyFailure);
    if (_submitted == null) {
      if (!canPick) return const Error(OrderController.denied);
      final input = CreateOrderInput(
        context: context,
        items: _lines
            .map(
              (l) => CreateOrderLine(
                itemId: l.item.id,
                quantity: l.quantity,
                note: l.note,
              ),
            )
            .toList(),
        customerName: customerName,
        customerPhone: customerPhone,
        note: note,
        guestCount: context.fromTable
            ? guestCount
            : guestCount ?? context.guestCount,
        submissionMode: effectiveMode,
      );
      final errors = OrderValidation.create(input);
      if (previewMinor > BigInt.from(99999999999999)) {
        errors['items'] = 'Tổng dự kiến vượt giới hạn tiền.';
      }
      if (errors.isNotEmpty) {
        failure = OrderController.invalid(errors);
        changed();
        return Error(failure!);
      }
      _submitted = input;
      _key = keys.next();
    }
    busy = true;
    failure = null;
    changed();
    try {
      final wasUncertain = uncertain;
      final response = await invoke(
        'ORDER_CREATE',
        () => createOrder(_submitted!, _key!),
      );
      if (!current) return const Error(OrderController.denied);
      switch (response) {
        case Success(value: final value):
          result = value.order;
          replayed = value.replayed;
          uncertain = false;
          needsTableReview = false;
          _lines.clear();
          events.emit(value.order.id, value.order.summary.tableSessionId);
          return Success(value.order);
        case Error(failure: final f):
          failure = f;
          uncertain = OrderSubmissionFailurePolicy.uncertain(
            f,
            previouslyUncertain: wasUncertain,
          );
          if (!uncertain) {
            needsTableReview =
                context.fromTable &&
                const {
                  'TABLE_SESSION_HAS_SERVING_ORDER',
                  'TABLE_ALREADY_OCCUPIED',
                  'TABLE_SESSION_NOT_OPEN',
                  'TABLE_INACTIVE',
                  'TABLE_AREA_INACTIVE',
                  'TABLE_NOT_FOUND',
                  'TABLE_AREA_NOT_FOUND',
                }.contains(f.code);
            _submitted = null;
            _key = null;
          }
          return Error(f);
      }
    } finally {
      busy = false;
      changed();
    }
  }

  Future<Result<OrderDetail>> retry() =>
      canRetry ? submit() : Future.value(const Error(OrderController.denied));

  @override
  void dispose() {
    _lines.clear();
    _submitted = null;
    _key = null;
    result = null;
    customerName = null;
    customerPhone = null;
    note = null;
    super.dispose();
  }
}
