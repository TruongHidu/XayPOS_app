import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../../tables/domain/entities/table_entities.dart';
import '../../../tables/domain/entities/table_query.dart';
import '../../../tables/domain/use_cases/restaurant_table_use_cases.dart';
import '../../../tables/domain/use_cases/table_area_use_cases.dart';
import '../entities/order_entities.dart';
import '../entities/order_inputs.dart';
import '../entities/order_table_workspace.dart';
import '../policies/order_table_policy.dart';
import 'order_use_cases.dart';

const _invalidWorkspace = Failure(
  type: FailureType.internal,
  code: 'INVALID_WORKSPACE_RESPONSE',
  message: 'Dữ liệu bàn/đơn phân trang không nhất quán. Hãy tải lại.',
);
const _staleWorkspace = Failure(
  type: FailureType.forbidden,
  code: 'ORDER_WORKSPACE_STALE',
  message: 'Phiên hoặc lần tải đã thay đổi.',
);

/// Capture a bounded page count per refresh. A later refresh handles concurrent insert/delete.
Future<Result<List<T>>> _tablePages<T>(
  Future<Result<TablePage<T>>> Function(int) read, {
  bool Function()? isCurrent,
}) async {
  final rows = <T>[];
  var pages = 1;
  for (var index = 0; index < pages; index++) {
    if (isCurrent?.call() == false) return const Error(_staleWorkspace);
    final result = await read(index);
    if (isCurrent?.call() == false) return const Error(_staleWorkspace);
    switch (result) {
      case Error(failure: final failure):
        return Error(failure);
      case Success(value: final page):
        if (page.page != index ||
            page.totalPages < 0 ||
            page.totalPages > 21474836) {
          return const Error(_invalidWorkspace);
        }
        if (index == 0) pages = page.totalPages;
        rows.addAll(page.content);
    }
  }
  return Success(List.unmodifiable(rows));
}

class GetAvailableOrderTables {
  const GetAvailableOrderTables(this.get);
  final ListRestaurantTable get;
  Future<Result<List<RestaurantTable>>> call({
    bool Function()? isCurrent,
  }) async {
    final result = await _tablePages(
      (page) => get(
        TableQuery(
          status: TableStatus.available,
          page: page,
          size: 100,
          direction: 'asc',
        ),
      ),
      isCurrent: isCurrent,
    );
    return switch (result) {
      Error(failure: final failure) => Error(failure),
      Success(value: final rows) => Success(
        List.unmodifiable(
          {
            for (final row in rows)
              if (row.status == TableStatus.available) row.id: row,
          }.values,
        ),
      ),
    };
  }
}

class GetActiveOrderAreas {
  const GetActiveOrderAreas(this.get);
  final ListTableArea get;
  Future<Result<List<TableArea>>> call({bool Function()? isCurrent}) async {
    final result = await _tablePages(
      (page) => get(
        TableQuery(active: true, page: page, size: 100, direction: 'asc'),
      ),
      isCurrent: isCurrent,
    );
    return switch (result) {
      Error(failure: final failure) => Error(failure),
      Success(value: final rows) => Success(
        List.unmodifiable(
          {
            for (final row in rows)
              if (row.active) row.id: row,
          }.values,
        ),
      ),
    };
  }
}

/// The list API filters one status per call, so every serving status is read
/// (all pages) with at most three requests in flight.
Future<Result<List<OrderSummary>>> _servingOrders(
  GetOrders get,
  ServiceType type, {
  bool Function()? isCurrent,
}) async {
  final statuses = OrderTablePolicy.servingStatuses.toList(growable: false);
  final outcomes = List<Result<List<OrderSummary>>?>.filled(
    statuses.length,
    null,
  );
  var next = 0;
  Future<void> worker() async {
    while (next < statuses.length) {
      final index = next++;
      outcomes[index] = await _servingStatus(
        get,
        type,
        statuses[index],
        isCurrent,
      );
    }
  }

  await Future.wait(List.generate(3, (_) => worker()));
  final rows = <OrderSummary>[];
  for (final outcome in outcomes) {
    switch (outcome!) {
      case Error(failure: final failure):
        return Error(failure);
      case Success(value: final values):
        rows.addAll(values);
    }
  }
  return Success(rows);
}

Future<Result<List<OrderSummary>>> _servingStatus(
  GetOrders get,
  ServiceType type,
  OrderStatus status,
  bool Function()? isCurrent,
) async {
  final rows = <OrderSummary>[];
  var pages = 1;
  for (var index = 0; index < pages; index++) {
    if (isCurrent?.call() == false) return const Error(_staleWorkspace);
    final response = await get(
      OrderQuery(serviceType: type, status: status, page: index, size: 100),
    );
    if (isCurrent?.call() == false) return const Error(_staleWorkspace);
    switch (response) {
      case Error(failure: final failure):
        return Error(failure);
      case Success(value: final page):
        if (page.page != index ||
            page.totalPages < 0 ||
            page.totalPages > 21474836) {
          return const Error(_invalidWorkspace);
        }
        if (index == 0) pages = page.totalPages;
        rows.addAll(page.content);
    }
  }
  return Success(rows);
}

class GetServingOrderSummaries {
  const GetServingOrderSummaries(this.get);
  final GetOrders get;
  Future<Result<ServingOrderSnapshot>> call({
    bool Function()? isCurrent,
  }) async => switch (await _servingOrders(
    get,
    ServiceType.dineIn,
    isCurrent: isCurrent,
  )) {
    Error(failure: final failure) => Error(failure),
    Success(value: final rows) => Success(
      ServingOrderSnapshot.fromOrders(rows),
    ),
  };
}

/// Takeaway orders still being handled, oldest first (first come, first served).
class GetActiveTakeawayOrders {
  const GetActiveTakeawayOrders(this.get);
  final GetOrders get;
  Future<Result<List<OrderSummary>>> call({bool Function()? isCurrent}) async {
    switch (await _servingOrders(
      get,
      ServiceType.takeaway,
      isCurrent: isCurrent,
    )) {
      case Error(failure: final failure):
        return Error(failure);
      case Success(value: final rows):
        // An order can move status between per-status reads; keep its newest copy.
        final latest = <String, OrderSummary>{};
        for (final row in rows) {
          if (row.serviceType != ServiceType.takeaway) continue;
          final seen = latest[row.id];
          if (seen == null || row.version > seen.version) latest[row.id] = row;
        }
        return Success(
          latest.values.toList()
            ..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
        );
    }
  }
}
