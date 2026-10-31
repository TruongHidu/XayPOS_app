import 'dart:async';
import '../../../../core/result/result.dart';
import '../../domain/entities/table_entities.dart';
import '../../domain/entities/table_inputs.dart';
import '../../domain/entities/table_query.dart';
import '../../domain/use_cases/restaurant_table_use_cases.dart';
import 'table_controller.dart';
import 'table_list_controller.dart';
import 'table_events.dart';

class RestaurantTableController extends TableListController<RestaurantTable> {
  RestaurantTableController({
    required super.session,
    required super.events,
    super.onAccessDenied,
    required ListRestaurantTable list,
    required this.get,
    required this.createTable,
    required this.updateTable,
    required this.statusTable,
    required this.assignTable,
    required this.deleteTable,
  }) : super(
         kind: TableQueryKind.tables,
         list: list.call,
         idOf: (table) => table.id,
       ) {
    _eventRevision = events.revision;
    events.addListener(_event);
  }
  final DetailRestaurantTable get;
  final CreateRestaurantTable createTable;
  final UpdateRestaurantTable updateTable;
  final SetStatusRestaurantTable statusTable;
  final AssignAreaRestaurantTable assignTable;
  final DeleteRestaurantTable deleteTable;
  TableAreaSummary? selectedArea;
  int _eventRevision = 0;
  void filterArea(TableAreaSummary? area) {
    selectedArea = area;
    setQuery(query.copyWith(areaId: () => area?.id));
  }

  void _event() {
    if (_eventRevision == events.revision) return;
    _eventRevision = events.revision;
    final e = events.change;
    if (e?.kind == TableChangeKind.area &&
        e!.id == query.areaId &&
        e.area != null) {
      selectedArea = e.area;
    }
    if (e?.kind == TableChangeKind.area && e!.deleted && e.id == query.areaId) {
      selectedArea = null;
      query = query.copyWith(areaId: () => null, page: 0);
    }
    unawaited(load());
  }

  Future<Result<RestaurantTable>> getDetail(String id) =>
      detail(id, () => get(id));
  Future<Result<RestaurantTable>> create(CreateRestaurantTableInput input) =>
      mutate(
        'table:create',
        'TABLE_CREATE',
        () => createTable(input),
        invalid: TableController.validate(input),
        change: (v) => TableChange(TableChangeKind.table, v.id),
      );
  Future<Result<RestaurantTable>> update(
    RestaurantTable b,
    UpdateRestaurantTableInput input,
  ) => mutate(
    'table:${b.id}',
    'TABLE_UPDATE',
    () => updateTable(b.id, input),
    invalid:
        TableController.snapshotVersion(input.expectedVersion, b.version) ??
        (input.isEmpty
            ? TableController.empty
            : b.occupied &&
                  ((input.code != null &&
                          input.code!.trim().toUpperCase() != b.code) ||
                      (input.capacity != null && input.capacity != b.capacity))
            ? TableController.occupied
            : TableController.validate(input)),
    change: (v) => TableChange(TableChangeKind.table, v.id),
  );
  Future<Result<RestaurantTable>> setStatus(
    RestaurantTable b,
    TableStatus status,
  ) => mutate(
    'table:${b.id}',
    'TABLE_UPDATE',
    () => statusTable(b.id, status, b.version),
    invalid: b.occupied && status == TableStatus.inactive
        ? TableController.occupied
        : null,
    change: (v) => TableChange(TableChangeKind.table, v.id),
  );
  Future<Result<RestaurantTable>> assignArea(
    RestaurantTable b,
    TableAreaSummary? area,
  ) => mutate(
    'table:${b.id}',
    'TABLE_UPDATE',
    () => assignTable(b.id, area?.id, b.version),
    invalid: b.occupied
        ? TableController.occupied
        : area != null && !area.active
        ? TableController.validation({'areaId': 'Chọn khu vực đang hoạt động.'})
        : null,
    change: (v) => TableChange(TableChangeKind.table, v.id),
  );
  Future<Result<void>> delete(RestaurantTable b) => mutate(
    'table:${b.id}',
    'TABLE_UPDATE',
    () => deleteTable(b.id, b.version),
    invalid: b.occupied ? TableController.occupied : null,
    change: (_) => TableChange(TableChangeKind.table, b.id, deleted: true),
  );
  @override
  void dispose() {
    events.removeListener(_event);
    super.dispose();
  }
}
