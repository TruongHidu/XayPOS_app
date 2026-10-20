import 'dart:async';
import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/inventory_entities.dart';
import '../../domain/entities/inventory_queries.dart';
import '../../domain/use_cases/inventory_use_cases.dart';
import 'inventory_controller.dart';
import 'inventory_events.dart';

class WarehouseSelectorController extends InventoryController {
  WarehouseSelectorController({
    required super.session,
    required super.events,
    super.onAccessDenied,
    required this.get,
    required this.detail,
  }) {
    events.addListener(_event);
  }
  final GetWarehouses get;
  final GetWarehouse detail;
  Warehouse? selected;
  WarehouseQuery query = const WarehouseQuery(sortBy: 'name', direction: 'asc');
  List<Warehouse> rows = const [];
  int totalPages = 0,
      totalElements = 0,
      _generation = 0,
      _selectionGeneration = 0,
      _revision = 0;
  bool loading = false, initial = true, _scheduled = false;
  Failure? failure, selectionFailure;
  Timer? _debounce;
  void select(Warehouse value) {
    if (!can('INVENTORY_VIEW')) return;
    ++_selectionGeneration;
    selected = value;
    selectionFailure = null;
    changed();
  }

  void _event() {
    if (_revision == events.revision) return;
    _revision = events.revision;
    final change = events.change;
    if (change?.kind != InventoryChangeKind.warehouse || !current) return;
    if (change!.deleted && selected?.id == change.warehouseId) {
      ++_selectionGeneration;
      selected = null;
      selectionFailure = null;
      changed();
    } else if (change.warehouse?.id == selected?.id &&
        change.warehouse != null) {
      selected = change.warehouse;
      changed();
    }
    if (_scheduled) return;
    _scheduled = true;
    Future.microtask(() async {
      _scheduled = false;
      if (!current) return;
      await Future.wait([load(), refreshSelection()]);
    });
  }

  Future<void> refreshSelection() async {
    final id = selected?.id;
    if (id == null || !can('INVENTORY_VIEW')) return;
    final generation = ++_selectionGeneration;
    final result = await read('selected', () => detail(id));
    if (!current || generation != _selectionGeneration) return;
    switch (result) {
      case Success(value: final value):
        if (value.id == id) {
          selected = value;
          selectionFailure = null;
        }
      case Error(failure: final error):
        selectionFailure = error;
        if (error.type == FailureType.notFound) selected = null;
    }
    changed();
  }

  void search(String text) {
    _debounce?.cancel();
    ++_generation;
    query = query.copyWith(q: text.trim(), page: 0);
    changed();
    _debounce = Timer(const Duration(milliseconds: 350), load);
  }

  void page(int value) {
    if (value < 0 || value >= totalPages && value != 0) return;
    query = query.copyWith(page: value);
    unawaited(load());
  }

  Future<void> load() async {
    if (!can('INVENTORY_VIEW')) return;
    _debounce?.cancel();
    final generation = ++_generation;
    final q = query;
    if (!q.valid) {
      loading = false;
      failure = InventoryController.invalid({'q': 'Từ khóa tối đa 100 ký tự.'});
      changed();
      return;
    }
    loading = true;
    failure = null;
    changed();
    final result = await read('selector', () => get(q));
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
        totalPages = data.totalPages;
        totalElements = data.totalElements;
        if (initial) {
          selected ??= rows.where((r) => r.isDefault).firstOrNull;
          initial = false;
        }
      case Error(failure: final error):
        failure = error;
    }
    loading = false;
    changed();
  }

  @override
  void dispose() {
    ++_generation;
    ++_selectionGeneration;
    _debounce?.cancel();
    events.removeListener(_event);
    super.dispose();
  }
}
