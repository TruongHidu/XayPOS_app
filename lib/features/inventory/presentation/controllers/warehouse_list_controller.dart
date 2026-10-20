import 'dart:async';
import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/inventory_entities.dart';
import '../../domain/entities/inventory_queries.dart';
import '../../domain/entities/inventory_inputs.dart';
import '../../domain/policies/inventory_validation.dart';
import '../../domain/use_cases/inventory_use_cases.dart';
import 'inventory_controller.dart';
import 'inventory_events.dart';

enum WarehouseAction { enable, disable, makeDefault, delete }

class WarehouseListController extends InventoryController {
  WarehouseListController({
    required super.session,
    required super.events,
    super.onAccessDenied,
    required this.get,
    required this.getDetail,
    required this.createWarehouse,
    required this.updateWarehouse,
    required this.setStatus,
    required this.makeDefault,
    required this.deleteWarehouse,
  }) {
    events.addListener(_event);
  }
  final GetWarehouses get;
  final GetWarehouse getDetail;
  final CreateWarehouse createWarehouse;
  final UpdateWarehouse updateWarehouse;
  final SetWarehouseStatus setStatus;
  final MakeDefaultWarehouse makeDefault;
  final DeleteWarehouse deleteWarehouse;
  WarehouseQuery query = const WarehouseQuery();
  List<Warehouse> rows = const [];
  int totalElements = 0, totalPages = 0, _generation = 0, _revision = 0;
  bool loading = false, hasLoaded = false, _scheduled = false;
  Failure? failure;
  CreateWarehouseInput? pendingCreate;
  Timer? _debounce;
  void _event() {
    if (_revision == events.revision) return;
    _revision = events.revision;
    if (events.change?.kind != InventoryChangeKind.warehouse || !current) {
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

  void filter({bool? active, String? sortBy, String? direction, int? size}) {
    _debounce?.cancel();
    ++_generation;
    query = query.copyWith(
      active: () => active,
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
    if (!can('INVENTORY_VIEW')) return;
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
    final result = await read('list', () => get(q));
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

  Future<Result<Warehouse>> detail(String id, {bool verify = false}) async {
    final result = await read('detail:$id', () => getDetail(id));
    if (result case Success(value: final value)) {
      if (value.id != id ||
          rows.any((r) => r.id == id && r.version > value.version)) {
        return const Error(InventoryController.invalidResponse);
      }
      if (current && verify) events.resolve(InventoryEvents.warehouseKey(id));
    }
    return result;
  }

  Future<Result<Warehouse>> create(CreateWarehouseInput input) async {
    if (!can('WAREHOUSE_CREATE')) {
      return const Error(InventoryController.denied);
    }
    final errors = InventoryValidation.warehouse(input.code, input.name);
    if (errors.isNotEmpty) return Error(InventoryController.invalid(errors));
    if (events.pending(InventoryEvents.createKey)) {
      return const Error(InventoryController.busy);
    }
    pendingCreate ??= input;
    final result = await mutate(
      InventoryEvents.createKey,
      'WAREHOUSE_CREATE',
      () => createWarehouse(input),
      applied: (value) => events.emit(
        InventoryChange(
          InventoryChangeKind.warehouse,
          value.id,
          warehouse: value,
        ),
      ),
    );
    if (current && events.verification(InventoryEvents.createKey) == null) {
      pendingCreate = null;
    }
    return result;
  }

  Future<Result<Warehouse>> update(
    Warehouse baseline,
    UpdateWarehouseInput input,
  ) {
    final errors = InventoryValidation.update(input);
    if (input.expectedVersion != baseline.version) {
      errors['expectedVersion'] = 'Dữ liệu đang sửa đã thay đổi.';
    }
    if (errors.isNotEmpty) {
      return Future.value(Error(InventoryController.invalid(errors)));
    }
    return mutate(
      InventoryEvents.warehouseKey(baseline.id),
      'WAREHOUSE_UPDATE',
      () => updateWarehouse(baseline.id, input),
      applied: (value) => events.emit(
        InventoryChange(
          InventoryChangeKind.warehouse,
          value.id,
          warehouse: value,
        ),
      ),
    );
  }

  Future<Result<Warehouse?>> act(
    Warehouse baseline,
    WarehouseAction action,
  ) async {
    final permission = action == WarehouseAction.delete
        ? 'WAREHOUSE_DELETE'
        : 'WAREHOUSE_UPDATE';
    if (!can(permission)) return const Error(InventoryController.denied);
    if ((action == WarehouseAction.disable ||
                action == WarehouseAction.delete) &&
            baseline.isDefault ||
        action == WarehouseAction.makeDefault && !baseline.active) {
      return Error(
        InventoryController.invalid({
          'form': 'Thao tác không khả dụng với trạng thái kho hiện tại.',
        }),
      );
    }
    final version = WarehouseVersionInput(baseline.version);
    return mutate<Warehouse?>(
      InventoryEvents.warehouseKey(baseline.id),
      permission,
      () async {
        if (action == WarehouseAction.delete) {
          return switch (await deleteWarehouse(baseline.id, version)) {
            Success() => const Success(null),
            Error(failure: final f) => Error(f),
          };
        }
        return action == WarehouseAction.makeDefault
            ? makeDefault(baseline.id, version)
            : setStatus(
                baseline.id,
                SetWarehouseStatusInput(
                  baseline.version,
                  action == WarehouseAction.enable,
                ),
              );
      },
      applied: (value) => events.emit(
        InventoryChange(
          InventoryChangeKind.warehouse,
          baseline.id,
          warehouse: value,
          deleted: action == WarehouseAction.delete,
        ),
      ),
    );
  }

  /// A timeout has no idempotency key: search the exact code without resending POST.
  Future<Result<List<Warehouse>>> inspectCreation(String code) async {
    final found = <Warehouse>[];
    var pages = 1;
    for (var page = 0; page < pages; page++) {
      if (!can('INVENTORY_VIEW')) {
        return const Error(InventoryController.denied);
      }
      final result = await read(
        'inspect:$page',
        () => get(
          WarehouseQuery(
            q: code.trim().toUpperCase(),
            page: page,
            size: 100,
            sortBy: 'code',
            direction: 'asc',
          ),
        ),
      );
      switch (result) {
        case Error(failure: final error):
          return Error(error);
        case Success(value: final data):
          if (data.totalPages > 10000) {
            return const Error(InventoryController.invalidResponse);
          }
          if (page == 0) pages = data.totalPages;
          found.addAll(
            data.content.where((row) => row.code == code.trim().toUpperCase()),
          );
      }
    }
    return Success(List.unmodifiable(found));
  }

  void acknowledgeCreation() {
    if (current) {
      events.resolve(InventoryEvents.createKey);
      pendingCreate = null;
    }
  }

  @override
  void dispose() {
    ++_generation;
    _debounce?.cancel();
    events.removeListener(_event);
    super.dispose();
  }
}
