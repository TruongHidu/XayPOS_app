import 'dart:async';
import '../../../../core/errors/failure.dart';
import '../../../../core/paging/endless_pages.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/stock_document.dart';
import '../../domain/entities/stock_queries.dart';
import '../../domain/use_cases/stock_document_use_cases.dart';
import 'inventory_controller.dart';
import 'inventory_events.dart';

class StockDocumentListController extends InventoryController {
  StockDocumentListController({
    required super.session,
    required super.events,
    super.onAccessDenied,
    required this.get,
  }) {
    events.addListener(_event);
  }
  final GetStockDocuments get;
  StockDocumentQuery query = const StockDocumentQuery();
  List<StockDocumentSummary> rows = const [];
  int totalElements = 0, totalPages = 0, _generation = 0, _revision = 0;
  bool loading = false, hasLoaded = false, _scheduled = false;
  Failure? failure;
  final endless = EndlessPages<StockDocumentSummary>((row) => row.id);
  bool get hasMore => query.page < totalPages - 1;
  Timer? _debounce;
  void _event() {
    if (_revision == events.revision) return;
    _revision = events.revision;
    final change = events.change;
    if (change?.kind != InventoryChangeKind.document ||
        !current ||
        query.warehouseId != null && query.warehouseId != change?.warehouseId) {
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

  void search(String value) {
    _debounce?.cancel();
    ++_generation;
    query = query.copyWith(q: value.trim(), page: 0);
    changed();
    _debounce = Timer(const Duration(milliseconds: 350), load);
  }

  void filter(StockDocumentQuery value) {
    _debounce?.cancel();
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
    _debounce?.cancel();
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
    final result = await endless.read(
      page: q.page,
      fetch: (page) => read('documents', () => get(q.copyWith(page: page))),
      content: (data) => data.content,
      totalPages: (data) => data.totalPages,
      active: () => current && generation == _generation,
    );
    if (!current || generation != _generation) return;
    switch (result) {
      case Success(value: final pages):
        final data = pages.last;
        if (q.page > 0 && pages.rows.isEmpty && data.totalPages <= q.page) {
          query = q.copyWith(
            page: data.totalPages == 0 ? 0 : data.totalPages - 1,
          );
          await load();
          return;
        }
        if (pages.lastPage != q.page) {
          query = query.copyWith(page: pages.lastPage);
        }
        rows = pages.rows;
        totalElements = data.totalElements;
        totalPages = data.totalPages;
        hasLoaded = true;
      case Error(failure: final error):
        failure = error;
    }
    loading = false;
    changed();
  }

  /// Appends the next page; a failure keeps the rows already shown.
  Future<void> loadMore() async {
    if (!can('INVENTORY_VIEW') ||
        loading ||
        endless.loadingMore ||
        !hasMore ||
        _debounce?.isActive == true) {
      return;
    }
    final generation = ++_generation;
    final next = query.copyWith(page: query.page + 1);
    endless.begin();
    changed();
    final result = await read('documents', () => get(next));
    if (!current || generation != _generation) return;
    switch (result) {
      case Success(value: final data):
        query = next;
        rows = endless.append(rows, data.content);
        totalElements = data.totalElements;
        totalPages = data.totalPages;
      case Error(failure: final error):
        endless.fail(error);
    }
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
