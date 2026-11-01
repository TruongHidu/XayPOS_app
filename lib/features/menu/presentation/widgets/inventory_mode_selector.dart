import 'package:flutter/material.dart';
import '../../../../core/auth/access_policy.dart';
import '../../../../core/auth/app_session.dart';
import '../../../../core/values/inventory_mode.dart';

/// Drafts the final mode; the form sends it in the same request as other edits.
class InventoryModeSelector extends StatelessWidget {
  const InventoryModeSelector({
    super.key,
    required this.session,
    required this.value,
    required this.baseline,
    required this.creating,
    required this.onChanged,
    this.errorText,
  });
  final AppSession? session;
  final InventoryMode value;
  final InventoryMode baseline;
  final bool creating;
  final ValueChanged<InventoryMode> onChanged;
  final String? errorText;

  bool _allowed(InventoryMode mode) => AccessPolicy.canSetInventoryMode(
    session,
    creating: creating,
    from: baseline,
    to: mode,
  );

  String get _noneHint => baseline == InventoryMode.recipe
      ? 'Tắt sử dụng vẫn giữ công thức và các phiên bản đã lưu.'
      : baseline == InventoryMode.direct
      ? 'Chỉ đổi được khi món hết tồn, không còn giữ chỗ hoặc phiếu kho nháp.'
      : 'Bán bình thường, không giữ hoặc trừ kho.';

  String get _directHint {
    if (!_allowed(InventoryMode.direct)) {
      return 'Cần tính năng quản lý kho để bật.';
    }
    return baseline == InventoryMode.recipe
        ? 'Công thức được giữ lại nhưng không áp dụng. Nhập tồn qua phiếu nhập kho.'
        : 'Nhập tồn qua phiếu nhập kho; gửi món sẽ giữ rồi trừ tồn của chính món. Khả năng bán không tự đổi theo tồn.';
  }

  String get _recipeHint {
    if (creating) {
      return _allowed(InventoryMode.recipe)
          ? 'Lưu món xong sẽ chuyển sang chọn nguyên liệu cho công thức.'
          : 'Cần quyền tạo công thức và tính năng quản lý công thức.';
    }
    if (!_allowed(InventoryMode.recipe)) {
      return 'Cần tính năng quản lý công thức để bật sử dụng.';
    }
    return baseline == InventoryMode.direct
        ? 'Cần công thức hiện hành hợp lệ. Món phải hết tồn, không còn giữ chỗ hoặc phiếu kho nháp.'
        : 'Sẽ dùng công thức cho các lần gửi món tiếp theo.';
  }

  Widget _option(InventoryMode mode, String title, String hint) =>
      RadioListTile<InventoryMode>(
        key: ValueKey('menu-item-inventory-${mode.code}'),
        contentPadding: EdgeInsets.zero,
        title: Text(title),
        subtitle: Text(hint),
        value: mode,
        groupValue: value,
        onChanged: _allowed(mode)
            ? (selected) {
                if (selected != null) onChanged(selected);
              }
            : null,
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Theo dõi tồn kho', style: theme.textTheme.titleSmall),
        _option(InventoryMode.none, 'Không theo dõi', _noneHint),
        _option(InventoryMode.direct, 'Trừ tồn trực tiếp', _directHint),
        _option(InventoryMode.recipe, 'Sử dụng công thức', _recipeHint),
        if (!AccessPolicy.canMenu(
          session,
          creating ? 'MENU_CREATE' : 'MENU_UPDATE',
        ))
          const Text('Cần quyền cập nhật món để thay đổi lựa chọn này.'),
        if (errorText != null)
          Text(errorText!, style: TextStyle(color: theme.colorScheme.error)),
      ],
    );
  }
}
