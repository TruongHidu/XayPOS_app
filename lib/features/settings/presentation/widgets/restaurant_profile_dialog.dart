import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../../../core/ui/widgets/responsive_dialog.dart';
import '../../domain/entities/restaurant_profile.dart';
import '../providers/settings_providers.dart';

/// Edits the restaurant's name and contact details; returns the saved profile.
class RestaurantProfileDialog extends ConsumerStatefulWidget {
  const RestaurantProfileDialog({super.key, required this.profile});

  final RestaurantProfile profile;

  @override
  ConsumerState<RestaurantProfileDialog> createState() =>
      _RestaurantProfileDialogState();
}

class _RestaurantProfileDialogState
    extends ConsumerState<RestaurantProfileDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.profile.name);
  late final _legalName = TextEditingController(
    text: widget.profile.legalName ?? '',
  );
  late final _phone = TextEditingController(text: widget.profile.phone ?? '');
  late final _address = TextEditingController(
    text: widget.profile.address ?? '',
  );
  bool _saving = false;
  Failure? _failure;

  @override
  void dispose() {
    _name.dispose();
    _legalName.dispose();
    _phone.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _failure = null;
    });
    final result = await ref
        .read(settingsRepositoryProvider)
        .updateRestaurant(
          RestaurantProfileUpdate(
            name: _name.text,
            legalName: _legalName.text,
            phone: _phone.text,
            address: _address.text,
          ),
        );
    if (!mounted) return;
    switch (result) {
      case Success(:final value):
        Navigator.of(context).pop(value);
      case Error(:final failure):
        setState(() {
          _saving = false;
          _failure = failure;
        });
    }
  }

  String? _fieldError(String field) => _failure?.fieldErrors[field];

  @override
  Widget build(BuildContext context) {
    return ResponsiveDialog(
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Sửa thông tin nhà hàng',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                enabled: !_saving,
                maxLength: 150,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Tên nhà hàng',
                  errorText: _fieldError('name'),
                ),
                validator: (value) => (value ?? '').trim().length < 2
                    ? 'Tên cần ít nhất 2 ký tự.'
                    : null,
              ),
              TextFormField(
                controller: _legalName,
                enabled: !_saving,
                maxLength: 200,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Tên pháp lý (không bắt buộc)',
                  errorText: _fieldError('legalName'),
                ),
              ),
              TextFormField(
                controller: _phone,
                enabled: !_saving,
                maxLength: 30,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Số điện thoại',
                  errorText: _fieldError('phone'),
                ),
              ),
              TextFormField(
                controller: _address,
                enabled: !_saving,
                maxLength: 500,
                minLines: 1,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Địa chỉ',
                  errorText: _fieldError('address'),
                ),
              ),
              if (_failure != null && _failure!.fieldErrors.isEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  _failure!.message,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('Hủy'),
                  ),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Lưu'),
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
