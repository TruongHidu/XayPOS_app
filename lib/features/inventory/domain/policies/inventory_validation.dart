import '../entities/inventory_inputs.dart';
import '../entities/inventory_entities.dart';

abstract final class InventoryValidation {
  static Map<String, String> warehouse(
    String? code,
    String? name, {
    bool update = false,
    int? version,
  }) {
    final errors = <String, String>{};
    if ((!update || code != null) &&
        (code == null || code.trim().isEmpty || code.trim().length > 50)) {
      errors['code'] = 'Nhập mã kho từ 1 đến 50 ký tự.';
    }
    if ((!update || name != null) &&
        (name == null || name.trim().isEmpty || name.trim().length > 100)) {
      errors['name'] = 'Nhập tên kho từ 1 đến 100 ký tự.';
    }
    if (update && (version == null || version < 0)) {
      errors['expectedVersion'] = 'Cần tải lại dữ liệu kho.';
    }
    if (update && code == null && name == null) {
      errors['form'] = 'Chưa có thay đổi để lưu.';
    }
    return errors;
  }

  static Map<String, String> update(UpdateWarehouseInput input) => warehouse(
    input.code,
    input.name,
    update: true,
    version: input.expectedVersion,
  );
  static bool canDisable(Warehouse warehouse) => !warehouse.isDefault;
  static bool canDelete(Warehouse warehouse) => !warehouse.isDefault;
  static bool canMakeDefault(Warehouse warehouse) =>
      warehouse.active && !warehouse.isDefault;
}
