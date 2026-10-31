import 'dart:async';
import '../../../../core/result/result.dart';
import '../../domain/entities/table_entities.dart';
import '../../domain/entities/table_inputs.dart';
import '../../domain/entities/table_query.dart';
import '../../domain/use_cases/table_area_use_cases.dart';
import 'table_controller.dart';
import 'table_list_controller.dart';
import 'table_events.dart';

class TableAreaController extends TableListController<TableArea> {
  TableAreaController({
    required super.session,
    required super.events,
    super.onAccessDenied,
    required ListTableArea list,
    required this.get,
    required this.createArea,
    required this.updateArea,
    required this.statusArea,
    required this.deleteArea,
  }) : super(
         kind: TableQueryKind.areas,
         list: list.call,
         idOf: (area) => area.id,
       ) {
    _eventRevision = events.revision;
    events.addListener(_event);
  }
  final DetailTableArea get;
  final CreateTableArea createArea;
  final UpdateTableArea updateArea;
  final SetStatusTableArea statusArea;
  final DeleteTableArea deleteArea;
  int _eventRevision = 0;
  void _event() {
    if (_eventRevision == events.revision) return;
    _eventRevision = events.revision;
    if (events.change?.kind == TableChangeKind.area) unawaited(load());
  }

  Future<Result<TableArea>> getDetail(String id) => detail(id, () => get(id));
  Future<Result<TableArea>> create(CreateTableAreaInput input) => mutate(
    'area:create',
    'TABLE_CREATE',
    () => createArea(input),
    invalid: TableController.validate(input),
    change: (v) => TableChange(
      TableChangeKind.area,
      v.id,
      area: TableAreaSummary(id: v.id, name: v.name, active: v.active),
    ),
  );
  Future<Result<TableArea>> update(
    TableArea baseline,
    UpdateTableAreaInput input,
  ) => mutate(
    'area:${baseline.id}',
    'TABLE_UPDATE',
    () => updateArea(baseline.id, input),
    invalid:
        TableController.snapshotVersion(
          input.expectedVersion,
          baseline.version,
        ) ??
        (input.isEmpty
            ? TableController.empty
            : TableController.validate(input)),
    change: (v) => TableChange(
      TableChangeKind.area,
      v.id,
      area: TableAreaSummary(id: v.id, name: v.name, active: v.active),
    ),
  );
  Future<Result<TableArea>> setStatus(TableArea baseline, bool active) =>
      mutate(
        'area:${baseline.id}',
        'TABLE_UPDATE',
        () => statusArea(baseline.id, active, baseline.version),
        change: (v) => TableChange(
          TableChangeKind.area,
          v.id,
          area: TableAreaSummary(id: v.id, name: v.name, active: v.active),
        ),
      );
  Future<Result<void>> delete(TableArea baseline) => mutate(
    'area:${baseline.id}',
    'TABLE_UPDATE',
    () => deleteArea(baseline.id, baseline.version),
    change: (_) =>
        TableChange(TableChangeKind.area, baseline.id, deleted: true),
  );
  @override
  void dispose() {
    events.removeListener(_event);
    super.dispose();
  }
}

class TableAreaSelectorController extends TableListController<TableArea> {
  TableAreaSelectorController({
    required super.session,
    required super.events,
    super.onAccessDenied,
    required ListTableArea list,
    required this.activeOnly,
  }) : super(
         kind: TableQueryKind.areas,
         list: list.call,
         idOf: (area) => area.id,
         query: TableQuery(
           active: activeOnly ? true : null,
           sortBy: 'name',
           direction: 'asc',
         ),
       ) {
    _eventRevision = events.revision;
    events.addListener(_event);
  }
  final bool activeOnly;
  @override
  void setQuery(TableQuery value, {bool debounce = false}) => super.setQuery(
    value.copyWith(active: () => activeOnly ? true : value.active),
    debounce: debounce,
  );
  int _eventRevision = 0;
  void _event() {
    if (_eventRevision == events.revision) return;
    _eventRevision = events.revision;
    if (events.change?.kind == TableChangeKind.area) unawaited(load());
  }

  @override
  void dispose() {
    events.removeListener(_event);
    super.dispose();
  }
}
