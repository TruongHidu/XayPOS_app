import 'package:flutter/material.dart';
import '../../domain/validation/menu_validation.dart';
import 'menu_dialogs.dart';

/// Edits an explicit price intent; displaying a numeric zero never confirms it.
class ReferenceCostField extends StatelessWidget {
  const ReferenceCostField({
    super.key,
    required this.controller,
    required this.fieldKey,
    required this.configured,
    required this.edited,
    required this.creating,
    required this.onChanged,
    required this.onClear,
    required this.onConfirmZero,
    required this.canConfirmZero,
    this.configurationChange,
    this.errorText,
    this.baseUnit = '',
    this.manualBackup = false,
  });
  final TextEditingController controller;
  final String fieldKey, baseUnit;
  final bool configured, edited, creating, canConfirmZero, manualBackup;
  final bool? configurationChange;
  final String? errorText;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear, onConfirmZero;

  @override
  Widget build(BuildContext context) {
    final state = configurationChange == false
        ? 'Sẽ xóa cấu hình khi lưu.'
        : configurationChange == true
        ? 'Sẽ xác nhận giá 0 khi lưu.'
        : edited && controller.text.trim().isNotEmpty
        ? 'Giá nhập sẽ được xác nhận khi lưu.'
        : configured
        ? 'Đã cấu hình giá vốn'
        : 'Chưa cấu hình giá vốn';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          key: ValueKey(fieldKey),
          controller: controller,
          forceErrorText: errorText,
          decoration: menuField(
            manualBackup
                ? 'Giá vốn tham chiếu thủ công / dự phòng'
                : 'Giá vốn tham chiếu / đơn vị',
            helper:
                '${baseUnit.isEmpty ? 'Giá cho 1 đơn vị cơ sở.' : 'Giá cho 1 $baseUnit.'} Có thể bỏ trống khi tạo; nhập rõ 0 để xác nhận giá 0.',
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: onChanged,
          validator: (value) =>
              MenuValidation.optionalPrice(value) ??
              (!creating &&
                      edited &&
                      (value ?? '').trim().isEmpty &&
                      configurationChange != false
                  ? 'Nhập giá hoặc chọn “Xóa cấu hình giá vốn”.'
                  : null),
        ),
        const SizedBox(height: 6),
        Text(state),
        if (manualBackup)
          const Text(
            'Giá thủ công này được lưu riêng với giá vốn ước tính từ công thức.',
          ),
        if (!creating)
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (canConfirmZero)
                TextButton.icon(
                  key: ValueKey('$fieldKey-confirm-zero'),
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: onConfirmZero,
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Xác nhận giá 0'),
                ),
              TextButton.icon(
                key: ValueKey('$fieldKey-clear'),
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: onClear,
                icon: const Icon(Icons.clear),
                label: const Text('Xóa cấu hình giá vốn'),
              ),
            ],
          ),
      ],
    );
  }
}

Future<bool> confirmReferenceCostClear(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa cấu hình giá vốn?'),
        content: const Text(
          'Khi lưu, giá vốn tham chiếu sẽ về 0 và được đánh dấu chưa cấu hình. Công thức và lịch sử đơn vẫn được giữ.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Giữ giá vốn'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Xóa cấu hình'),
          ),
        ],
      ),
    ) ??
    false;
