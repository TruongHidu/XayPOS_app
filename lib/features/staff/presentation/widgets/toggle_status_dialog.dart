import 'package:flutter/material.dart';

import '../../domain/entities/staff_member.dart';

class ToggleStatusDialog extends StatefulWidget {
  const ToggleStatusDialog({
    super.key,
    required this.staff,
    required this.onSubmit,
    this.fieldErrors,
  });

  final StaffMember staff;
  final Map<String, String> Function()? fieldErrors;
  final Future<String?> Function({
    required String staffId,
    required bool active,
    String? reason,
  })
  onSubmit;

  @override
  State<ToggleStatusDialog> createState() => _ToggleStatusDialogState();
}

class _ToggleStatusDialogState extends State<ToggleStatusDialog> {
  final _formKey = GlobalKey<FormState>();
  final _reasonController = TextEditingController();

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final willDisable = widget.staff.active;
    if (willDisable && !_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final error = await widget.onSubmit(
      staffId: widget.staff.id,
      active: !widget.staff.active,
      reason: willDisable ? _reasonController.text.trim() : null,
    );

    if (mounted) {
      if (error != null) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = error;
        });
      } else {
        Navigator.of(context).pop(true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDisabling = widget.staff.active;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 450),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              onChanged: () {
                if (_errorMessage != null) setState(() => _errorMessage = null);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isDisabling
                              ? theme.colorScheme.errorContainer
                              : theme.colorScheme.primaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isDisabling
                              ? Icons.block_outlined
                              : Icons.check_circle_outline,
                          color: isDisabling
                              ? theme.colorScheme.error
                              : theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          isDisabling
                              ? 'Vô hiệu hóa nhân viên'
                              : 'Kích hoạt lại nhân viên',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  Text(
                    isDisabling
                        ? 'Bạn có chắc chắn muốn vô hiệu hóa tài khoản của "${widget.staff.name}"?'
                        : 'Kích hoạt lại tài khoản cho "${widget.staff.name}" để cho phép truy cập lại hệ thống.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),

                  if (_errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.error_outline,
                            color: theme.colorScheme.error,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: TextStyle(color: theme.colorScheme.error),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  if (isDisabling) ...[
                    TextFormField(
                      controller: _reasonController,
                      forceErrorText: _errorMessage == null
                          ? null
                          : widget.fieldErrors?.call()['reason'],
                      maxLines: 3,
                      maxLength: 500,
                      decoration: const InputDecoration(
                        labelText: 'Lý do vô hiệu hóa *',
                        hintText: 'Nhập lý do (ví dụ: Nhân viên đã nghỉ việc)',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Vui lòng nhập lý do vô hiệu hóa';
                        }
                        if (v.trim().length > 500) {
                          return 'Lý do không quá 500 ký tự';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                  ],

                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: _isSubmitting
                            ? null
                            : () => Navigator.of(context).pop(),
                        child: const Text('Hủy'),
                      ),
                      const SizedBox(width: 12),
                      FilledButton(
                        style: isDisabling
                            ? FilledButton.styleFrom(
                                backgroundColor: theme.colorScheme.error,
                              )
                            : null,
                        onPressed: _isSubmitting ? null : _submit,
                        child: _isSubmitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                isDisabling ? 'Vô hiệu hóa' : 'Kích hoạt lại',
                              ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
