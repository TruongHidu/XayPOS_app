import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/providers.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/inventory_entities.dart';
import '../../domain/entities/inventory_inputs.dart';
import '../../domain/policies/inventory_validation.dart';
import '../controllers/inventory_controller.dart';
import '../controllers/inventory_events.dart';
import 'inventory_widgets.dart';

class WarehouseForm extends ConsumerStatefulWidget {
  const WarehouseForm({super.key, this.id});
  final String? id;
  @override
  ConsumerState<WarehouseForm> createState() => _WarehouseFormState();
}

class _WarehouseFormState extends ConsumerState<WarehouseForm> {
  final _code = TextEditingController(), _name = TextEditingController();
  Warehouse? _baseline;
  bool _loading = false, _inspected = false, _initialized = false;
  Failure? _failure;
  Map<String, String> _errors = {};
  List<Warehouse> _matches = [];
  bool get _creating => widget.id == null;
  String get _key => _creating
      ? InventoryEvents.createKey
      : InventoryEvents.warehouseKey(widget.id!);
  @override
  void initState() {
    super.initState();
    Future.microtask(_initialize);
  }

  Future<void> _initialize() async {
    if (!mounted) return;
    if (_creating) {
      final pending = ref.read(warehouseListProvider).pendingCreate;
      if (pending != null) {
        _code.text = pending.code;
        _name.text = pending.name;
      }
      setState(() => _initialized = true);
    } else {
      await _load();
    }
  }

  Future<void> _load() async {
    final c = ref.read(warehouseListProvider);
    if (!mounted || !c.current) return;
    setState(() {
      _loading = true;
      _initialized = false;
    });
    final result = await c.detail(widget.id!, verify: true);
    if (!mounted || !c.current) return;
    setState(() {
      _loading = false;
      switch (result) {
        case Success(value: final row):
          _baseline = row;
          _code.text = row.code;
          _name.text = row.name;
          _errors = {};
          _failure = null;
          _initialized = true;
        case Error(failure: final error):
          _failure = error;
          if (error.type == FailureType.notFound) c.events.resolve(_key);
      }
    });
  }

  Future<void> _inspect() async {
    final c = ref.read(warehouseListProvider);
    final code =
        c.pendingCreate?.normalizedCode ?? _code.text.trim().toUpperCase();
    setState(() => _loading = true);
    final result = await c.inspectCreation(code);
    if (!mounted || !c.current) return;
    setState(() {
      _loading = false;
      switch (result) {
        case Success(value: final rows):
          _matches = rows;
          _inspected = true;
          _failure = null;
        case Error(failure: final f):
          _failure = f;
      }
    });
  }

  Future<void> _save() async {
    final c = ref.read(warehouseListProvider);
    final code = _code.text.trim().toUpperCase(), name = _name.text.trim();
    final errors = InventoryValidation.warehouse(code, name);
    if (errors.isNotEmpty) {
      setState(() => _errors = errors);
      return;
    }
    Result<Warehouse> result;
    if (_creating) {
      result = await c.create(CreateWarehouseInput(code: code, name: name));
    } else {
      final baseline = _baseline;
      if (baseline == null) return;
      result = await c.update(
        baseline,
        UpdateWarehouseInput(
          expectedVersion: baseline.version,
          code: code == baseline.code ? null : code,
          name: name == baseline.name ? null : name,
        ),
      );
    }
    if (!mounted || !c.current) return;
    switch (result) {
      case Success(value: final row):
        ref.read(warehouseSelectorProvider).select(row);
        Navigator.of(context).pop(row);
      case Error(failure: final error):
        setState(() {
          _failure = error;
          _errors = error.fieldErrors;
          _inspected = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(warehouseListProvider),
        events = ref.watch(inventoryEventsProvider);
    final pending = events.pending(_key),
        verification = events.verification(_key);
    final unknown = InventoryController.unknown(verification);
    final disabled = pending || _loading || verification != null;
    return InventoryDialogFrame(
      title: _creating ? 'Thêm kho' : 'Sửa kho',
      busy: pending || _loading,
      canClose: !unknown,
      actions: [
        if (!_creating &&
            (_failure != null || verification != null || !_initialized))
          OutlinedButton(
            onPressed: pending || _loading
                ? null
                : () async {
                    if (await confirmInventoryDraftReload(context, ref) &&
                        mounted) {
                      await _load();
                    }
                  },
            child: const Text('Tải lại để đối chiếu'),
          ),
        FilledButton(
          onPressed:
              disabled ||
                  !_initialized ||
                  !c.can(_creating ? 'WAREHOUSE_CREATE' : 'WAREHOUSE_UPDATE')
              ? null
              : _save,
          child: Text(_creating ? 'Tạo kho' : 'Lưu thay đổi'),
        ),
      ],
      children: [
        TextField(
          controller: _code,
          enabled: !disabled,
          maxLength: 50,
          textCapitalization: TextCapitalization.characters,
          decoration: inventoryField(
            'Mã kho',
            hint: 'Ví dụ: KHO-CHINH',
            error: _errors['code'],
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _name,
          enabled: !disabled,
          maxLength: 100,
          decoration: inventoryField(
            'Tên kho',
            hint: 'Ví dụ: Kho chính',
            error: _errors['name'],
          ),
        ),
        if (_creating)
          const Text('Kho đầu tiên sẽ được hệ thống đặt làm kho mặc định.'),
        if (_baseline != null)
          InventoryBadge(
            _baseline!.active ? 'Đang hoạt động' : 'Ngừng hoạt động',
          ),
        InventoryFailurePanel(failure: _failure ?? verification),
        if (unknown)
          const Text(
            'Chưa rõ kho đã được lưu hay chưa. Hãy tải lại danh sách kho trước khi gửi lại.',
          ),
        if (verification != null && _creating) ...[
          OutlinedButton(
            onPressed: _loading || pending ? null : _inspect,
            child: const Text('Kiểm tra kho theo mã'),
          ),
          if (_inspected) ...[
            Text(
              _matches.isEmpty
                  ? 'Chưa tìm thấy kho có đúng mã này. Hãy kiểm tra lại trước khi gửi mới.'
                  : 'Máy chủ đã có kho cùng mã. Hãy đối chiếu, không tạo thêm kho trùng.',
            ),
            for (final row in _matches) Text('${row.code} · ${row.name}'),
            TextButton(
              onPressed: () {
                c.acknowledgeCreation();
                setState(() => _failure = null);
              },
              child: const Text('Đã đối chiếu dữ liệu'),
            ),
          ],
        ],
      ],
    );
  }

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    super.dispose();
  }
}
