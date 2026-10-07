import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/providers.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/table_entities.dart';
import '../../domain/entities/table_inputs.dart';
import '../../domain/validation/table_validation.dart';
import 'table_dialogs.dart';

class TableSessionForm extends ConsumerStatefulWidget {
  const TableSessionForm({
    super.key,
    this.table,
    this.session,
    this.cancel = false,
  }) : assert(table != null || session != null);
  final RestaurantTable? table;
  final TableSession? session;
  final bool cancel;
  @override
  ConsumerState<TableSessionForm> createState() => _TableSessionFormState();
}

class _TableSessionFormState extends ConsumerState<TableSessionForm> {
  final _form = GlobalKey<FormState>();
  final _guests = TextEditingController(),
      _note = TextEditingController(),
      _reason = TextEditingController();
  RestaurantTable? _table;
  TableSession? _session;
  bool _busy = false;
  Failure? _failure;
  final _errors = <String, String>{};
  String get _tableId => _table?.id ?? _session!.tableId;
  String get _permission => widget.cancel ? 'TABLE_CLOSE' : 'TABLE_OPEN';
  @override
  void initState() {
    super.initState();
    _table = widget.table;
    _session = widget.session;
    _apply();
  }

  void _apply() {
    _guests.text = '${_session?.guestCount ?? 1}';
    _note.text = _session?.note ?? '';
    _reason.clear();
    _failure = null;
    _errors.clear();
  }

  @override
  void dispose() {
    _guests.dispose();
    _note.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final c = ref.read(tableSessionControllerProvider(_tableId));
    final b = _session;
    final Result<TableSession> result;
    if (widget.cancel) {
      result = await c.cancel(b!, _reason.text.trim());
    } else if (b == null) {
      result = await c.open(
        _table!,
        OpenTableSessionInput(
          guestCount: int.parse(_guests.text),
          note: _note.text.trim(),
          expectedVersion: _table!.version,
        ),
      );
    } else {
      final guests = int.parse(_guests.text), note = _note.text.trim();
      result = await c.update(
        b,
        UpdateTableSessionInput(
          guestCount: guests != b.guestCount ? guests : null,
          note: note != (b.note ?? '') ? note : null,
          expectedVersion: b.version,
        ),
      );
    }
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
    if (!await confirmTableDraftReload(context, ref, _permission) || !mounted) {
      return;
    }
    setState(() => _busy = true);
    // Reload by the original session ID, never substitute a newer current session.
    if (_session != null) {
      final result = await ref
          .read(tableSessionControllerProvider(_tableId))
          .getDetail(_session!.id);
      if (!mounted) return;
      setState(() {
        _busy = false;
        switch (result) {
          case Success(value: final v):
            _session = v;
            _apply();
          case Error(failure: final f):
            _failure = f;
        }
      });
    } else {
      final result = await ref
          .read(restaurantTableControllerProvider)
          .getDetail(_table!.id);
      if (!mounted) return;
      setState(() {
        _busy = false;
        switch (result) {
          case Success(value: final v):
            _table = v;
            _apply();
          case Error(failure: final f):
            _failure = f;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(tableSessionControllerProvider(_tableId));
    final allowed = _session != null
        ? _session!.status == TableSessionStatus.open
        : _table!.canOpen;
    return TableFormLayout(
      title: widget.cancel
          ? 'Hủy phiên mở nhầm'
          : _session == null
          ? 'Mở phiên phục vụ'
          : 'Sửa phiên phục vụ',
      busy: _busy,
      onSubmit: !allowed || tableNeedsReload(_failure) ? null : _save,
      submitLabel: widget.cancel ? 'Xác nhận hủy phiên' : 'Lưu',
      children: [
        Text(
          'Bàn ${_table?.code ?? _session!.tableCode}${_session == null ? '' : ' • ${_session!.sessionCode}'}',
        ),
        if (!allowed)
          const Text('Trạng thái hiện tại không cho phép thao tác này.'),
        TableFailurePanel(failure: _failure, onReload: _reload),
        Form(
          key: _form,
          child: Column(
            children: widget.cancel
                ? [
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        'Chỉ hủy phiên đã mở nhầm. Đây không phải thao tác thanh toán hay đóng bàn sau thanh toán.',
                      ),
                    ),
                    TextFormField(
                      controller: _reason,
                      maxLines: 3,
                      decoration: tableField(
                        'Lý do hủy',
                        error: _errors['reason'],
                      ),
                      validator: (v) =>
                          TableValidation.text(v, 1000, required: true),
                      onChanged: (_) =>
                          setState(() => _errors.remove('reason')),
                    ),
                  ]
                : [
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _guests,
                      keyboardType: TextInputType.number,
                      decoration: tableField(
                        'Số khách',
                        helper: 'Có thể lớn hơn sức chứa của bàn.',
                        error: _errors['guestCount'],
                      ),
                      validator: (v) => TableValidation.number(
                        int.tryParse(v ?? ''),
                        min: 1,
                        max: 32767,
                      ),
                      onChanged: (_) =>
                          setState(() => _errors.remove('guestCount')),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _note,
                      maxLines: 3,
                      decoration: tableField('Ghi chú', error: _errors['note']),
                      validator: (v) => TableValidation.text(v, 2000),
                      onChanged: (_) => setState(() => _errors.remove('note')),
                    ),
                  ],
          ),
        ),
      ],
    );
  }
}
