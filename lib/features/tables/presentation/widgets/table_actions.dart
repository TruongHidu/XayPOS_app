import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/providers.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/table_entities.dart';
import 'table_dialogs.dart';
import 'table_area_picker.dart';

/// A confirmation holds its own snapshot; background refresh never advances it.
class TableConfirmation<T> extends ConsumerStatefulWidget {
  const TableConfirmation({
    super.key,
    required this.title,
    required this.initial,
    required this.describe,
    required this.reload,
    required this.submit,
    required this.permission,
  });
  final String title, permission;
  final T initial;
  final String Function(T) describe;
  final Future<Result<T>> Function() reload;
  final Future<Result<Object?>> Function(T) submit;
  @override
  ConsumerState<TableConfirmation<T>> createState() =>
      _TableConfirmationState<T>();
}

class _TableConfirmationState<T> extends ConsumerState<TableConfirmation<T>> {
  late T _baseline = widget.initial;
  bool _busy = false;
  Failure? _failure;
  Future<void> _save() async {
    setState(() => _busy = true);
    final result = await widget.submit(_baseline);
    if (!mounted) return;
    switch (result) {
      case Success():
        Navigator.pop(context, true);
      case Error(failure: final f):
        setState(() {
          _busy = false;
          _failure = f;
        });
    }
  }

  Future<void> _reload() async {
    if (!await confirmTableDraftReload(context, ref, widget.permission) ||
        !mounted) {
      return;
    }
    setState(() => _busy = true);
    final result = await widget.reload();
    if (!mounted) return;
    setState(() {
      _busy = false;
      switch (result) {
        case Success(value: final v):
          _baseline = v;
          _failure = null;
        case Error(failure: final f):
          _failure = f;
      }
    });
  }

  @override
  Widget build(BuildContext context) => TableFormLayout(
    title: widget.title,
    busy: _busy,
    onSubmit: tableNeedsReload(_failure) ? null : _save,
    submitLabel: 'Xác nhận',
    children: [
      TableFailurePanel(failure: _failure, onReload: _reload),
      Text(widget.describe(_baseline)),
    ],
  );
}

class TableAreaAssignment extends ConsumerStatefulWidget {
  const TableAreaAssignment({super.key, required this.initial});
  final RestaurantTable initial;
  @override
  ConsumerState<TableAreaAssignment> createState() =>
      _TableAreaAssignmentState();
}

class _TableAreaAssignmentState extends ConsumerState<TableAreaAssignment> {
  late RestaurantTable _baseline = widget.initial;
  late TableAreaSummary? _area = widget.initial.area;
  bool _busy = false;
  Failure? _failure;
  Future<void> _save() async {
    setState(() => _busy = true);
    final result = await ref
        .read(restaurantTableControllerProvider)
        .assignArea(_baseline, _area);
    if (!mounted) return;
    switch (result) {
      case Success():
        Navigator.pop(context, true);
      case Error(failure: final f):
        setState(() {
          _busy = false;
          _failure = f;
        });
    }
  }

  Future<void> _reload() async {
    if (!await confirmTableDraftReload(context, ref, 'TABLE_UPDATE') ||
        !mounted) {
      return;
    }
    setState(() => _busy = true);
    final result = await ref
        .read(restaurantTableControllerProvider)
        .getDetail(_baseline.id);
    if (!mounted) return;
    setState(() {
      _busy = false;
      switch (result) {
        case Success(value: final v):
          _baseline = v;
          _area = v.area;
          _failure = null;
        case Error(failure: final f):
          _failure = f;
      }
    });
  }

  @override
  Widget build(BuildContext context) => TableFormLayout(
    title: 'Gán khu vực • ${_baseline.code}',
    busy: _busy,
    onSubmit:
        tableNeedsReload(_failure) ||
            _baseline.occupied ||
            _area?.id == _baseline.area?.id
        ? null
        : _save,
    children: [
      TableFailurePanel(failure: _failure, onReload: _reload),
      if (_failure?.fieldErrors['areaId'] != null)
        Text(
          _failure!.fieldErrors['areaId']!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),

      Text(
        _area == null
            ? 'Không thuộc khu vực'
            : '${_area!.name}${_area!.active ? '' : ' (ngừng hoạt động)'}',
      ),
      if (_baseline.occupied)
        const Text('Không thể đổi khu vực khi bàn đang có khách.'),
      TextButton(
        onPressed: _baseline.occupied
            ? null
            : () async {
                final selected = await pickTableArea(
                  context,
                  ref,
                  activeOnly: true,
                );
                if (mounted && selected != null) {
                  setState(() {
                    _area = selected.area;
                    if (_failure?.code == 'TABLE_AREA_NOT_FOUND') {
                      _failure = null;
                    }
                  });
                }
              },
        child: const Text('Chọn hoặc bỏ gán khu vực'),
      ),
    ],
  );
}
