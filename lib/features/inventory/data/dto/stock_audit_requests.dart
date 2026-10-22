import '../../domain/entities/stock_audit_inputs.dart';
import '../../domain/entities/stock_audit_queries.dart';

abstract final class StockAuditRequests {
  static Map<String, dynamic> audits(StockAuditQuery q) => {
    if (q.q.trim().isNotEmpty) 'q': q.q.trim(),
    if (q.warehouseId != null) 'warehouseId': q.warehouseId,
    if (q.status != null) 'status': q.status!.code,
    if (q.dates?.from != null)
      'createdFrom': q.dates!.from!.toUtc().toIso8601String(),
    if (q.dates?.to != null)
      'createdTo': q.dates!.to!.toUtc().toIso8601String(),
    'page': q.page,
    'size': q.size,
    'sortBy': q.sortBy,
    'direction': q.direction,
  };
  static Map<String, dynamic> items(StockAuditItemQuery q) => {
    if (q.q.trim().isNotEmpty) 'q': q.q.trim(),
    if (q.counted != null) 'counted': q.counted,
    'differenceOnly': q.differenceOnly,
    'page': q.page,
    'size': q.size,
    'sortBy': q.sortBy,
    'direction': q.direction,
  };
  static String? _note(String? value) =>
      value == null || value.trim().isEmpty ? null : value.trim();
  static Map<String, dynamic> create(CreateStockAuditInput input) => {
    'warehouseId': input.warehouseId,
    'note': _note(input.note),
  };
  static Map<String, dynamic> note(UpdateStockAuditNoteInput input) => {
    'expectedVersion': input.expectedVersion,
    'note': _note(input.note),
  };
  static Map<String, dynamic> transition(StockAuditTransitionInput input) => {
    'expectedVersion': input.expectedVersion,
  };
  static Map<String, dynamic> counts(StockAuditCountsInput input) => {
    'expectedVersion': input.expectedVersion,
    'items': input.items
        .map(
          (row) => {
            'auditItemId': row.auditItemId,
            'countedQuantity': row.countedQuantity.toNumber(),
            // Omit/null preserves existing note; explicit blank clears the note.
            if (row.note != null) 'note': row.note!.trim(),
          },
        )
        .toList(),
  };
  static Map<String, dynamic> cancel(CancelStockAuditInput input) => {
    'expectedVersion': input.expectedVersion,
    if (_note(input.note) != null) 'note': _note(input.note),
  };
}
