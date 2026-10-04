import 'package:flutter/material.dart';

import '../../../../core/ui/widgets/responsive_dialog.dart';
import '../../../../core/ui/widgets/responsive_columns.dart';

import '../../domain/entities/staff_role.dart';

class CreateStaffDialog extends StatefulWidget {
  const CreateStaffDialog({
    super.key,
    required this.roles,
    required this.onSubmit,
    this.fieldErrors,
  });

  final List<StaffRole> roles;
  final Map<String, String> Function()? fieldErrors;
  final Future<String?> Function({
    required String name,
    required String email,
    String? phone,
    required String roleCode,
    required String initialPassword,
  })
  onSubmit;

  @override
  State<CreateStaffDialog> createState() => _CreateStaffDialogState();
}

class _CreateStaffDialogState extends State<CreateStaffDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();

  String? _selectedRoleCode;
  bool _obscurePassword = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    if (widget.roles.isNotEmpty) {
      _selectedRoleCode = widget.roles.first.code;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.clear();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedRoleCode == null) {
      setState(() => _errorMessage = 'Vui lòng chọn vai trò');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final error = await widget.onSubmit(
      name: _nameController.text.trim(),
      email: _emailController.text.trim(),
      phone: _phoneController.text.trim().isEmpty
          ? null
          : _phoneController.text.trim(),
      roleCode: _selectedRoleCode!,
      initialPassword: _passwordController.text,
    );

    if (mounted) {
      if (error != null) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = error;
        });
      } else {
        _passwordController.clear();
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
              // Title
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.person_add_outlined,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Thêm nhân viên mới',
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
                      hintText: 'Nhập tên nhân viên',
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
                      hintText: 'example@domain.com',
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
                      hintText: '0900000000 (Tùy chọn)',
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
                    value: _selectedRoleCode,
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
                      setState(() => _selectedRoleCode = val);
                    },
                    validator: (v) =>
                        v == null ? 'Vui lòng chọn vai trò' : null,
                  ),

                  // Initial Password field
                  TextFormField(
                    controller: _passwordController,
                    forceErrorText: _errorMessage == null
                        ? null
                        : widget.fieldErrors?.call()['initialPassword'],
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'Mật khẩu khởi tạo *',
                      hintText: 'Nhập mật khẩu (8-100 ký tự)',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        onPressed: () {
                          setState(() => _obscurePassword = !_obscurePassword);
                        },
                      ),
                      border: const OutlineInputBorder(),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) {
                        return 'Mật khẩu không được để trống';
                      }
                      if (v.length < 8 || v.length > 100) {
                        return 'Mật khẩu phải từ 8 đến 100 ký tự';
                      }
                      return null;
                    },
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Action buttons
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
                        : const Text('Tạo nhân viên'),
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
