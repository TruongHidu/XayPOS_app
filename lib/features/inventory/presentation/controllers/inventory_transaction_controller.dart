import 'dart:async';
import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/stock_document.dart';
import '../../domain/entities/stock_queries.dart';
import '../../domain/use_cases/stock_document_use_cases.dart';
import 'inventory_controller.dart';
import 'inventory_events.dart';

class InventoryTransactionController extends InventoryController {
  InventoryTransactionController({
    required super.session,
    required super.events,
    super.onAccessDenied,
    required this.get,
    this.query = const InventoryTransactionQuery(),
  }) {
    events.addListener(_event);
  }
  final GetInventoryTransactions get;
  InventoryTransactionQuery query;
  List<InventoryTransaction> rows = const [];

  /// Display names for filter IDs: set from pickers, else learned from rows.
  final names = <String, String>{};
  int totalElements = 0, totalPages = 0, _generation = 0, _revision = 0;
  bool loading = false, hasLoaded = false, _scheduled = false;
  Failure? failure;
  void _event() {
    if (_revision == events.revision) return;
    _revision = events.revision;
    final change = events.change;
    if (!current ||
        !(change?.kind == InventoryChangeKind.balance ||
            change?.kind == InventoryChangeKind.orderStock) ||
        query.warehouseId != null &&
            change?.warehouseId != null &&
            query.warehouseId != change?.warehouseId ||
        change?.kind == InventoryChangeKind.orderStock &&
            (query.documentId != null ||
                query.source == InventoryTransactionSource.stockDocument) ||
        query.orderId != null &&
            change?.orderId != null &&
            query.orderId != change?.orderId ||
        query.orderItemId != null &&
            change?.orderItemId != null &&
            query.orderItemId != change?.orderItemId ||
        query.ingredientId != null &&
            change?.ingredientId != null &&
            query.ingredientId != change?.ingredientId ||
        query.documentId != null &&
            change?.documentId != null &&
            query.documentId != change?.documentId) {
      return;
    }
    ++_generation;
    if (_scheduled) return;
    _scheduled = true;
    Future.microtask(() {
      _scheduled = false;
      if (current) unawaited(load());
    });
  }

  void filter(InventoryTransactionQuery value) {
    ++_generation;
    query = value.copyWith(page: 0);
    unawaited(load());
  }

  void page(int value) {
    if (value < 0 || value >= totalPages && value != 0) return;
    query = query.copyWith(page: value);
    unawaited(load());
  }

  Future<void> load() async {
    if (!can('INVENTORY_VIEW')) return;
    final generation = ++_generation, q = query;
    if (!q.valid) {
      failure = InventoryController.invalid({
        'query': 'Bộ lọc hoặc khoảng thời gian không hợp lệ.',
      });
      loading = false;
      changed();
      return;
    }
    loading = true;
    failure = null;
    changed();
    final result = await read('transactions', () => get(q));
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
        for (final row in rows) {
          names.putIfAbsent(row.warehouseId, () => row.warehouseCode);
          names.putIfAbsent(row.ingredientId, () => row.ingredientName);
          if (row.documentId case final id?) {
            names.putIfAbsent(id, () => row.documentCode!);
          }
        }
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
    events.removeListener(_event);
    super.dispose();
  }
}
