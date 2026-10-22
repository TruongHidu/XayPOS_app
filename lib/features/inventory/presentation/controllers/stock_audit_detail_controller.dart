import 'dart:async';
import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/inventory_quantity.dart';
import '../../domain/entities/stock_audit.dart';
import '../../domain/entities/stock_audit_inputs.dart';
import '../../domain/entities/stock_audit_queries.dart';
import '../../domain/use_cases/stock_audit_use_cases.dart';
import 'inventory_controller.dart';
import 'inventory_events.dart';
import 'stock_audit_controller.dart';

class StockAuditDraftRow {
  const StockAuditDraftRow({
    required this.baseline,
    required this.rawQuantity,
    required this.note,
    required this.generation,
  });
  final StockAuditItem baseline;
  final String rawQuantity, note;
  final int generation;
  InventoryQuantity? get quantity {
    try {
      return InventoryQuantity.parse(rawQuantity.trim().replaceAll(',', '.'));
    } on FormatException {
      return null;
    }
  }

  String? get error => rawQuantity.trim().isEmpty
      ? 'Nhập số đếm; ô trống không xóa số đã lưu.'
      : quantity == null
      ? 'Số không âm, tối đa 11 chữ số nguyên và 3 số lẻ.'
      : note.length > 1000
      ? 'Ghi chú dòng tối đa 1000 ký tự.'
      : null;
  bool get noteChanged => note.trim() != (baseline.note ?? '').trim();
  bool get dirty =>
      quantity == null && rawQuantity.trim().isNotEmpty ||
      quantity != baseline.countedQuantity ||
      noteChanged;
}

enum StockAuditCommand { note, start, counts, confirm, cancel }

class StockAuditPendingCommand {
  const StockAuditPendingCommand(
    this.kind,
    this.baselineVersion,
    this.operation, {
    this.rows = const {},
    this.note,
  });
  final StockAuditCommand kind;
  final int baselineVersion;
  final Future<Result<StockAuditDetail>> Function() operation;
  final Map<String, StockAuditDraftRow> rows;
  final String? note;
}

/// Header and paged rows are independent reads. Drafts belong to the audit, not
/// its currently mounted page; no background read replaces typed values.
class StockAuditDetailController extends StockAuditController {
  StockAuditDetailController({
    required super.session,
    required super.events,
    super.onAccessDenied,
    required this.id,
    required this.get,
    required this.getItems,
    required this.updateNote,
    required this.start,
    required this.updateCounts,
    required this.confirm,
    required this.cancel,
  }) {
    events.addListener(_event);
  }

  final String id;
  final GetStockAudit get;
  final GetStockAuditItems getItems;
  final UpdateStockAuditNote updateNote;
  final StartStockAudit start;
  final UpdateStockAuditCounts updateCounts;
  final ConfirmStockAudit confirm;
  final CancelStockAudit cancel;
  StockAuditDetail? audit;
  StockAuditItemQuery query = const StockAuditItemQuery();
  List<StockAuditItem> rows = const [];
  final Map<String, StockAuditDraftRow> _drafts = {};
  final Map<String, int> _epochs = {};
  Map<String, StockAuditDraftRow> get drafts => Map.unmodifiable(_drafts);
  int totalElements = 0,
      totalPages = 0,
      _headerGeneration = 0,
      _itemsGeneration = 0,
      _editGeneration = 0,
      _revision = 0;
  int savedInLastRun = 0;
  bool loading = false,
      itemsLoading = false,
      itemsLoaded = false,
      saving = false,
      verifying = false;
  bool needsReview = false,
      hasCompared = false,
      snapshotStale = false,
      stockMayHaveChanged = false;
  Failure? failure, itemFailure;
  String? notice;
  String? headerNoteDraft;
  Timer? _debounce;
  StockAuditPendingCommand? pendingCommand;
  String get key => InventoryEvents.auditKey(id);
  bool get busy => saving || verifying || events.pending(key);
  bool get dirty => _drafts.isNotEmpty || headerNoteDraft != null;
  bool get hasCountDrafts => _drafts.isNotEmpty;
  int get dirtyCount => _drafts.length;
  bool get requiresReview =>
      needsReview || pendingCommand != null || events.verification(key) != null;
  bool get mutableState =>
      audit?.status == StockAuditStatus.draft ||
      audit?.status == StockAuditStatus.counting;
  bool get editable =>
      canManage &&
      audit?.status == StockAuditStatus.counting &&
      !busy &&
      !loading &&
      !requiresReview &&
      !snapshotStale;
  bool get headerEditable =>
      canManage && mutableState && !busy && !loading && !requiresReview;
  bool get canSaveDrafts =>
      dirty && headerEditable && (!hasCountDrafts || editable);
  bool get canPost =>
      canConfirm &&
      audit?.status == StockAuditStatus.counting &&
      !busy &&
      !loading &&
      !requiresReview &&
      !snapshotStale &&
      !dirty &&
      audit!.itemCount > 0 &&
      audit!.countedItemCount == audit!.itemCount;
  int epoch(String itemId) => _epochs[itemId] ?? 0;
  StockAuditDraftRow? draft(String itemId) => _drafts[itemId];

  void _event() {
    if (_revision == events.revision) return;
    _revision = events.revision;
    final change = events.change;
    if (!canView ||
        audit == null ||
        change?.warehouseId != null &&
            change!.warehouseId != audit!.warehouseId) {
      return;
    }
    if (change?.kind == InventoryChangeKind.balance ||
        change?.kind == InventoryChangeKind.orderStock) {
      // Order signals also include reserve/release: only backend decides staleness.
      stockMayHaveChanged = true;
      changed();
    }
  }

  Future<void> load() async {
    if (!canView || busy) return;
    await loadHeader();
    if (canView && audit != null && audit!.status != StockAuditStatus.draft) {
      await loadItems();
    }
  }

  Future<void> loadHeader() async {
    if (!canView || events.pending(key)) return;
    final generation = ++_headerGeneration;
    loading = true;
    if (!requiresReview) failure = null;
    changed();
    final response = await auditRead('audit-header', () => get(id));
    if (!canView || generation != _headerGeneration) return;
    switch (response) {
      case Success(value: final value):
        if (!_valid(value)) {
          failure = InventoryController.invalidResponse;
          needsReview = true;
        } else {
          if (dirty && audit != null && value.version != audit!.version) {
            needsReview = true;
            hasCompared = false;
            failure = const Failure(
              type: FailureType.conflict,
              code: 'CONCURRENT_STOCK_AUDIT_UPDATE',
              message:
                  'Phiên đã thay đổi trên máy chủ. Bản nhập được giữ; hãy đối chiếu trước khi lưu.',
            );
            events.requireVerification(key, failure!);
          }
          audit = value;
        }
      case Error(failure: final error):
        failure = error;
        if (error.type == FailureType.notFound) audit = null;
    }
    loading = false;
    changed();
  }

  bool _valid(StockAuditDetail value) =>
      value.id == id &&
      (audit == null ||
          value.warehouseId == audit!.warehouseId &&
              value.version >= audit!.version);

  Future<void> loadItems() async {
    if (!canView || audit == null || audit!.status == StockAuditStatus.draft) {
      return;
    }
    _debounce?.cancel();
    final generation = ++_itemsGeneration, q = query;
    if (!q.valid) {
      itemFailure = InventoryController.invalid({
        'query': 'Bộ lọc dòng kiểm kê không hợp lệ.',
      });
      itemsLoading = false;
      changed();
      return;
    }
    itemsLoading = true;
    itemFailure = null;
    changed();
    final response = await auditRead('audit-items', () => getItems(id, q));
    if (!canView || generation != _itemsGeneration) return;
    switch (response) {
      case Success(value: final data):
        if (q.page > 0 && data.content.isEmpty && data.totalPages <= q.page) {
          query = q.copyWith(
            page: data.totalPages == 0 ? 0 : data.totalPages - 1,
          );
          await loadItems();
          return;
        }
        final oldRows = {for (final row in rows) row.id: row};
        for (final row in data.content) {
          final old = oldRows[row.id];
          if (!_drafts.containsKey(row.id) &&
              old != null &&
              (old.countedQuantity != row.countedQuantity ||
                  old.note != row.note)) {
            _epochs[row.id] = epoch(row.id) + 1;
          }
        }
        rows = data.content;
        totalElements = data.totalElements;
        totalPages = data.totalPages;
        itemsLoaded = true;
      case Error(failure: final error):
        itemFailure = error;
    }
    itemsLoading = false;
    changed();
  }

  void search(String value) {
    _debounce?.cancel();
    ++_itemsGeneration;
    query = query.copyWith(q: value.trim(), page: 0);
    changed();
    _debounce = Timer(const Duration(milliseconds: 350), loadItems);
  }

  void filter(StockAuditItemQuery value) {
    query = value.copyWith(page: 0);
    unawaited(loadItems());
  }

  void page(int value) {
    if (value < 0 || value >= totalPages && value != 0) return;
    query = query.copyWith(page: value);
    unawaited(loadItems());
  }

  void edit(StockAuditItem item, {String? rawQuantity, String? note}) {
    if (!editable) return;
    final old = _drafts[item.id];
    final value = StockAuditDraftRow(
      baseline: old?.baseline ?? item,
      rawQuantity:
          rawQuantity ??
          old?.rawQuantity ??
          item.countedQuantity?.toString().replaceAll('.', ',') ??
          '',
      note: note ?? old?.note ?? item.note ?? '',
      generation: ++_editGeneration,
    );
    if (value.dirty) {
      _drafts[item.id] = value;
    } else {
      _drafts.remove(item.id);
    }
    notice = null;
    changed();
  }

  void restore(String itemId) {
    if (!canManage || busy) return;
    _drafts.remove(itemId);
    _epochs[itemId] = epoch(itemId) + 1;
    changed();
  }

  void discardDrafts() {
    if (!current || busy) return;
    for (final itemId in _drafts.keys) {
      _epochs[itemId] = epoch(itemId) + 1;
    }
    _drafts.clear();
    headerNoteDraft = null;
    changed();
  }

  void setHeaderNoteDraft(String value) {
    if (!canManage || busy || !mutableState) return;
    headerNoteDraft = value.trim() == (audit?.note ?? '').trim() ? null : value;
    changed();
  }

  void _publish(StockAuditDetail value, {bool posted = false}) {
    events.emit(
      InventoryChange(
        InventoryChangeKind.audit,
        value.warehouseId,
        auditId: id,
      ),
    );
    if (posted && value.adjustmentDocumentId != null) {
      events.emit(
        InventoryChange(
          InventoryChangeKind.document,
          value.warehouseId,
          documentId: value.adjustmentDocumentId,
          auditId: id,
        ),
      );
      events.emit(
        InventoryChange(
          InventoryChangeKind.balance,
          value.warehouseId,
          documentId: value.adjustmentDocumentId,
          auditId: id,
        ),
      );
    }
  }

  bool _allowed(StockAuditCommand kind) =>
      kind == StockAuditCommand.confirm ? canConfirm : canManage;
  Future<Result<StockAuditDetail>> _run(
    StockAuditPendingCommand command, {
    bool insideSave = false,
  }) async {
    if (!_allowed(command.kind) || !insideSave && busy) {
      return const Error(InventoryController.denied);
    }
    if (!events.lock(key)) return const Error(InventoryController.busy);
    ++_headerGeneration;
    ++_itemsGeneration;
    _debounce?.cancel();
    loading = false;
    itemsLoading = false;
    failure = null;
    changed();
    try {
      final response = await command.operation();
      if (!_allowed(command.kind)) {
        return const Error(InventoryController.denied);
      }
      switch (response) {
        case Success(value: final value):
          if (!_valid(value) || value.version < command.baselineVersion) {
            throw const FormatException('Wrong audit mutation response');
          }
          audit = value;
          if (command.kind == StockAuditCommand.note) headerNoteDraft = null;
          if (command.kind == StockAuditCommand.cancel) {
            for (final itemId in _drafts.keys) {
              _epochs[itemId] = epoch(itemId) + 1;
            }
            _drafts.clear();
            headerNoteDraft = null;
          }
          pendingCommand = null;
          needsReview = false;
          hasCompared = false;
          events.resolve(key);
          _publish(value, posted: command.kind == StockAuditCommand.confirm);
        case Error(failure: final error):
          failure = error;
          await report(error);
          if (!canView) return const Error(InventoryController.denied);
          snapshotStale =
              snapshotStale || error.code == 'STOCK_AUDIT_SNAPSHOT_STALE';
          if (InventoryController.unknown(error)) {
            pendingCommand = command;
          } else if (identical(pendingCommand, command)) {
            // A replay that receives a definite rejection ends the uncertain
            // intent. A fresh read and explicit review are still required.
            pendingCommand = null;
          }
          if (InventoryController.unknown(error) ||
              error.type == FailureType.conflict) {
            needsReview = true;
            hasCompared = false;
            events.requireVerification(key, error);
          }
      }
      return response;
    } catch (_) {
      if (current) {
        failure = InventoryController.invalidResponse;
        pendingCommand = command;
        needsReview = true;
        hasCompared = false;
        events.requireVerification(key, failure!);
      }
      return const Error(InventoryController.invalidResponse);
    } finally {
      if (current) {
        events.unlock(key);
        changed();
      }
    }
  }

  Future<Result<StockAuditDetail>> saveNote(String? note) async {
    if (!headerEditable || (note?.length ?? 0) > 2000) {
      return Error(
        InventoryController.invalid({
          'note': 'Chưa thể sửa hoặc ghi chú vượt 2000 ký tự.',
        }),
      );
    }
    final input = UpdateStockAuditNoteInput(
      expectedVersion: audit!.version,
      note: note,
    );
    setHeaderNoteDraft(note ?? '');
    final response = await _run(
      StockAuditPendingCommand(
        StockAuditCommand.note,
        audit!.version,
        () => updateNote(id, input),
        note: note,
      ),
    );
    if (response is Success<StockAuditDetail> && canView) await loadItems();
    return response;
  }

  Future<Result<StockAuditDetail>> startCounting() async {
    if (!headerEditable || audit!.status != StockAuditStatus.draft) {
      return const Error(InventoryController.denied);
    }
    final input = StockAuditTransitionInput(expectedVersion: audit!.version);
    final response = await _run(
      StockAuditPendingCommand(
        StockAuditCommand.start,
        audit!.version,
        () => start(id, input),
      ),
    );
    if (response is Success<StockAuditDetail> && canView) await loadItems();
    return response;
  }

  Future<Result<StockAuditDetail>> cancelAudit(String? note) async {
    if (!headerEditable || (note?.length ?? 0) > 2000) {
      return const Error(InventoryController.denied);
    }
    final input = CancelStockAuditInput(
      expectedVersion: audit!.version,
      note: note,
    );
    return _run(
      StockAuditPendingCommand(
        StockAuditCommand.cancel,
        audit!.version,
        () => cancel(id, input),
        note: note,
      ),
    );
  }

  Future<Result<StockAuditDetail>> post() async {
    if (!canPost) return const Error(InventoryController.denied);
    final input = StockAuditTransitionInput(expectedVersion: audit!.version);
    return _run(
      StockAuditPendingCommand(
        StockAuditCommand.confirm,
        audit!.version,
        () => confirm(id, input),
      ),
    );
  }

  Future<Result<StockAuditDetail>> saveCounts() async {
    if (!editable || !hasCountDrafts) {
      return const Error(InventoryController.denied);
    }
    final errors = <String, String>{
      for (final e in _drafts.entries)
        if (e.value.error != null) e.key: e.value.error!,
    };
    if (errors.isNotEmpty) {
      failure = InventoryController.invalid(errors);
      changed();
      return Error(failure!);
    }
    final edits = Map<String, StockAuditDraftRow>.of(_drafts).entries.toList();
    saving = true;
    savedInLastRun = 0;
    notice = null;
    changed();
    try {
      for (var offset = 0; offset < edits.length; offset += 100) {
        if (!canManage || requiresReview) {
          return const Error(InventoryController.denied);
        }
        final batch = Map<String, StockAuditDraftRow>.fromEntries(
          edits.skip(offset).take(100),
        );
        final input = StockAuditCountsInput(
          expectedVersion: audit!.version,
          items: [
            for (final e in batch.entries)
              StockAuditCountInput(
                auditItemId: e.key,
                countedQuantity: e.value.quantity!,
                note: e.value.noteChanged ? e.value.note : null,
              ),
          ],
        );
        final response = await _run(
          StockAuditPendingCommand(
            StockAuditCommand.counts,
            audit!.version,
            () => updateCounts(id, input),
            rows: Map.unmodifiable(batch),
          ),
          insideSave: true,
        );
        if (!canView) return const Error(InventoryController.denied);
        if (response case Error(failure: final error)) {
          notice =
              'Đã lưu $savedInLastRun dòng; còn ${_drafts.length} dòng chưa được xác nhận lưu.';
          return Error(error);
        }
        _acceptRows(batch);
        savedInLastRun += batch.length;
      }
      notice = 'Đã lưu $savedInLastRun dòng số đếm.';
      await loadItems();
      return Success(audit!);
    } finally {
      if (current) {
        saving = false;
        changed();
      }
    }
  }

  void _acceptRows(Map<String, StockAuditDraftRow> accepted) {
    rows = [
      for (final row in rows)
        if (accepted[row.id] case final StockAuditDraftRow edit)
          StockAuditItem(
            id: row.id,
            ingredientId: row.ingredientId,
            sku: row.sku,
            name: row.name,
            unit: row.unit,
            systemQuantity: row.systemQuantity,
            countedQuantity: edit.quantity,
            differenceQuantity: StockAuditDifference.between(
              edit.quantity!,
              row.systemQuantity,
            ),
            referenceUnitCostSnapshot: row.referenceUnitCostSnapshot,
            note: !edit.noteChanged
                ? row.note
                : edit.note.trim().isEmpty
                ? null
                : edit.note.trim(),
          )
        else
          row,
    ];
    for (final e in accepted.entries) {
      if (_drafts[e.key]?.generation == e.value.generation) {
        _drafts.remove(e.key);
        _epochs[e.key] = epoch(e.key) + 1;
      }
    }
  }

  /// Read-only reconciliation. Never applies a fresh version to an old write.
  Future<void> verify() async {
    if (!canView || busy) return;
    verifying = true;
    changed();
    try {
      final response = await auditRead('audit-verify', () => get(id));
      if (!canView) return;
      if (response case Error(failure: final error)) {
        failure = error;
        return;
      }
      final value = (response as Success<StockAuditDetail>).value;
      if (!_valid(value)) {
        failure = InventoryController.invalidResponse;
        return;
      }
      audit = value;
      final pending = pendingCommand;
      var applied = pending == null;
      if (pending != null) {
        final countComparison = pending.kind == StockAuditCommand.counts
            ? await _comparePendingRows(pending)
            : false;
        if (pending.kind == StockAuditCommand.counts &&
            countComparison == null) {
          return;
        }
        applied = switch (pending.kind) {
          StockAuditCommand.start =>
            value.status == StockAuditStatus.counting ||
                value.status == StockAuditStatus.confirmed,
          StockAuditCommand.confirm =>
            value.status == StockAuditStatus.confirmed,
          StockAuditCommand.cancel =>
            value.status == StockAuditStatus.cancelled,
          StockAuditCommand.note =>
            (value.note ?? '').trim() == (pending.note ?? '').trim(),
          StockAuditCommand.counts => countComparison!,
        };
      }
      if (!canView) return;
      hasCompared = true;
      if (applied && pending != null) {
        if (pending.kind == StockAuditCommand.counts) _acceptRows(pending.rows);
        if (pending.kind == StockAuditCommand.note) headerNoteDraft = null;
        if (pending.kind == StockAuditCommand.cancel) {
          for (final itemId in _drafts.keys) {
            _epochs[itemId] = epoch(itemId) + 1;
          }
          _drafts.clear();
          headerNoteDraft = null;
        }
        pendingCommand = null;
        needsReview = false;
        failure = null;
        events.resolve(key);
        _publish(value, posted: pending.kind == StockAuditCommand.confirm);
        notice = 'Đã đối chiếu và xác nhận kết quả trên máy chủ.';
      } else {
        needsReview = true;
        notice = pending == null
            ? 'Đã tải dữ liệu mới. Hãy đối chiếu bản nhập trước khi tiếp tục.'
            : 'Chưa xác nhận yêu cầu đã được áp dụng. Bản nhập và yêu cầu ban đầu được giữ để đối chiếu.';
      }
      await loadItems();
    } finally {
      if (current) {
        verifying = false;
        changed();
      }
    }
  }

  Future<bool?> _comparePendingRows(StockAuditPendingCommand pending) async {
    final remaining = {...pending.rows};
    var matches = true;
    for (var page = 0; ; page++) {
      final result = await auditRead(
        'audit-compare-page',
        () => getItems(id, StockAuditItemQuery(page: page, size: 100)),
      );
      if (!canView || result is Error) {
        if (result case Error(failure: final error)) itemFailure = error;
        hasCompared = false;
        return null;
      }
      final data = (result as Success).value;
      for (final StockAuditItem row in data.content) {
        final expected = remaining[row.id];
        if (expected == null) continue;
        if (row.countedQuantity != expected.quantity ||
            expected.noteChanged &&
                (row.note ?? '').trim() != expected.note.trim()) {
          matches = false;
        }
        remaining.remove(row.id);
      }
      if (remaining.isEmpty) return matches;
      if (page + 1 >= data.totalPages) return false;
    }
  }

  /// Explicit acknowledgement after a fresh read. Uncertain writes remain
  /// frozen; transition replay uses the original expectedVersion, never a new one.
  void acknowledgeReview() {
    if (!canView || busy || !hasCompared || pendingCommand != null) return;
    needsReview = false;
    failure = null;
    events.resolve(key);
    changed();
  }

  Future<Result<StockAuditDetail>> retryPendingTransition() async {
    final pending = pendingCommand;
    if (pending == null ||
        pending.kind == StockAuditCommand.counts ||
        pending.kind == StockAuditCommand.note ||
        busy ||
        !hasCompared) {
      return const Error(InventoryController.denied);
    }
    return _run(pending);
  }

  /// Only after explicit read comparison can the user abandon an unresolved
  /// PATCH and edit again. It does not send or silently retry any old values.
  void acknowledgeUnappliedPatch() {
    if (!canManage ||
        busy ||
        !hasCompared ||
        pendingCommand == null ||
        !{
          StockAuditCommand.counts,
          StockAuditCommand.note,
        }.contains(pendingCommand!.kind)) {
      return;
    }
    pendingCommand = null;
    needsReview = false;
    failure = null;
    events.resolve(key);
    changed();
  }

  Future<Result<StockAuditDetail>> saveDrafts() async {
    if (headerNoteDraft != null) {
      final response = await saveNote(headerNoteDraft);
      if (response is Error<StockAuditDetail>) return response;
    }
    if (hasCountDrafts) return saveCounts();
    return audit == null
        ? const Error(InventoryController.denied)
        : Success(audit!);
  }

  @override
  void dispose() {
    ++_headerGeneration;
    ++_itemsGeneration;
    _debounce?.cancel();
    events.removeListener(_event);
    _drafts.clear();
    super.dispose();
  }
}
