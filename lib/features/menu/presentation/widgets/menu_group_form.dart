import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../../../core/ui/widgets/responsive_columns.dart';
import '../../domain/entities/menu_group.dart';
import '../../domain/entities/menu_inputs.dart';
import '../../domain/validation/menu_validation.dart';
import '../providers/menu_providers.dart';
import 'menu_dialogs.dart';

class MenuGroupForm extends ConsumerStatefulWidget {
  const MenuGroupForm({super.key, this.initial});
  final MenuGroup? initial;
  @override
  ConsumerState<MenuGroupForm> createState() => _MenuGroupFormState();
}

class _MenuGroupFormState extends ConsumerState<MenuGroupForm> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _order;
  MenuGroup? _baseline;
  bool _active = true;
  bool _busy = false;
  Failure? _failure;
  final _errors = <String, String>{};

  @override
  void initState() {
    super.initState();
    _baseline = widget.initial;
    _name = TextEditingController(text: _baseline?.name ?? '');
    _order = TextEditingController(text: '${_baseline?.displayOrder ?? 0}');
  }

  @override
  void dispose() {
    _name.dispose();
    _order.dispose();
    super.dispose();
  }

  void _edited(String field) => setState(() {
    _errors.remove(field);
    if (_errors.isEmpty && !menuNeedsReload(_failure)) _failure = null;
  });

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final controller = ref.read(menuGroupControllerProvider);
    final baseline = _baseline;
    final result = baseline == null
        ? await controller.create(
            CreateMenuGroupInput(
              name: _name.text,
              displayOrder: int.parse(_order.text.trim()),
              active: _active,
            ),
          )
        : await controller.update(
            baseline.id,
            UpdateMenuGroupInput.changes(
              baseline,
              name: _name.text,
              displayOrder: int.parse(_order.text.trim()),
            ),
          );
    if (!mounted) return;
    if (result is Success<MenuGroup>) {
      Navigator.of(context).pop(true);
    } else if (result case Error(failure: final failure)) {
      setState(() {
        _busy = false;
        _failure = failure;
        _errors.addAll(failure.fieldErrors);
      });
    }
  }

  Future<void> _reload() async {
    final baseline = _baseline;
    if (_busy || baseline == null) return;
    if (!await confirmMenuDraftReload(context, ref, 'MENU_UPDATE') ||
        !mounted) {
      return;
    }
    setState(() => _busy = true);
    final result = await ref
        .read(menuGroupControllerProvider)
        .detail(baseline.id);
    if (!mounted) return;
    setState(() {
      _busy = false;
      switch (result) {
        case Success(value: final group):
          _baseline = group;
          _name.text = group.name;
          _order.text = '${group.displayOrder}';
          _failure = null;
          _errors.clear();
        case Error(failure: final failure):
          _failure = failure;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(menuGroupControllerProvider);
    final creating = _baseline == null;
    return Form(
      key: _form,
      child: MenuFormLayout(
        title: creating ? 'Thêm nhóm món' : 'Sửa nhóm món',
        busy: _busy,
        submitLabel: creating ? 'Tạo nhóm' : 'Lưu thay đổi',
        onSubmit:
            menuNeedsReload(_failure) ||
                !controller.can(creating ? 'MENU_CREATE' : 'MENU_UPDATE')
            ? null
            : _save,
        children: [
          MenuFailurePanel(
            failure: _failure,
            onReload: creating ? null : _reload,
          ),
          ResponsiveColumns(
            maxColumns: 2,
            children: [
              TextFormField(
                controller: _name,
                forceErrorText: _errors['name'],
                decoration: menuField('Tên nhóm *'),
                onChanged: (_) => _edited('name'),
                validator: (v) =>
                    MenuValidation.text(v ?? '', max: 100, required: true),
              ),
              TextFormField(
                controller: _order,
                forceErrorText: _errors['displayOrder'],
                decoration: menuField(
                  'Thứ tự hiển thị *',
                  helper: 'Số nguyên từ 0 trở lên.',
                ),
                keyboardType: TextInputType.number,
                onChanged: (_) => _edited('displayOrder'),
                validator: (v) => MenuValidation.displayOrder(v ?? ''),
              ),
            ],
          ),
          if (creating)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Nhóm đang hoạt động'),
              value: _active,
              onChanged: (value) => setState(() => _active = value),
            ),
        ],
      ),
    );
  }
}
