import 'dart:async';
import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/table_entities.dart';
import '../../domain/entities/table_inputs.dart';
import '../../domain/entities/table_query.dart';
import '../../domain/use_cases/table_session_use_cases.dart';
import '../../domain/validation/table_validation.dart';
import 'table_controller.dart';
import 'table_list_controller.dart';
import 'table_events.dart';

class TableSessionController extends TableListController<TableSession> {
  TableSessionController({
    required super.session,
    required super.events,
    super.onAccessDenied,
    required this.tableId,
    required ListTableSession list,
    required this.get,
    required this.getCurrent,
    required this.openSession,
    required this.updateSession,
    required this.cancelSession,
  }) : super(
         kind: TableQueryKind.sessions,
         list: list.call,
         query: TableQuery(
           tableId: tableId.isEmpty ? null : tableId,
           sortBy: 'openedAt',
         ),
       ) {
    _eventRevision = events.revision;
    events.addListener(_event);
  }
  final String tableId;
  final DetailTableSession get;
  final CurrentTableSession getCurrent;
  final OpenTableSession openSession;
  final UpdateTableSession updateSession;
  final CancelTableSession cancelSession;
  TableSession? current;
  Failure? currentFailure;
  bool currentLoading = false;
  int _currentGeneration = 0;
  int _eventRevision = 0;
  bool _watchCurrent = false, _watchHistory = false;
  void _event() {
    if (_eventRevision == events.revision) return;
    _eventRevision = events.revision;
    final change = events.change;
    if (change?.kind != TableChangeKind.refresh &&
        tableId.isNotEmpty &&
        change?.id != tableId &&
        change?.relatedTableIds.contains(tableId) != true) {
      return;
    }
    if (change?.kind == TableChangeKind.session ||
        change?.kind == TableChangeKind.refresh) {
      if (_watchCurrent) unawaited(loadCurrent());
      if (_watchHistory) unawaited(load());
    }
  }

  @override
  Future<void> load() {
    _watchHistory = true;
    return super.load();
  }

  Future<void> loadCurrent() async {
    _watchCurrent = true;
    final generation = ++_currentGeneration;
    currentLoading = true;
    currentFailure = null;
    changed();
    final result = await read('current', () => getCurrent(tableId));
    if (!isCurrent || generation != _currentGeneration) return;
    switch (result) {
      case Success(value: final v):
        current = v;
      case Error(failure: final f):
        currentFailure = f;
        if (f.type == FailureType.notFound) current = null;
    }
    currentLoading = false;
    changed();
  }

  Future<Result<TableSession>> getDetail(String id) =>
      detail(id, () => get(id));
  Future<Result<TableSession>> open(
    RestaurantTable b,
    OpenTableSessionInput input,
  ) => mutate(
    'table:${b.id}',
    'TABLE_OPEN',
    () => openSession(b.id, input),
    invalid:
        TableController.snapshotVersion(input.expectedVersion, b.version) ??
        (!b.canOpen || b.occupied || b.status != TableStatus.available
            ? TableController.occupied
            : TableController.validate(input)),
    change: (v) => TableChange(TableChangeKind.session, v.tableId),
  );
  Future<Result<TableSession>> update(
    TableSession b,
    UpdateTableSessionInput input,
  ) => mutate(
    'session:${b.id}',
    'TABLE_OPEN',
    () => updateSession(b.id, input),
    invalid:
        TableController.snapshotVersion(input.expectedVersion, b.version) ??
        (b.status != TableSessionStatus.open
            ? TableController.terminal
            : input.isEmpty
            ? TableController.empty
            : TableController.validate(input)),
    change: (v) => TableChange(TableChangeKind.session, v.tableId),
  );
  Future<Result<TableSession>> cancel(TableSession b, String reason) => mutate(
    'session:${b.id}',
    'TABLE_CLOSE',
    () => cancelSession(b.id, reason, b.version),
    invalid: b.status != TableSessionStatus.open
        ? TableController.terminal
        : TableValidation.text(reason, 1000, required: true) != null
        ? TableController.validation({
            'reason': TableValidation.text(reason, 1000, required: true)!,
          })
        : null,
    change: (v) => TableChange(TableChangeKind.session, v.tableId),
  );
  @override
  void dispose() {
    events.removeListener(_event);
    ++_currentGeneration;
    current = null;
    super.dispose();
  }
}
