import 'package:flutter/material.dart';

import '../../../../core/ui/widgets/responsive_dialog.dart';
import '../../../../core/ui/widgets/responsive_columns.dart';

import '../../domain/entities/staff_member.dart';
import '../../domain/entities/staff_role.dart';

class EditStaffDialog extends StatefulWidget {
  const EditStaffDialog({
    super.key,
    required this.staff,
    required this.roles,
    required this.onSubmit,
    this.fieldErrors,
  });

  final StaffMember staff;
  final List<StaffRole> roles;
  final Map<String, String> Function()? fieldErrors;
  final Future<String?> Function({
    required String staffId,
    String? name,
    String? email,
    String? phone,
    String? roleCode,
  })
  onSubmit;

  @override
  State<EditStaffDialog> createState() => _EditStaffDialogState();
}

class _EditStaffDialogState extends State<EditStaffDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;

  late String _selectedRoleCode;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.staff.name);
    _emailController = TextEditingController(text: widget.staff.email);
    _phoneController = TextEditingController(text: widget.staff.phone ?? '');
    _selectedRoleCode = widget.staff.role.code;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final newName = _nameController.text.trim();
    final newEmail = _emailController.text.trim();
    final newPhone = _phoneController.text.trim();
    final newRoleCode = _selectedRoleCode;

    if (newName == widget.staff.name &&
        newEmail == widget.staff.email &&
        newPhone == (widget.staff.phone ?? '') &&
        newRoleCode == widget.staff.role.code) {
      setState(() {
        _isSubmitting = false;
        _errorMessage = 'Chưa có thay đổi để lưu.';
      });
      return;
    }
    final error = await widget.onSubmit(
      staffId: widget.staff.id,
      name: newName != widget.staff.name ? newName : null,
      email: newEmail != widget.staff.email ? newEmail : null,
      phone: newPhone != (widget.staff.phone ?? '') ? newPhone : null,
      roleCode: newRoleCode != widget.staff.role.code ? newRoleCode : null,
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

    return ResponsiveDialog(
      child: Form(
        key: _formKey,
        onChanged: () {
          if (_errorMessage != null) setState(() => _errorMessage = null);
        },
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.edit_outlined,
                      color: theme.colorScheme.secondary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Cập nhật nhân viên',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    tooltip: 'Đóng',
                  ),
                ],
              ),
              const SizedBox(height: 20),

              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: theme.colorScheme.error),
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

              ResponsiveColumns(
                children: [
                  // Name field
                  TextFormField(
                    controller: _nameController,
                    maxLength: 150,
                    forceErrorText: _errorMessage == null
                        ? null
                        : widget.fieldErrors?.call()['name'],
                    decoration: const InputDecoration(
                      labelText: 'Họ và tên *',
                      prefixIcon: Icon(Icons.person_outline),
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Họ và tên không được để trống';
                      }
                      return null;
                    },
                  ),

                  // Email field
                  TextFormField(
                    controller: _emailController,
                    forceErrorText: _errorMessage == null
                        ? null
                        : widget.fieldErrors?.call()['email'],
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email *',
                      prefixIcon: Icon(Icons.email_outlined),
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Email không được để trống';
                      }
                      if (v.trim().length > 254 ||
                          !RegExp(
                            r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                          ).hasMatch(v.trim())) {
                        return 'Email không hợp lệ';
                      }
                      return null;
                    },
                  ),

                  // Phone field
                  TextFormField(
                    controller: _phoneController,
                    maxLength: 30,
                    forceErrorText: _errorMessage == null
                        ? null
                        : widget.fieldErrors?.call()['phone'],
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Số điện thoại',
                      hintText: 'Xóa để bỏ số điện thoại',
                      prefixIcon: Icon(Icons.phone_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),

                  // Role selector
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    forceErrorText: _errorMessage == null
                        ? null
                        : widget.fieldErrors?.call()['roleCode'],
                    value: widget.roles.any((r) => r.code == _selectedRoleCode)
                        ? _selectedRoleCode
                        : null,
                    decoration: const InputDecoration(
                      labelText: 'Vai trò (Role) *',
                      prefixIcon: Icon(Icons.badge_outlined),
                      border: OutlineInputBorder(),
                    ),
                    items: widget.roles.map((role) {
                      return DropdownMenuItem<String>(
                        value: role.code,
                        child: Text('${role.name} (${role.code})'),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _selectedRoleCode = val);
                      }
                    },
                    validator: (v) =>
                        v == null ? 'Vui lòng chọn vai trò' : null,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_selectedRoleCode != widget.staff.role.code)
                const Text(
                  'Đổi vai trò sẽ xóa toàn bộ permission overrides cũ.',
                ),
              const Text(
                'Đổi email hoặc vai trò sẽ thu hồi các refresh token của nhân viên.',
              ),
              const SizedBox(height: 24),

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
                        : const Text('Lưu thay đổi'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
