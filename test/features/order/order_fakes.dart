import 'dart:async';
import 'package:pos_saas_app/core/auth/app_session.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/order/data/dto/order_dto.dart';
import 'package:pos_saas_app/features/order/domain/entities/order_entities.dart';
import 'package:pos_saas_app/features/order/domain/entities/order_item_action.dart';
import 'package:pos_saas_app/features/order/domain/entities/order_inputs.dart';
import 'package:pos_saas_app/features/order/domain/entities/order_payment.dart';
import 'package:pos_saas_app/features/order/domain/entities/order_submission.dart';
import 'package:pos_saas_app/features/order/domain/repositories/order_repository.dart';
import 'package:pos_saas_app/features/order/domain/use_cases/order_use_cases.dart';
import 'package:pos_saas_app/features/order/domain/use_cases/order_workspace_use_cases.dart';
import 'package:pos_saas_app/features/order/domain/policies/order_table_policy.dart';
import 'package:pos_saas_app/features/order/presentation/controllers/order_draft_controller.dart';
import 'package:pos_saas_app/features/order/presentation/controllers/order_detail_controller.dart';
import 'package:pos_saas_app/features/order/presentation/controllers/order_events.dart';
import 'package:pos_saas_app/features/order/presentation/controllers/order_service_context_controller.dart';
import 'package:pos_saas_app/features/tables/domain/use_cases/restaurant_table_use_cases.dart';
import 'package:pos_saas_app/features/tables/domain/use_cases/table_area_use_cases.dart';
import 'package:pos_saas_app/features/tables/domain/use_cases/table_session_use_cases.dart';
import 'package:pos_saas_app/features/tables/presentation/controllers/table_events.dart';
import '../../helpers/auth_fakes.dart';
import '../tables/table_fakes.dart';

const itemId = '22222222-2222-4222-8222-222222222222';
const sessionId = '11111111-1111-4111-8111-111111111111';
const orderPermissions = {
  'ORDER_VIEW',
  'ORDER_CREATE',
  'ORDER_UPDATE',
  'ORDER_CANCEL',
  'MENU_VIEW',
  'TABLE_VIEW',
  'TABLE_OPEN',
};
const orderFeatures = {
  'ORDER_MANAGEMENT',
  'TABLE_MANAGEMENT',
  'POS_QUICK_ORDER',
  'MENU_MANAGEMENT',
};
AppSession orderSession({
  Set<String> permissions = orderPermissions,
  Set<String> features = orderFeatures,
}) => makeAppSession(permissions: permissions, features: features);
Map<String, dynamic> orderJson({
  int version = 5,
  String status = 'OPEN',
  bool confirmed = false,
  String lineStatus = 'PENDING',
}) => {
  'id': 'o1',
  'orderCode': 'OD-TEST',
  'serviceType': 'TAKEAWAY',
  'sourceChannel': 'WAITER',
  'tableSessionId': null,
  'status': status,
  'paymentStatus': 'UNPAID',
  'customerName': null,
  'customerPhone': null,
  'guestCount': 1,
  'note': null,
  'currencyCode': 'VND',
  'subtotalAmount': 100000,
  'discountAmount': 0,
  'taxAmount': 0,
  'serviceChargeAmount': 0,
  'totalAmount': 100000,
  'paidAmount': 0,
  'createdBy': 'u1',
  'confirmedAt': confirmed ? '2026-10-08T00:00:00Z' : null,
  'completedAt': null,
  'cancelledAt': null,
  'cancelReason': null,
  'createdAt': '2026-10-08T00:00:00Z',
  'updatedAt': '2026-10-08T00:00:00Z',
  'version': version,
  'items': [
    {
      'id': 'line1',
      'itemId': itemId,
      'itemName': 'Phở bò',
      'unit': 'tô',
      'quantity': 2,
      'unitPrice': 50000,
      'discountAmount': 0,
      'lineTotal': 100000,
      'status': lineStatus,
      'note': null,
      'cancelReason': null,
      'sentToKitchenAt': null,
    },
  ],
};

class TestKeys implements OrderKeyGenerator {
  int calls = 0;
  @override
  String next() => 'key-${++calls}';
}

class FakeOrders implements OrderRepository {
  final itemTransitions = <(String, String, int, OrderItemAction)>[];
  final servedBatches = <(String, int)>[];
  Future<Result<OrderDetail>> Function()? onTransition, onMarkAllServed;
  @override
  Future<Result<OrderDetail>> transitionItem(
    String id,
    String lineId,
    int version,
    OrderItemAction action,
  ) async {
    itemTransitions.add((id, lineId, version, action));
    return onTransition != null ? onTransition!() : Success(current);
  }

  @override
  Future<Result<OrderDetail>> markAllServed(String id, int version) async {
    servedBatches.add((id, version));
    return onMarkAllServed != null ? onMarkAllServed!() : Success(current);
  }

  OrderDetail current = OrderDto.detail(orderJson());
  final creates = <(CreateOrderInput, String)>[];
  final writes = <(String, int)>[];
  final submissions = <(String, AddOrderItemsInput, String)>[];
  final paymentCalls = <(String, RecordOrderPaymentInput, String)>[];
  final completes = <(String, int)>[];
  final _appliedKeys = <String>{};
  final queries = <OrderQuery>[];
  int detailCalls = 0;
  final activeCalls = <String>[];
  Future<Result<OrderDetail?>> Function(String)? onActive;
  Future<Result<OrderDetail>> Function()? onCreate, onWrite, onDetail;
  Future<Result<OrderSubmission>> Function()? onSubmitItems;
  Future<Result<OrderPage>> Function(OrderQuery)? onList;
  Future<Result<OrderPayment>> Function()? onRecordPayment;
  Future<Result<OrderDetail>> Function()? onComplete;
  @override
  Future<Result<OrderPage>> list(OrderQuery q) async {
    queries.add(q);
    return onList != null
        ? onList!(q)
        : Success(
            OrderPage(
              content:
                  q.serviceType == ServiceType.dineIn &&
                      (current.summary.serviceType != q.serviceType ||
                          q.status != null &&
                              current.summary.status != q.status)
                  ? []
                  : [current.summary],
              page: q.page,
              size: q.size,
              totalElements: 1,
              totalPages: 1,
            ),
          );
  }

  @override
  Future<Result<OrderDetail>> detail(String id) async {
    detailCalls++;
    return onDetail != null ? onDetail!() : Success(current);
  }

  @override
  Future<Result<OrderDetail?>> activeForSession(String id) async {
    activeCalls.add(id);
    if (onActive != null) return onActive!(id);
    return Success(
      current.summary.serviceType == ServiceType.dineIn &&
              current.summary.tableSessionId == id &&
              OrderTablePolicy.servingStatuses.contains(current.summary.status)
          ? current
          : null,
    );
  }

  @override
  Future<Result<OrderSubmission>> create(
    CreateOrderInput input,
    String key,
  ) async {
    creates.add((input, key));
    if (onCreate != null) {
      return switch (await onCreate!()) {
        Success(value: final value) => Success(
          OrderSubmission(value, replayed: false),
        ),
        Error(failure: final failure) => Error(failure),
      };
    }
    if (input.submissionMode == OrderSubmissionMode.submit) {
      current = OrderDto.detail(
        orderJson(
            version: current.version + 1,
            status: 'CONFIRMED',
            confirmed: true,
          )
          ..['serviceType'] = input.context.serviceType.code
          ..['tableSessionId'] = input.context.fromTable
              ? sessionId
              : input.context.tableSessionId,
      );
    }
    return Success(OrderSubmission(current, replayed: false));
  }

  @override
  Future<Result<OrderSubmission>> submitItems(
    String id,
    AddOrderItemsInput input,
    String key,
  ) async {
    submissions.add((id, input, key));
    if (onSubmitItems != null) return onSubmitItems!();
    if (!_appliedKeys.add(key)) {
      return Success(OrderSubmission(current, replayed: true));
    }
    final data =
        orderJson(
            version: current.version + 2,
            status: 'CONFIRMED',
            confirmed: true,
          )
          ..['id'] = id
          ..['serviceType'] = current.summary.serviceType.code
          ..['tableSessionId'] = current.summary.tableSessionId
          ..['confirmedAt'] =
              current.confirmedAt?.toIso8601String() ?? '2026-10-08T00:00:00Z';
    final old = current.items
        .map(
          (line) => <String, dynamic>{
            'id': line.id,
            'itemId': line.itemId,
            'itemName': line.itemName,
            'unit': line.unit,
            'quantity': line.quantity.toNumber(),
            'unitPrice': line.unitPrice.minorUnits / 100,
            'discountAmount': line.discountAmount.minorUnits / 100,
            'lineTotal': line.lineTotal.minorUnits / 100,
            'status': line.status.code,
            'note': line.note,
            'cancelReason': line.cancelReason,
            'sentToKitchenAt': line.sentToKitchenAt?.toIso8601String(),
          },
        )
        .toList();
    for (final line in input.items) {
      old.add({
        'id': 'added-${old.length}',
        'itemId': line.itemId,
        'itemName': 'Current menu snapshot',
        'unit': 'bowl',
        'quantity': line.quantity.toNumber(),
        'unitPrice': 60000,
        'discountAmount': 0,
        'lineTotal': 60000 * line.quantity.toNumber(),
        'status': 'PENDING',
        'note': line.note,
        'cancelReason': null,
        'sentToKitchenAt': null,
      });
    }
    data['items'] = old;
    data['subtotalAmount'] = data['totalAmount'] = old
        .where((line) => line['status'] != 'CANCELLED')
        .fold<num>(0, (sum, line) => sum + (line['lineTotal'] as num));
    current = OrderDto.detail(data);
    return Success(OrderSubmission(current, replayed: false));
  }

  Future<Result<OrderDetail>> _write(String kind, int version) async {
    writes.add((kind, version));
    return onWrite != null ? onWrite!() : Success(current);
  }

  @override
  Future<Result<OrderDetail>> update(String id, UpdateOrderInput input) =>
      _write('update', input.expectedVersion);
  @override
  Future<Result<OrderDetail>> addItems(
    String id,
    int version,
    List<CreateOrderLine> items,
  ) => _write('add', version);
  @override
  Future<Result<OrderDetail>> updateItem(
    String id,
    String lineId,
    UpdateOrderLineInput input,
  ) => _write('line', input.expectedVersion);
  @override
  Future<Result<OrderDetail>> confirm(String id, int version) =>
      _write('confirm', version);
  @override
  Future<Result<OrderDetail>> cancelItem(
    String id,
    String lineId,
    int version,
    String reason,
  ) => _write('cancelLine', version);
  @override
  Future<Result<OrderDetail>> cancel(String id, int version, String reason) =>
      _write('cancel', version);

  @override
  Future<Result<OrderPayment>> recordPayment(
    String id,
    RecordOrderPaymentInput input,
    String idempotencyKey,
  ) async {
    paymentCalls.add((id, input, idempotencyKey));
    if (onRecordPayment != null) return onRecordPayment!();
    return Success(
      OrderPayment(
        id: 'payment1',
        orderId: id,
        paymentCode: 'PAY-TEST',
        amount: input.amount,
        currencyCode: current.summary.currencyCode,
        paymentMethod: input.paymentMethod,
        confirmationSource: PaymentConfirmationSource.staffManual,
        provider: null,
        status: PaymentRecordStatus.success,
        referenceNo: input.normalizedReferenceNo,
        requestedAt: DateTime.utc(2026, 10, 17),
        paidAt: DateTime.utc(2026, 10, 17),
        createdBy: 'u1',
      ),
    );
  }

  @override
  Future<Result<OrderDetail>> complete(String id, int expectedVersion) async {
    completes.add((id, expectedVersion));
    return onComplete != null
        ? onComplete!()
        : _write('complete', expectedVersion);
  }
}

OrderDraftController draft(
  FakeOrders repo,
  AppSession? Function() session, {
  OrderCreationContext context = const OrderCreationContext.takeaway(),
  OrderEvents? events,
}) => OrderDraftController(
  session: session,
  events: events ?? OrderEvents(),
  createOrder: CreateOrder(repo),
  keys: TestKeys(),
  context: context,
);
OrderDetailController detail(
  FakeOrders repo,
  AppSession? Function() session, {
  OrderEvents? events,
}) => OrderDetailController(
  session: session,
  events: events ?? OrderEvents(),
  id: 'o1',
  get: GetOrderDetail(repo),
  updateOrder: UpdateOrder(repo),
  add: AddOrderItems(repo),
  updateLine: UpdateOrderItem(repo),
  confirmOrder: ConfirmOrder(repo),
  cancelLine: CancelOrderItem(repo),
  cancelOrder: CancelOrder(repo),
  transitionOrderItem: TransitionOrderItem(repo),
)..seed(repo.current);
OrderServiceContextController hub(
  TableServer server,
  AppSession? Function() session, {
  OrderEvents? events,
  FakeOrders? orders,
}) => OrderServiceContextController(
  session: session,
  events: events ?? OrderEvents(),
  getTables: GetAvailableOrderTables(ListRestaurantTable(server.tables)),
  getAreas: GetActiveOrderAreas(ListTableArea(server.areas)),
  getServing: GetServingOrderSummaries(GetOrders(orders ?? FakeOrders())),
  detailTable: DetailRestaurantTable(server.tables),
  getSession: DetailTableSession(server.sessions),
  getActive: GetActiveOrderForSession(orders ?? FakeOrders()),
  tableEvents: TableEvents(),
);
