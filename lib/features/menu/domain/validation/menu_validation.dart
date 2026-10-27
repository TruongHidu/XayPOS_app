import '../entities/menu_inputs.dart';
import '../entities/menu_price.dart';

abstract final class MenuValidation {
  static String? text(String value, {required int max, bool required = false}) {
    if (required && value.trim().isEmpty) return 'Vui lòng nhập thông tin này.';
    if (value.trim().length > max) return 'Tối đa $max ký tự.';
    return null;
  }

  static String? price(String value) {
    try {
      MenuPrice.parse(value);
      return null;
    } on FormatException catch (e) {
      return e.message;
    }
  }

  static String? optionalPrice(String? value) =>
      value == null || value.trim().isEmpty ? null : price(value);

  static String? referenceCost(
    MenuPrice? price,
    bool? configured, {
    required bool creating,
  }) {
    if (configured == false && price != null && price.minorUnits > 0) {
      return 'Không thể vừa xóa cấu hình vừa đặt giá vốn lớn hơn 0.';
    }
    if (creating && configured == true && price == null) {
      return 'Nhập giá vốn để xác nhận cấu hình.';
    }
    return null;
  }

  static String? displayOrder(String value) {
    if (!RegExp(r'^\d+$').hasMatch(value.trim()) ||
        int.tryParse(value.trim()) == null) {
      return 'Thứ tự phải là số nguyên không âm.';
    }
    return null;
  }

  static String? imageUrl(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final text = value.trim();
    final uri = Uri.tryParse(text);
    if (text.length > 500 ||
        RegExp(r'\s').hasMatch(text) ||
        uri == null ||
        !const {'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
        uri.host.isEmpty ||
        uri.authority.contains('@')) {
      return 'Nhập URL HTTP(S) hợp lệ, không chứa tài khoản, tối đa 500 ký tự.';
    }
    return null;
  }

  static Map<String, String> group(CreateMenuGroupInput input) => _errors({
    'name': text(input.name, max: 100, required: true),
    'displayOrder': input.displayOrder < 0 ? 'Thứ tự phải không âm.' : null,
  });
  static Map<String, String> groupPatch(UpdateMenuGroupInput input) => _errors({
    'name': input.name == null
        ? null
        : text(input.name!, max: 100, required: true),
    'displayOrder': input.displayOrder != null && input.displayOrder! < 0
        ? 'Thứ tự phải không âm.'
        : null,
    'expectedVersion': input.expectedVersion < 0
        ? 'Version không hợp lệ.'
        : null,
  });
  static Map<String, String> item(CreateMenuItemInput input) => _errors({
    'name': text(input.name, max: 150, required: true),
    'baseUnit': text(input.baseUnit, max: 30, required: true),
    'sku': text(input.sku ?? '', max: 80),
    'description': text(input.description ?? '', max: 10000),
    'imageUrl': imageUrl(input.imageUrl),
    'costPrice': referenceCost(
      input.costPrice,
      input.costConfigured,
      creating: true,
    ),
    'recipeEnabled': input.recipeEnabled
        ? 'Tạo món và công thức trước khi bật sử dụng công thức.'
        : null,
    'groupId': input.groupId != null && input.groupId!.trim().isEmpty
        ? 'Nhóm không hợp lệ.'
        : null,
  });
  static Map<String, String> itemPatch(UpdateMenuItemInput input) => _errors({
    'name': input.name == null
        ? null
        : text(input.name!, max: 150, required: true),
    'baseUnit': input.baseUnit == null
        ? null
        : text(input.baseUnit!, max: 30, required: true),
    'sku': text(input.sku ?? '', max: 80),
    'description': text(input.description ?? '', max: 10000),
    'imageUrl': imageUrl(input.imageUrl),
    'costPrice': referenceCost(
      input.costPrice,
      input.costConfigured,
      creating: false,
    ),
    'expectedVersion': input.expectedVersion < 0
        ? 'Version không hợp lệ.'
        : null,
  });
  static Map<String, String> _errors(Map<String, String?> fields) => {
    for (final entry in fields.entries)
      if (entry.value != null) entry.key: entry.value!,
  };
}
