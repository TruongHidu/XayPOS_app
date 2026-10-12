import 'dart:async';

import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/table_entities.dart';
import '../../domain/entities/table_inputs.dart';
import '../../domain/entities/table_query.dart';
import '../../domain/use_cases/restaurant_table_use_cases.dart';
import '../../domain/use_cases/table_session_use_cases.dart';
import 'table_controller.dart';
import 'table_events.dart';

class TableTransferController extends TableController {
  TableTransferController({
    required super.session,
    required super.events,
    super.onAccessDenied,
    required this.sessionId,
    required this.getSession,
    required this.listTables,
    required this.transferSession,
    required this.keys,
  }) {
    _eventRevision = events.revision;
    _lastConflictingMutation = events.externalSessionBlocked(sessionId);
    events.addListener(_event);
  }

  final String sessionId;
  final DetailTableSession getSession;
  final ListRestaurantTable listTables;
  final TransferTableSession transferSession;
  final TableTransferKeyGenerator keys;

  TableSession? currentSession;
  Failure? sessionFailure;
  bool sessionLoading = false;
  int _sessionGeneration = 0;

  TableQuery query = const TableQuery(
    status: TableStatus.available,
    occupied: false,
    sortBy: 'code',
    direction: 'asc',
  );
  List<RestaurantTable> targets = const [];
  Failure? targetsFailure;
  bool targetsLoading = false;
  int totalElements = 0, totalPages = 0;
  int _targetsGeneration = 0;
  Timer? _debounce;

  RestaurantTable? selected;
  String reason = '';
  Failure? failure;
  TableSessionTransferResult? result;
  _TableTransferIntent? _intent;
  bool uncertain = false;
  int _eventRevision = 0;
  bool _lastConflictingMutation = false;

  bool get busy => events.transferPending(sessionId);
  bool get frozen => busy || uncertain;
  bool get conflictingMutation => _lastConflictingMutation;
  bool get canRetry =>
      uncertain && !busy && can('TABLE_TRANSFER') && _intent != null;
  bool get canSubmit =>
      !frozen &&
      !conflictingMutation &&
      can('TABLE_TRANSFER') &&
      currentSession?.status == TableSessionStatus.open &&
      selected != null &&
      selected!.id != currentSession!.tableId &&
      _eligible(selected!);

  void _event() {
    final external = events.externalSessionBlocked(sessionId);
    if (_lastConflictingMutation != external) {
      _lastConflictingMutation = external;
      changed();
    }
    if (_eventRevision == events.revision) return;
    _eventRevision = events.revision;
    final change = events.change;
    if (frozen || change?.kind != TableChangeKind.session) return;
    if (change?.sessionId == sessionId) {
      unawaited(loadSession());
      unawaited(loadTargets());
    }
  }

  Future<void> loadContext() async {
    await Future.wait([loadSession(), loadTargets()]);
  }

  Future<void> loadSession() async {
    if (!can('TABLE_VIEW')) return;
    final generation = ++_sessionGeneration;
    sessionLoading = true;
    sessionFailure = null;
    changed();
    final response = await read(
      'transfer-session',
      () => getSession(sessionId),
    );
    if (!isCurrent || generation != _sessionGeneration) return;
    switch (response) {
      case Success(value: final value):
        if (value.id != sessionId) {
          sessionFailure = const Failure(
            type: FailureType.internal,
            code: 'INVALID_TABLE_RESPONSE',
            message: 'Máy chủ trả về phiên bàn không đúng yêu cầu.',
          );
        } else {
          currentSession = value;
          sessionFailure = null;
          if (selected?.id == value.tableId) selected = null;
        }
      case Error(failure: final error):
        sessionFailure = error;
        if (error.type == FailureType.notFound) currentSession = null;
    }
    sessionLoading = false;
    changed();
  }

  Future<void> loadTargets() async {
    if (!can('TABLE_VIEW')) return;
    final generation = ++_targetsGeneration;
    targetsLoading = true;
    targetsFailure = null;
    changed();
    final response = await read('transfer-targets', () => listTables(query));
    if (!isCurrent || generation != _targetsGeneration) return;
    switch (response) {
      case Success(value: final page):
        targets = page.content.where(_eligible).toList(growable: false);
        totalElements = page.totalElements;
        totalPages = page.totalPages;
        if (selected != null && !_eligible(selected!)) selected = null;
      case Error(failure: final error):
        targets = const [];
        targetsFailure = error;
        totalElements = totalPages = 0;
    }
    targetsLoading = false;
    changed();
  }

  bool _eligible(RestaurantTable table) =>
      table.id != currentSession?.tableId &&
      table.status == TableStatus.available &&
      !table.occupied &&
      (table.area == null || table.area!.active);

  void search(String value) {
    if (frozen) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      query = query.copyWith(q: value, page: 0);
      unawaited(loadTargets());
    });
  }

  void filterArea(TableAreaSummary? area) {
    if (frozen) return;
    query = query.copyWith(areaId: () => area?.id, page: 0);
    unawaited(loadTargets());
  }

  void setPage(int page) {
    if (frozen || page < 0 || page >= totalPages) return;
    query = query.copyWith(page: page);
    unawaited(loadTargets());
  }

  void select(RestaurantTable value) {
    if (frozen || !_eligible(value)) return;
    selected = value;
    failure = null;
    changed();
  }

  void setReason(String value) {
    if (frozen) return;
    reason = value;
    failure = null;
    changed();
  }

  Future<Result<TableSessionTransferResult>> submit() async {
    if (!canSubmit || busy) return const Error(TableController.expired);
    final baseline = currentSession!;
    final input = TransferTableSessionInput(
      targetTableId: selected!.id,
      expectedVersion: baseline.version,
      reason: reason,
    ).normalized();
    final validation = TableController.validate(input);
    final key = keys.next();
    if (validation != null || key.trim().isEmpty || key.length > 100) {
      failure =
          validation ??
          TableController.validation({
            'idempotencyKey': 'Key phải không trống và tối đa 100 ký tự.',
          });
      changed();
      return Error(failure!);
    }
    _intent = _TableTransferIntent(
      sourceTableId: baseline.tableId,
      input: input,
      key: key,
    );
    result = null;
    return _execute();
  }

  Future<Result<TableSessionTransferResult>> retry() async {
    if (!canRetry) return const Error(TableController.expired);
    return _execute();
  }

  Future<Result<TableSessionTransferResult>> _execute() async {
    final intent = _intent;
    if (intent == null || !can('TABLE_TRANSFER')) {
      return const Error(TableController.expired);
    }
    if (!events.lockTransfer(sessionId)) {
      return const Error(
        Failure(
          type: FailureType.conflict,
          code: 'TABLE_BUSY',
          message: 'Phiên này đang có thao tác chuyển bàn khác.',
        ),
      );
    }
    final previouslyUncertain = uncertain;
    ++_sessionGeneration;
    sessionLoading = false;
    failure = null;
    changed();
    try {
      final response = await transferSession(
        sessionId,
        intent.input,
        intent.key,
      );
      if (!isCurrent) return const Error(TableController.expired);
      switch (response) {
        case Success(value: final value):
          if (value.session.id != sessionId) {
            failure = const Failure(
              type: FailureType.internal,
              code: 'INVALID_TABLE_RESPONSE',
              message: 'Kết quả chuyển bàn không đúng phiên yêu cầu.',
            );
            uncertain = true;
            events.markTransferUnresolved(sessionId, true);
            return Error(failure!);
          }
          currentSession = value.session;
          result = value;
          sessionFailure = null;
          failure = null;
          uncertain = false;
          events.markTransferUnresolved(sessionId, false);
          _intent = null;
          selected = null;
          reason = '';
          events.emit(
            TableChange(
              TableChangeKind.session,
              value.session.tableId,
              sessionId: sessionId,
              relatedTableIds: {
                intent.sourceTableId,
                intent.input.targetTableId,
                value.session.tableId,
              },
            ),
          );
          unawaited(loadTargets());
          return response;
        case Error(failure: final error):
          failure = error;
          uncertain =
              error.isNetwork ||
              error.type == FailureType.internal ||
              previouslyUncertain;
          events.markTransferUnresolved(sessionId, uncertain);
          if (!uncertain) {
            _intent = null;
            unawaited(_reloadAfterRefusal());
          }
          return response;
      }
    } finally {
      events.unlockTransfer(sessionId);
      changed();
    }
  }

  Future<void> _reloadAfterRefusal() async {
    await Future.wait([loadSession(), loadTargets()]);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    ++_sessionGeneration;
    ++_targetsGeneration;
    events.removeListener(_event);
    super.dispose();
  }
}

class _TableTransferIntent {
  const _TableTransferIntent({
    required this.sourceTableId,
    required this.input,
    required this.key,
  });

  final String sourceTableId;
  final TransferTableSessionInput input;
  final String key;
}

class TableTransferHistoryController extends TableController {
  TableTransferHistoryController({
    required super.session,
    required super.events,
    super.onAccessDenied,
    required this.sessionId,
    required this.getTransfers,
  }) {
    _eventRevision = events.revision;
    events.addListener(_event);
  }

  final String sessionId;
  final GetTableSessionTransfers getTransfers;
  List<TableSessionTransferHistoryEntry> rows = const [];
  Failure? failure;
  bool loading = false, hasLoaded = false;
  int page = 0, totalPages = 0, totalElements = 0;
  int _generation = 0;
  int _eventRevision = 0;

  void _event() {
    if (_eventRevision == events.revision) return;
    _eventRevision = events.revision;
    if (events.change?.sessionId == sessionId) unawaited(load());
  }

  Future<void> load() async {
    final generation = ++_generation;
    loading = true;
    failure = null;
    changed();
    final response = await read(
      'transfer-history',
      () => getTransfers(sessionId, page: page, size: 20),
    );
    if (!isCurrent || generation != _generation) return;
    switch (response) {
      case Success(value: final value):
        rows = value.content;
        totalPages = value.totalPages;
        totalElements = value.totalElements;
        hasLoaded = true;
      case Error(failure: final error):
        failure = error;
    }
    loading = false;
    changed();
  }

  void setPage(int value) {
    if (loading || value < 0 || value >= totalPages) return;
    page = value;
    unawaited(load());
  }

  @override
  void dispose() {
    ++_generation;
    events.removeListener(_event);
    super.dispose();
  }
}
