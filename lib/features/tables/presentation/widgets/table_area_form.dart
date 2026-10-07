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

class TableAreaForm extends ConsumerStatefulWidget {
  const TableAreaForm({super.key, this.initial});
  final TableArea? initial;
  @override
  ConsumerState<TableAreaForm> createState() => _TableAreaFormState();
}

class _TableAreaFormState extends ConsumerState<TableAreaForm> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(),
      _description = TextEditingController(),
      _order = TextEditingController();
  TableArea? _baseline;
  bool _busy = false, _active = true;
  Failure? _failure;
  final _errors = <String, String>{};
  @override
  void initState() {
    super.initState();
    _apply(widget.initial);
  }

  void _apply(TableArea? b) {
    _baseline = b;
    _name.text = b?.name ?? '';
    _description.text = b?.description ?? '';
    _order.text = '${b?.displayOrder ?? 0}';
    _active = b?.active ?? true;
    _failure = null;
    _errors.clear();
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _order.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final c = ref.read(tableAreaControllerProvider), b = _baseline;
    final name = _name.text.trim(),
        description = _description.text.trim(),
        order = int.parse(_order.text);
    final result = b == null
        ? await c.create(
            CreateTableAreaInput(
              name: name,
              description: description,
              displayOrder: order,
              active: _active,
            ),
          )
        : await c.update(
            b,
            UpdateTableAreaInput(
              name: name != b.name ? name : null,
              description: description != (b.description ?? '')
                  ? description
                  : null,
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
      final controller = ref.read(tableAreaControllerProvider);
      final verified = await showTableDialog<bool>(
        context,
        ref,
        permission: 'TABLE_CREATE',
        child: TableCreationCheck<TableArea>(
          fetch: (page) => controller.verifyCreation(
            TableQuery(q: _name.text.trim(), page: page),
          ),
          label: (v) => v.name,
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
        .read(tableAreaControllerProvider)
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
    title: _baseline == null ? 'Thêm khu vực' : 'Sửa khu vực',
    busy: _busy,
    onSubmit: tableNeedsReload(_failure) ? null : _save,
    children: [
      TableFailurePanel(failure: _failure, onReload: _reload),
      Form(
        key: _form,
        child: Column(
          children: [
            _field(
              _name,
              'name',
              'Tên khu vực',
              (v) => TableValidation.text(v, 100, required: true),
            ),
            _field(
              _description,
              'description',
              'Mô tả',
              (v) => TableValidation.text(v, 2000),
              lines: 3,
            ),
            _field(
              _order,
              'displayOrder',
              'Thứ tự hiển thị',
              (v) => TableValidation.number(int.tryParse(v ?? '')),
              number: true,
            ),
            if (_baseline == null)
              SwitchListTile(
                title: const Text('Đang hoạt động'),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
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
    int lines = 1,
    bool number = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      controller: c,
      maxLines: lines,
      keyboardType: number ? TextInputType.number : null,
      decoration: tableField(label, error: _errors[key]),
      validator: validator,
      onChanged: (_) => setState(() => _errors.remove(key)),
    ),
  );
}
