import '../entities/stock_audit_inputs.dart';

abstract final class StockAuditValidation {
  static Map<String, String> _version(int value) => {
    if (value < 0) 'expectedVersion': 'Phiên bản kiểm kê không hợp lệ.',
  };
  static Map<String, String> create(CreateStockAuditInput input) => {
    if (input.warehouseId.trim().isEmpty) 'warehouseId': 'Chọn kho.',
    if ((input.note?.length ?? 0) > 2000) 'note': 'Ghi chú tối đa 2000 ký tự.',
  };
  static Map<String, String> note(UpdateStockAuditNoteInput input) => {
    ..._version(input.expectedVersion),
    if ((input.note?.length ?? 0) > 2000) 'note': 'Ghi chú tối đa 2000 ký tự.',
  };
  static Map<String, String> transition(StockAuditTransitionInput input) =>
      _version(input.expectedVersion);
  static Map<String, String> cancel(CancelStockAuditInput input) => {
    ..._version(input.expectedVersion),
    if ((input.note?.length ?? 0) > 2000) 'note': 'Ghi chú tối đa 2000 ký tự.',
  };
  static Map<String, String> counts(StockAuditCountsInput input) {
    final errors = <String, String>{..._version(input.expectedVersion)};
    if (input.items.isEmpty || input.items.length > 100) {
      errors['items'] = 'Mỗi lần lưu cần từ 1 đến 100 dòng.';
    }
    final ids = <String>{};
    for (var i = 0; i < input.items.length; i++) {
      final row = input.items[i];
      if (row.auditItemId.trim().isEmpty || !ids.add(row.auditItemId)) {
        errors['items[$i].auditItemId'] =
            'Dòng kiểm kê không hợp lệ hoặc trùng.';
      }
      if ((row.note?.length ?? 0) > 1000) {
        errors['items[$i].note'] = 'Ghi chú dòng tối đa 1000 ký tự.';
      }
    }
    return errors;
  }
}
