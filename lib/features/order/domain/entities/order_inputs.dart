import 'order_entities.dart';
import 'order_quantity.dart';
import 'order_submission.dart';

enum OrderCreationTarget { takeaway, table, session }

class OrderCreationContext {
  const OrderCreationContext.takeaway()
    : serviceType = ServiceType.takeaway,
      target = OrderCreationTarget.takeaway,
      tableId = null,
      tableSessionId = null,
      sessionAlreadyOpen = false,
      guestCount = 1,
      tableName = null;
  const OrderCreationContext.dineIn({
    required String sessionId,
    this.guestCount = 1,
    this.tableName,
  }) : serviceType = ServiceType.dineIn,
       target = OrderCreationTarget.session,
       tableId = null,
       sessionAlreadyOpen = true,
       tableSessionId = sessionId;
  const OrderCreationContext.fromTable({
    required String this.tableId,
    this.guestCount = 1,
    this.tableName,
    this.sessionAlreadyOpen = false,
  }) : serviceType = ServiceType.dineIn,
       target = OrderCreationTarget.table,
       tableSessionId = null;
  final ServiceType serviceType;
  final OrderCreationTarget target;
  final String? tableId, tableSessionId, tableName;

  /// Display/eligibility hint only; never serialized or used as intent identity.
  final bool sessionAlreadyOpen;
  final int guestCount;
  bool get fromTable => target == OrderCreationTarget.table;
  // Provider identity is the workspace, not transient seating display metadata.
  @override
  bool operator ==(Object other) =>
      other is OrderCreationContext &&
      other.serviceType == serviceType &&
      other.target == target &&
      other.tableId == tableId &&
      other.tableSessionId == tableSessionId;
  @override
  int get hashCode => Object.hash(serviceType, target, tableId, tableSessionId);
}

class CreateOrderLine {
  const CreateOrderLine({
    required this.itemId,
    required this.quantity,
    this.note,
  });
  final String itemId;
  final OrderQuantity quantity;
  final String? note;
}

class CreateOrderInput {
  CreateOrderInput({
    required this.context,
    required List<CreateOrderLine> items,
    this.guestCount,
    this.customerName,
    this.customerPhone,
    this.note,
    this.submissionMode = OrderSubmissionMode.draft,
  }) : items = List.unmodifiable(items);
  final OrderCreationContext context;
  final List<CreateOrderLine> items;
  final int? guestCount;
  final String? customerName, customerPhone, note;
  final OrderSubmissionMode submissionMode;
}

class AddOrderItemsInput {
  AddOrderItemsInput({
    required this.expectedVersion,
    required List<CreateOrderLine> items,
    this.submissionMode = OrderSubmissionMode.draft,
  }) : items = List.unmodifiable(items);
  final int expectedVersion;
  final List<CreateOrderLine> items;
  final OrderSubmissionMode submissionMode;
}

class UpdateOrderInput {
  const UpdateOrderInput({
    required this.expectedVersion,
    this.guestCount,
    this.customerName,
    this.customerPhone,
    this.note,
  });
  final int expectedVersion;
  final int? guestCount;
  final String? customerName, customerPhone, note;
  bool get isEmpty =>
      guestCount == null &&
      customerName == null &&
      customerPhone == null &&
      note == null;
}

class UpdateOrderLineInput {
  const UpdateOrderLineInput({
    required this.expectedVersion,
    this.quantity,
    this.note,
  });
  final int expectedVersion;
  final OrderQuantity? quantity;
  final String? note;
  bool get isEmpty => quantity == null && note == null;
}

class OrderQuery {
  const OrderQuery({
    this.q = '',
    this.status,
    this.serviceType,
    this.tableSessionId,
    this.page = 0,
    this.size = 20,
    this.sortBy = 'createdAt',
    this.direction = 'desc',
  });
  final String q, sortBy, direction;
  final OrderStatus? status;
  final ServiceType? serviceType;
  final String? tableSessionId;
  final int page, size;
  bool get valid =>
      q.trim().length <= 100 &&
      page >= 0 &&
      size >= 1 &&
      size <= 100 &&
      page * size <= 2147483647 &&
      const {
        'createdAt',
        'updatedAt',
        'orderCode',
        'totalAmount',
      }.contains(sortBy) &&
      const {'asc', 'desc'}.contains(direction);
  OrderQuery copyWith({
    String? q,
    OrderStatus? Function()? status,
    ServiceType? Function()? serviceType,
    int? page,
    String? sortBy,
    String? direction,
  }) => OrderQuery(
    q: q ?? this.q,
    status: status != null ? status() : this.status,
    serviceType: serviceType != null ? serviceType() : this.serviceType,
    tableSessionId: tableSessionId,
    page: page ?? this.page,
    size: size,
    sortBy: sortBy ?? this.sortBy,
    direction: direction ?? this.direction,
  );
}

abstract interface class OrderKeyGenerator {
  String next();
}
