import 'package:pos_saas_app/core/auth/app_session.dart';
import 'package:pos_saas_app/core/errors/failure.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/kitchen/data/dto/kitchen_dto.dart';
import 'package:pos_saas_app/features/kitchen/domain/entities/kitchen_queue.dart';
import 'package:pos_saas_app/features/kitchen/domain/repositories/kitchen_repository.dart';
import 'package:pos_saas_app/features/kitchen/domain/use_cases/kitchen_use_cases.dart';
import 'package:pos_saas_app/features/kitchen/presentation/controllers/kitchen_display_controller.dart';
import 'package:pos_saas_app/features/kitchen/presentation/controllers/kitchen_order_action_controller.dart';
import 'package:pos_saas_app/features/order/data/dto/order_dto.dart';
import 'package:pos_saas_app/features/order/domain/entities/order_entities.dart';
import 'package:pos_saas_app/features/order/presentation/controllers/order_events.dart';
import 'package:pos_saas_app/features/tables/presentation/controllers/table_events.dart';
import '../../helpers/auth_fakes.dart';
import '../order/order_fakes.dart';

const kitchenPermissions = {
  'KITCHEN_VIEW',
  'KITCHEN_START_COOKING',
  'KITCHEN_MARK_READY',
};
Map<String, dynamic> kitchenJson({
  String orderId = 'o1',
  String itemId = 'i1',
  String status = 'PENDING',
  int version = 3,
  num quantity = 2,
  String name = 'Phở bò',
  String unit = 'tô',
  String? note = 'Không hành',
  String table = 'Bàn 01',
  bool takeaway = false,
}) => {
  'orderId': orderId,
  'orderCode': 'ORD-$orderId',
  'orderVersion': version,
  'orderItemId': itemId,
  'itemName': name,
  'quantity': quantity,
  'unit': unit,
  'note': note,
  'itemStatus': status,
  'serviceType': takeaway ? 'TAKEAWAY' : 'DINE_IN',
  'createdAt': '2026-10-13T01:00:00Z',
  'sentToKitchenAt': null,
  'sessionId': takeaway ? null : 's-$orderId',
  'tableId': takeaway ? null : 't-$orderId',
  'tableCode': takeaway ? null : 'B01',
  'tableName': takeaway ? null : table,
};

OrderDetail kitchenOrder(
  List<KitchenQueueItem> rows, {
  int? version,
  String? rootStatus,
  bool paid = false,
}) {
  final first = rows.first;
  final live = rows
      .where((row) => row.itemStatus != OrderItemStatus.cancelled)
      .toList();
  final status =
      rootStatus ??
      (live.every((row) => row.itemStatus == OrderItemStatus.ready)
          ? 'READY'
          : live.every((row) => row.itemStatus == OrderItemStatus.pending)
          ? 'CONFIRMED'
          : 'PREPARING');
  final j =
      orderJson(
          status: status,
          version: version ?? first.orderVersion,
          confirmed: true,
        )
        ..['id'] = first.orderId
        ..['orderCode'] = first.orderCode
        ..['serviceType'] = first.serviceType.code
        ..['tableSessionId'] = first.sessionId
        ..['paymentStatus'] = paid ? 'PAID' : 'UNPAID'
        ..['paidAmount'] = paid ? 100000 : 0
        ..['items'] = [
          for (final row in rows)
            {
              'id': row.orderItemId,
              'itemId': 'menu-${row.orderItemId}',
              'itemName': row.itemName,
              'unit': row.unit,
              'quantity': row.quantity.toNumber(),
              'unitPrice': 50000,
              'discountAmount': 0,
              'lineTotal': 100000,
              'status': row.itemStatus.code,
              'note': row.note,
              'cancelReason': null,
              'sentToKitchenAt': row.sentToKitchenAt?.toIso8601String(),
            },
        ];
  return OrderDto.detail(j);
}

class FakeKitchen implements KitchenRepository {
  List<KitchenQueueItem> rows = [KitchenDto.item(kitchenJson())];
  final queries = <KitchenQueueQuery>[];
  final writes = <KitchenItemTransition>[];
  Future<Result<KitchenQueuePage>> Function(KitchenQueueQuery)? onQueue;
  Future<Result<OrderDetail>> Function(KitchenItemTransition)? onTransition;
  bool paid = false;
  @override
  Future<Result<KitchenQueuePage>> queue(KitchenQueueQuery query) async {
    queries.add(query);
    if (onQueue != null) {
      return onQueue!(query);
    }
    final matching = rows.where((r) => r.itemStatus == query.status).toList();
    final start = query.page * query.size;
    return Success(
      KitchenQueuePage(
        content: matching.skip(start).take(query.size).toList(),
        page: query.page,
        size: query.size,
        totalElements: matching.length,
        totalPages: (matching.length / query.size).ceil(),
      ),
    );
  }

  @override
  Future<Result<OrderDetail>> transition(KitchenItemTransition input) async {
    writes.add(input);
    if (onTransition != null) return onTransition!(input);
    return perform(input);
  }

  Result<OrderDetail> perform(KitchenItemTransition input) {
    final group = rows.where((r) => r.orderId == input.orderId).toList();
    final line = group.where((r) => r.orderItemId == input.orderItemId).first;
    if (line.itemStatus == input.action.target) {
      return Success(kitchenOrder(group, paid: paid));
    }
    if (line.itemStatus != input.action.source ||
        line.orderVersion != input.expectedOrderVersion) {
      return const Error(
        Failure(
          type: FailureType.conflict,
          code: 'CONCURRENT_ORDER_UPDATE',
          message: 'Đơn đã thay đổi.',
        ),
      );
    }
    final j = kitchenJson(
      orderId: line.orderId,
      itemId: line.orderItemId,
      version: input.expectedOrderVersion + 1,
      status: input.action.target.code,
      name: line.itemName,
      quantity: line.quantity.toNumber(),
      unit: line.unit,
      note: line.note,
    );
    final changed = KitchenDto.item(j);
    final order = kitchenOrder(
      [for (final row in group) row.key == line.key ? changed : row],
      version: input.expectedOrderVersion + 1,
      paid: paid,
    );
    rows = [
      for (final row in rows)
        row.orderId == order.id
            ? row.fromOrder(
                order,
                order.items.firstWhere((l) => l.id == row.orderItemId),
              )
            : row,
    ];
    return Success(order);
  }
}

class KitchenRig {
  KitchenRig({
    FakeKitchen? repository,
    Set<String> permissions = kitchenPermissions,
    Duration interval = const Duration(seconds: 12),
  }) : repo = repository ?? FakeKitchen() {
    appSession = makeAppSession(
      permissions: permissions,
      features: {'KITCHEN_DISPLAY'},
    );
    display = KitchenDisplayController(
      session: () => appSession,
      getQueue: GetKitchenQueue(repo),
      pollInterval: interval,
    );
    actions = KitchenOrderActionController(
      session: () => appSession,
      transition: TransitionKitchenItem(repo),
      display: display,
      events: events,
      externalBlocked: (s, owner) =>
          tables.sessionTransferBlocked(s) ||
          s != null && tables.externalSessionBlocked(s, except: owner),
      onSessionBlocked: tables.markExternalSessionBlocked,
    );
  }
  final FakeKitchen repo;
  AppSession? appSession;
  final events = OrderEvents();
  final tables = TableEvents();
  late final KitchenDisplayController display;
  late final KitchenOrderActionController actions;
  void dispose() {
    actions.dispose();
    display.dispose();
    events.dispose();
    tables.dispose();
  }
}
