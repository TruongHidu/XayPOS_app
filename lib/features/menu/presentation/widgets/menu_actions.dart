import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/menu_group.dart';
import '../../domain/entities/menu_item.dart';
import '../providers/menu_providers.dart';
import 'menu_dialogs.dart';
import 'menu_group_picker.dart';

/// The confirmed entity is the version displayed when this dialog opened.
class MenuConfirmDialog<T> extends ConsumerStatefulWidget {
  const MenuConfirmDialog({
    super.key,
    required this.initial,
    required this.title,
    required this.describe,
    required this.reload,
    required this.submit,
    required this.permission,
    this.label = 'Xác nhận',
  });
  final T initial;
  final String title, permission, label;
  final String Function(T) describe;
  final Future<Result<T>> Function() reload;
  final Future<Result<Object?>> Function(T) submit;
  @override
  ConsumerState<MenuConfirmDialog<T>> createState() =>
      _MenuConfirmDialogState<T>();
}

class _MenuConfirmDialogState<T> extends ConsumerState<MenuConfirmDialog<T>> {
  late T _baseline = widget.initial;
  bool _busy = false;
  Failure? _failure;
  Future<void> _submit() async {
    if (_busy) return;
    setState(() => _busy = true);
    final result = await widget.submit(_baseline);
    if (!mounted) return;
    switch (result) {
      case Success():
        Navigator.of(context).pop(true);
      case Error(failure: final failure):
        setState(() {
          _busy = false;
          _failure = failure;
        });
    }
  }

  Future<void> _reload() async {
    if (_busy ||
        !await confirmMenuDraftReload(context, ref, widget.permission) ||
        !mounted) {
      return;
    }
    setState(() => _busy = true);
    final result = await widget.reload();
    if (!mounted) return;
    setState(() {
      _busy = false;
      switch (result) {
        case Success(value: final value):
          _baseline = value;
          _failure = null;
        case Error(failure: final failure):
          _failure = failure;
      }
    });
  }

  @override
  Widget build(BuildContext context) => MenuFormLayout(
    title: widget.title,
    busy: _busy,
    submitLabel: widget.label,
    onSubmit: menuNeedsReload(_failure) ? null : _submit,
    children: [
      MenuFailurePanel(failure: _failure, onReload: _reload),
      Text(widget.describe(_baseline)),
    ],
  );
}

Future<Result<Object?>> menuDeleteResult(Future<Result<void>> future) async =>
    switch (await future) {
      Success() => const Success(null),
      Error(failure: final failure) => Error(failure),
    };

class MenuMoveDialog extends ConsumerStatefulWidget {
  const MenuMoveDialog({super.key, required this.initial});
  final MenuItem initial;
  @override
  ConsumerState<MenuMoveDialog> createState() => _MenuMoveDialogState();
}

class _MenuMoveDialogState extends ConsumerState<MenuMoveDialog> {
  late MenuItem _baseline = widget.initial;
  late MenuItemGroupSummary? _selected = widget.initial.group;
  bool _busy = false;
  Failure? _failure;
  bool get _needsReload =>
      _failure?.code != 'MENU_GROUP_NOT_FOUND' && menuNeedsReload(_failure);
  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    final result = await ref
        .read(menuItemControllerProvider)
        .setGroup(_baseline, _selected);
    if (!mounted) return;
    switch (result) {
      case Success():
        Navigator.of(context).pop(true);
      case Error(failure: final failure):
        setState(() {
          _busy = false;
          _failure = failure;
        });
    }
  }

  Future<void> _reload() async {
    if (_busy ||
        !await confirmMenuDraftReload(context, ref, 'MENU_UPDATE') ||
        !mounted) {
      return;
    }
    setState(() => _busy = true);
    final result = await ref
        .read(menuItemControllerProvider)
        .detail(_baseline.id);
    if (!mounted) return;
    setState(() {
      _busy = false;
      switch (result) {
        case Success(value: final item):
          _baseline = item;
          _selected = item.group;
          _failure = null;
        case Error(failure: final failure):
          _failure = failure;
      }
    });
  }

  @override
  Widget build(BuildContext context) => MenuFormLayout(
    title: 'Chuyển nhóm món',
    busy: _busy,
    onSubmit: _needsReload || _selected?.id == _baseline.group?.id
        ? null
        : _save,
    children: [
      Text(_baseline.name, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 16),
      MenuFailurePanel(failure: _failure, onReload: _reload),
      MenuGroupPicker(
        value: _selected,
        errorText: _failure?.fieldErrors['groupId'],
        onChanged: (value) => setState(() {
          _selected = value;
          if (!_needsReload) _failure = null;
        }),
      ),
      const SizedBox(height: 12),
      const Text(
        'Chọn nhóm đang hoạt động hoặc “Chưa phân nhóm”. Việc chuyển nhóm có thể thay đổi khả năng bán của món.',
      ),
    ],
  );
}
