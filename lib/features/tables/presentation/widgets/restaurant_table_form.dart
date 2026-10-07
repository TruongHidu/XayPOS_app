import '../../domain/entities/table_query.dart';
import 'table_creation_check.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/providers.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/table_entities.dart';
import '../../domain/entities/table_inputs.dart';
import '../../domain/validation/table_validation.dart';
import 'table_dialogs.dart';
import 'table_area_picker.dart';

class RestaurantTableForm extends ConsumerStatefulWidget {
  const RestaurantTableForm({super.key, this.initial});
  final RestaurantTable? initial;
  @override
  ConsumerState<RestaurantTableForm> createState() =>
      _RestaurantTableFormState();
}

class _RestaurantTableFormState extends ConsumerState<RestaurantTableForm> {
  final _form = GlobalKey<FormState>();
  final _code = TextEditingController(),
      _name = TextEditingController(),
      _capacity = TextEditingController(),
      _order = TextEditingController();
  RestaurantTable? _baseline;
  TableAreaSummary? _area;
  TableStatus _status = TableStatus.available;
  bool _busy = false;
  Failure? _failure;
  final _errors = <String, String>{};
  @override
  void initState() {
    super.initState();
    _apply(widget.initial);
  }

  void _apply(RestaurantTable? b) {
    _baseline = b;
    _code.text = b?.code ?? '';
    _name.text = b?.name ?? '';
    _capacity.text = '${b?.capacity ?? 4}';
    _order.text = '${b?.displayOrder ?? 0}';
    _area = b?.area;
    _status = b?.status ?? TableStatus.available;
    _failure = null;
    _errors.clear();
  }

  @override
  void dispose() {
    for (final c in [_code, _name, _capacity, _order]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final c = ref.read(restaurantTableControllerProvider), b = _baseline;
    final code = _code.text.trim().toUpperCase(),
        name = _name.text.trim(),
        capacity = int.parse(_capacity.text),
        order = int.parse(_order.text);
    final result = b == null
        ? await c.create(
            CreateRestaurantTableInput(
              code: code,
              name: name,
              capacity: capacity,
              displayOrder: order,
              areaId: _area?.id,
              status: _status,
            ),
          )
        : await c.update(
            b,
            UpdateRestaurantTableInput(
              code: code != b.code ? code : null,
              name: name != b.name ? name : null,
              capacity: capacity != b.capacity ? capacity : null,
              displayOrder: order != b.displayOrder ? order : null,
              expectedVersion: b.version,
            ),
          );
    if (!mounted) return;
    switch (result) {
      case Success():
        Navigator.pop(context, true);
      case Error(failure: final f):
        setState(() {
          _busy = false;
          _failure = f;
          _errors.addAll(f.fieldErrors);
        });
    }
  }

  Future<void> _reload() async {
    if (_baseline == null) {
      final controller = ref.read(restaurantTableControllerProvider);
      final verified = await showTableDialog<bool>(
        context,
        ref,
        permission: 'TABLE_CREATE',
        child: TableCreationCheck<RestaurantTable>(
          fetch: (page) => controller.verifyCreation(
            TableQuery(q: _code.text.trim(), page: page),
          ),
          label: (v) => '${v.code} - ${v.name}',
        ),
      );
      if (mounted && verified == true) setState(() => _failure = null);
      return;
    }
    if (_baseline == null ||
        !await confirmTableDraftReload(context, ref, 'TABLE_UPDATE') ||
        !mounted) {
      return;
    }
    setState(() => _busy = true);
    final result = await ref
        .read(restaurantTableControllerProvider)
        .getDetail(_baseline!.id);
    if (!mounted) return;
    setState(() {
      _busy = false;
      switch (result) {
        case Success(value: final b):
          _apply(b);
        case Error(failure: final f):
          _failure = f;
      }
    });
  }

  @override
  Widget build(BuildContext context) => TableFormLayout(
    title: _baseline == null ? 'Thêm bàn' : 'Sửa thông tin bàn',
    busy: _busy,
    onSubmit: tableNeedsReload(_failure) ? null : _save,
    children: [
      TableFailurePanel(failure: _failure, onReload: _reload),
      if (_baseline?.occupied == true)
        const Padding(
          padding: EdgeInsets.only(bottom: 16),
          child: Text('Bàn đang có khách: chỉ sửa tên và thứ tự hiển thị.'),
        ),
      Form(
        key: _form,
        child: Column(
          children: [
            _field(
              _code,
              'code',
              'Mã bàn',
              (v) => TableValidation.text(v, 50, required: true),
              enabled: _baseline?.occupied != true,
            ),
            _field(
              _name,
              'name',
              'Tên bàn',
              (v) => TableValidation.text(v, 100, required: true),
            ),
            _field(
              _capacity,
              'capacity',
              'Sức chứa',
              (v) => TableValidation.number(
                int.tryParse(v ?? ''),
                min: 1,
                max: 32767,
              ),
              number: true,
              enabled: _baseline?.occupied != true,
            ),
            _field(
              _order,
              'displayOrder',
              'Thứ tự hiển thị',
              (v) => TableValidation.number(int.tryParse(v ?? '')),
              number: true,
            ),
            Text(
              'Khu vực: ${_area?.name ?? 'Chưa gán khu vực'}${_area?.active == false ? ' (ngừng hoạt động)' : ''}',
            ),
            if (_errors['areaId'] != null)
              Text(
                _errors['areaId']!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (_baseline == null) ...[
              TextButton(
                onPressed: () async {
                  final result = await pickTableArea(
                    context,
                    ref,
                    activeOnly: true,
                  );
                  if (mounted && result != null) {
                    setState(() {
                      _area = result.area;
                      _errors.remove('areaId');
                    });
                  }
                },
                child: const Text('Chọn khu vực'),
              ),
              DropdownButtonFormField<TableStatus>(
                isExpanded: true,
                value: _status,
                decoration: tableField('Trạng thái cấu hình'),
                items: const [
                  DropdownMenuItem(
                    value: TableStatus.available,
                    child: Text('Hoạt động'),
                  ),
                  DropdownMenuItem(
                    value: TableStatus.inactive,
                    child: Text('Ngừng hoạt động'),
                  ),
                ],
                onChanged: (v) => setState(() => _status = v!),
              ),
            ] else
              const Text(
                'Gán khu vực và đổi trạng thái là các thao tác riêng.',
              ),
          ],
        ),
      ),
    ],
  );
  Widget _field(
    TextEditingController c,
    String key,
    String label,
    String? Function(String?) validator, {
    bool enabled = true,
    bool number = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      controller: c,
      enabled: enabled,
      keyboardType: number ? TextInputType.number : null,
      decoration: tableField(label, error: _errors[key]),
      validator: validator,
      onChanged: (_) => setState(() => _errors.remove(key)),
    ),
  );
}
