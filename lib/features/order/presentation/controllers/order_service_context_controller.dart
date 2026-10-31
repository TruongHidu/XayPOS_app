import 'dart:async';
import '../../../../core/auth/access_policy.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../../tables/domain/entities/table_entities.dart';
import '../../../tables/domain/entities/table_query.dart';
import '../../../tables/domain/use_cases/restaurant_table_use_cases.dart';
import '../../../tables/domain/use_cases/table_session_use_cases.dart';
import '../../../tables/presentation/controllers/table_events.dart';
import '../../domain/entities/order_inputs.dart';
import '../../domain/entities/order_table_workspace.dart';
import '../../domain/policies/order_table_policy.dart';
import '../../domain/use_cases/order_use_cases.dart';
import '../../domain/use_cases/order_workspace_use_cases.dart';
import 'order_controller.dart';

class OrderServiceContextController extends OrderController {
  OrderServiceContextController({
    required super.session,
    required super.events,
    super.onAccessDenied,
    required this.getTables,
    required this.getAreas,
    required this.getServing,
    required this.detailTable,
    required this.getSession,
    required this.getActive,
    required this.tableEvents,
  }) {
    _tableRevision = tableEvents.revision;
    tableEvents.addListener(_tableEvent);
    events.addListener(_orderEvent);
  }
  final GetAvailableOrderTables getTables;
  final GetActiveOrderAreas getAreas;
  final GetServingOrderSummaries getServing;
  final DetailRestaurantTable detailTable;
  final DetailTableSession getSession;
  final GetActiveOrderForSession getActive;
  final TableEvents tableEvents;
  TableQuery query = const TableQuery(
    status: TableStatus.available,
    size: 100,
    direction: 'asc',
  );
  List<RestaurantTable> _tables = const [];
  List<TableArea> _areas = const [];
  List<TableArea> get areas => current ? _areas : const [];
  List<RestaurantTable> get tables => !tableAccess
      ? const []
      : List.unmodifiable(
          _tables.where(
            (t) =>
                (query.occupied == null || t.occupied == query.occupied) &&
                (query.areaId == null || t.area?.id == query.areaId),
          ),
        );
  ServingOrderSnapshot? _snapshot;
  Failure? failure, areasFailure, billsFailure;
  bool loading = false,
      areasLoading = false,
      billsLoading = false,
      selecting = false;
  int _generation = 0, _areasGeneration = 0, _revision = 0, _tableRevision = 0;
  Timer? _refreshTimer;
  Future<void>? _reading;
  bool _refreshRequested = false;
  bool get workspaceAllowed =>
      current && AccessPolicy.canOrderWorkspace(session());
  bool get tableAccess =>
      workspaceAllowed && AccessPolicy.canTables(session(), 'TABLE_VIEW');
  bool get canView => can('ORDER_VIEW');
  bool get dineInAllowed =>
      current && AccessPolicy.canSubmitOrder(session(), takeaway: false);
  bool get takeawayAllowed =>
      current && AccessPolicy.canCreateOrder(session(), takeaway: true);
  bool get menuAllowed =>
      current && AccessPolicy.canMenu(session(), 'MENU_VIEW');
  OrderTableTile tile(RestaurantTable table) => OrderTableTile.from(
    table,
    canView: canView,
    loading: billsLoading,
    snapshot: _snapshot,
  );
  bool canCreateAt(RestaurantTable table) => OrderTablePolicy.canCreate(
    table,
    submit: dineInAllowed,
    menu: menuAllowed,
    tableOpen: AccessPolicy.canTables(session(), 'TABLE_OPEN'),
  );
  bool canSelect(RestaurantTable table) =>
      tableAccess &&
      !selecting &&
      (table.occupied ? canView : canCreateAt(table));

  void _scheduleRefresh() {
    if (!tableAccess) return;
    ++_generation;
    if (_reading != null) _refreshRequested = true;
    _refreshTimer?.cancel();
    _refreshTimer = Timer(
      const Duration(milliseconds: 120),
      () => unawaited(load(background: true)),
    );
  }

  void _tableEvent() {
    if (_tableRevision == tableEvents.revision) return;
    _tableRevision = tableEvents.revision;
    if (!tableAccess) return;
    if (tableEvents.change?.kind == TableChangeKind.area) {
      final change = tableEvents.change!;
      if (change.id == query.areaId &&
          (change.deleted || change.area?.active == false)) {
        query = query.copyWith(areaId: () => null, page: 0);
      }
      unawaited(loadAreas());
    }
    _scheduleRefresh();
  }

  void _orderEvent() {
    if (_revision == events.revision) return;
    _revision = events.revision;
    _scheduleRefresh();
  }

  Future<void> filter({bool? occupied, String? areaId}) async {
    query = query.copyWith(
      occupied: () => occupied,
      areaId: () => areaId,
      page: 0,
    );
    changed(); // Filtering an already loaded snapshot causes no per-card requests.
  }

  Future<void> refresh() async {
    await Future.wait([load(), loadAreas()]);
  }

  Future<void> load({bool background = false}) {
    if (_reading != null && background) {
      _refreshRequested = true;
      return _reading!;
    }
    late final Future<void> future;
    future = _readLoop().whenComplete(() {
      if (identical(_reading, future)) _reading = null;
    });
    _reading = future;
    return future;
  }

  Future<void> _readLoop() async {
    do {
      _refreshRequested = false;
      await _load();
    } while (_refreshRequested && tableAccess);
  }

  Future<void> _load() async {
    if (!tableAccess) return;
    _refreshTimer?.cancel();
    final generation = ++_generation;
    loading = true;
    billsLoading = canView;
    failure = null;
    billsFailure = null;
    changed();
    final result = await getTables(
      isCurrent: () => tableAccess && generation == _generation,
    );
    if (!tableAccess || generation != _generation) return;
    switch (result) {
      case Error(failure: final error):
        loading = false;
        billsLoading = false;
        failure = error;
        await report(error);
        changed();
        return;
      case Success(value: final rows):
        _tables = rows;
    }
    loading = false;
    changed();
    if (!canView || !_tables.any((t) => t.currentSession != null)) {
      billsLoading = false;
      _snapshot = canView ? ServingOrderSnapshot.fromOrders(const []) : null;
      changed();
      return;
    }
    final bills = await getServing(
      isCurrent: () => tableAccess && canView && generation == _generation,
    );
    if (!tableAccess || !canView || generation != _generation) return;
    switch (bills) {
      case Success(value: final snapshot):
        _snapshot = snapshot;
      case Error(failure: final error):
        billsFailure = error;
        await report(error);
    }
    billsLoading = false;
    changed();
  }

  Future<void> loadAreas() async {
    if (!tableAccess) return;
    final generation = ++_areasGeneration;
    areasLoading = true;
    areasFailure = null;
    changed();
    final result = await getAreas(
      isCurrent: () => tableAccess && generation == _areasGeneration,
    );
    if (!tableAccess || generation != _areasGeneration) return;
    switch (result) {
      case Success(value: final rows):
        _areas = rows;
      case Error(failure: final error):
        areasFailure = error;
        await report(error);
    }
    areasLoading = false;
    changed();
  }

  Future<Result<RestaurantTable>> prepare(String id) async {
    if (!tableAccess) return const Error(OrderController.denied);
    final result = await detailTable(id);
    if (!tableAccess) return const Error(OrderController.denied);
    if (result case Error(failure: final error)) {
      failure = error;
      await report(error);
      changed();
    }
    if (result case Success(value: final table)) {
      if (table.id != id) {
        return const Error(
          Failure(
            type: FailureType.internal,
            code: 'INVALID_TABLE_RESPONSE',
            message: 'Dữ liệu bàn không đúng yêu cầu.',
          ),
        );
      }
    }
    return result;
  }

  Future<Result<OrderTableSelection>> selectTable(String id) async {
    if (!tableAccess || selecting) return const Error(OrderController.denied);
    selecting = true;
    failure = null;
    changed();
    try {
      final result = await prepare(id);
      if (!tableAccess) return const Error(OrderController.denied);
      if (result case Error(failure: final error)) return Error(error);
      final table = (result as Success<RestaurantTable>).value;
      if (!OrderTablePolicy.consistent(table)) {
        return _selectionFailure(
          'INCONSISTENT_TABLE_SESSION_STATE',
          'Bàn và phiên chưa đồng bộ. Hãy tải lại.',
        );
      }
      if (table.currentSession != null) {
        if (!canView) {
          return _selectionFailure(
            'ORDER_VIEW_REQUIRED',
            'Bạn chưa có quyền xem đơn hàng nên không kiểm tra được đơn của bàn đang sử dụng.',
            type: FailureType.forbidden,
          );
        }
        final active = await getActive(table.currentSession!.id);
        if (!tableAccess || !canView) {
          return const Error(OrderController.denied);
        }
        switch (active) {
          case Error(failure: final error):
            failure = error;
            await report(error);
            changed();
            return Error(error);
          case Success(value: final order):
            if (order != null) return Success(ViewTableOrder(order));
        }
      }
      if (!canCreateAt(table)) {
        return _selectionFailure(
          'TABLE_ORDER_NOT_ALLOWED',
          'Chưa đủ quyền gửi đơn/mở phiên, quyền chọn món hoặc bàn không còn khả dụng.',
          type: FailureType.forbidden,
        );
      }
      return Success(
        ComposeTableOrder(
          OrderCreationContext.fromTable(
            tableId: table.id,
            tableName: table.name,
            guestCount: table.currentSession?.guestCount ?? 1,
            sessionAlreadyOpen: table.currentSession != null,
          ),
        ),
      );
    } finally {
      selecting = false;
      changed();
    }
  }

  Error<OrderTableSelection> _selectionFailure(
    String code,
    String message, {
    FailureType type = FailureType.conflict,
  }) {
    failure = Failure(type: type, code: code, message: message);
    changed();
    return Error(failure!);
  }

  /// Legacy session composer only; never opens or silently replaces seating.
  Future<Result<OrderCreationContext>> resolveSession(String id) async {
    if (!tableAccess ||
        !AccessPolicy.canCreateOrder(session(), takeaway: false)) {
      return const Error(OrderController.denied);
    }
    final result = await getSession(id);
    if (!tableAccess) return const Error(OrderController.denied);
    if (result case Error(failure: final error)) {
      await report(error);
      return Error(error);
    }
    final seating = (result as Success<TableSession>).value;
    final resultTable = await prepare(seating.tableId);
    if (!tableAccess ||
        !AccessPolicy.canCreateOrder(session(), takeaway: false)) {
      return const Error(OrderController.denied);
    }
    if (resultTable case Error(failure: final error)) return Error(error);
    final table = (resultTable as Success<RestaurantTable>).value;
    if (seating.status != TableSessionStatus.open ||
        !OrderTablePolicy.eligible(table) ||
        !table.occupied ||
        table.currentSession?.id != seating.id) {
      return const Error(
        Failure(
          type: FailureType.conflict,
          code: 'TABLE_SESSION_NOT_OPEN',
          message: 'Phiên bàn không còn khả dụng. Hãy chọn lại bàn.',
        ),
      );
    }
    return Success(
      OrderCreationContext.dineIn(
        sessionId: seating.id,
        guestCount: seating.guestCount,
        tableName: seating.tableName,
      ),
    );
  }

  @override
  void dispose() {
    ++_generation;
    ++_areasGeneration;
    _refreshTimer?.cancel();
    _tables = const [];
    _areas = const [];
    _snapshot = null;
    tableEvents.removeListener(_tableEvent);
    events.removeListener(_orderEvent);
    super.dispose();
  }
}
