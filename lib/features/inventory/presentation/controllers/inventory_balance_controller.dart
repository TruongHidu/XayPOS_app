import 'dart:async';
import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/inventory_entities.dart';
import '../../domain/entities/inventory_queries.dart';
import '../../domain/use_cases/inventory_use_cases.dart';
import 'inventory_controller.dart';
import 'inventory_events.dart';

class InventoryBalanceController extends InventoryController {
  InventoryBalanceController({
    required super.session,
    required super.events,
    super.onAccessDenied,
    required this.get,
    required this.getLowStock,
    this.warehouseId,
    this.lowStock = false,
  }) {
    if (lowStock) query = const InventoryBalanceQuery(sortBy: 'quantity');
    events.addListener(_event);
  }
  final GetInventoryBalances get;
  final GetLowStockBalances getLowStock;
  final String? warehouseId;
  final bool lowStock;
  InventoryBalanceQuery query = const InventoryBalanceQuery();
  List<InventoryBalance> rows = const [];
  int totalElements = 0, totalPages = 0, _generation = 0, _revision = 0;
  bool loading = false, hasLoaded = false, _scheduled = false;
  Failure? failure;
  Timer? _debounce;
  bool get allowed => can('INVENTORY_VIEW') && (!lowStock || canLowStock);
  void _event() {
    if (_revision == events.revision) return;
    _revision = events.revision;
    if (events.change?.kind == InventoryChangeKind.document) return;
    if (!current ||
        warehouseId != null && events.change?.warehouseId != warehouseId) {
      return;
    }
    ++_generation;
    if (_scheduled) return;
    _scheduled = true;
    Future.microtask(() {
      _scheduled = false;
      if (allowed) unawaited(load());
    });
  }

  void search(String value) {
    _debounce?.cancel();
    ++_generation;
    query = query.copyWith(q: value.trim(), page: 0);
    changed();
    _debounce = Timer(const Duration(milliseconds: 350), load);
  }

  void filter({bool? active, String? sortBy, String? direction, int? size}) {
    _debounce?.cancel();
    ++_generation;
    query = query.copyWith(
      ingredientActive: () => active,
      sortBy: sortBy,
      direction: direction,
      size: size,
      page: 0,
    );
    unawaited(load());
  }

  void page(int value) {
    if (value < 0 || value >= totalPages && value != 0) return;
    query = query.copyWith(page: value);
    unawaited(load());
  }

  Future<void> load() async {
    if (!allowed || !lowStock && warehouseId == null) return;
    _debounce?.cancel();
    final generation = ++_generation;
    final q = query;
    if (!q.valid) {
      loading = false;
      failure = InventoryController.invalid({
        'q': 'Bộ lọc không hợp lệ; từ khóa tối đa 100 ký tự.',
      });
      changed();
      return;
    }
    loading = true;
    failure = null;
    changed();
    final result = await read(
      'balances',
      () => lowStock
          ? getLowStock(LowStockQuery(warehouseId: warehouseId, filters: q))
          : get(warehouseId!, q),
      lowStock: lowStock,
    );
    if (!current || generation != _generation) return;
    switch (result) {
      case Success(value: final data):
        if (q.page > 0 && data.content.isEmpty && data.totalPages <= q.page) {
          query = q.copyWith(
            page: data.totalPages == 0 ? 0 : data.totalPages - 1,
          );
          await load();
          return;
        }
        rows = data.content;
        totalElements = data.totalElements;
        totalPages = data.totalPages;
        hasLoaded = true;
      case Error(failure: final error):
        failure = error;
    }
    loading = false;
    changed();
  }

  @override
  void dispose() {
    ++_generation;
    _debounce?.cancel();
    events.removeListener(_event);
    super.dispose();
  }
}
