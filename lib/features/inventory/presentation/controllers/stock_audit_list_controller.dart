import 'dart:async';
import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/stock_audit.dart';
import '../../domain/entities/stock_audit_queries.dart';
import '../../domain/use_cases/stock_audit_use_cases.dart';
import 'inventory_controller.dart';
import 'inventory_events.dart';
import 'stock_audit_controller.dart';

class StockAuditListController extends StockAuditController {
  StockAuditListController({
    required super.session,
    required super.events,
    super.onAccessDenied,
    required this.get,
  }) {
    events.addListener(_event);
  }

  final GetStockAudits get;
  StockAuditQuery query = const StockAuditQuery();
  List<StockAuditSummary> rows = const [];
  int totalElements = 0, totalPages = 0, _generation = 0, _revision = 0;
  bool loading = false, hasLoaded = false, _scheduled = false;
  Failure? failure;
  Timer? _debounce;

  void _event() {
    if (_revision == events.revision) return;
    _revision = events.revision;
    final e = events.change;
    if (!canView ||
        e?.kind != InventoryChangeKind.audit ||
        query.warehouseId != null && query.warehouseId != e?.warehouseId) {
      return;
    }
    if (_scheduled) return;
    _scheduled = true;
    Future.microtask(() {
      _scheduled = false;
      if (canView) unawaited(load());
    });
  }

  void search(String value) {
    _debounce?.cancel();
    ++_generation;
    query = query.copyWith(q: value.trim(), page: 0);
    changed();
    _debounce = Timer(const Duration(milliseconds: 350), load);
  }

  void filter(StockAuditQuery value) {
    _debounce?.cancel();
    query = value.copyWith(page: 0);
    unawaited(load());
  }

  void page(int value) {
    if (value < 0 || value >= totalPages && value != 0) return;
    query = query.copyWith(page: value);
    unawaited(load());
  }

  Future<void> load() async {
    if (!canView) return;
    _debounce?.cancel();
    final generation = ++_generation, q = query;
    if (!q.valid) {
      failure = InventoryController.invalid({
        'query': 'Bộ lọc hoặc khoảng ngày không hợp lệ.',
      });
      loading = false;
      changed();
      return;
    }
    loading = true;
    failure = null;
    changed();
    final result = await auditRead('audits', () => get(q));
    if (!canView || generation != _generation) return;
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
