import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../../../core/ui/widgets/responsive_columns.dart';
import '../../domain/entities/menu_group.dart';
import '../../domain/entities/menu_item.dart';
import '../../domain/entities/menu_inputs.dart';
import '../../domain/entities/menu_price.dart';
import '../../domain/validation/menu_validation.dart';
import '../providers/menu_providers.dart';
import 'menu_dialogs.dart';
import 'menu_group_picker.dart';

class MenuItemForm extends ConsumerStatefulWidget {
  const MenuItemForm({super.key, this.initial});
  final MenuItem? initial;
  @override
  ConsumerState<MenuItemForm> createState() => _MenuItemFormState();
}

class _MenuItemFormState extends ConsumerState<MenuItemForm> {
  final _form = GlobalKey<FormState>();
  final _fields = <String, TextEditingController>{};
  final _errors = <String, String>{};
  MenuItem? _baseline;
  MenuItemGroupSummary? _group;
  bool _active = true;
  bool _busy = false;
  bool _costPriceEdited = false;
  Failure? _failure;

  @override
  void initState() {
    super.initState();
    _baseline = widget.initial;
    for (final key in [
      'name',
      'sku',
      'baseUnit',
      'salePrice',
      'costPrice',
      'description',
      'imageUrl',
    ]) {
      _fields[key] = TextEditingController();
    }
    _apply(_baseline);
  }

  void _apply(MenuItem? item) {
    _fields['name']!.text = item?.name ?? '';
    _fields['sku']!.text = item?.sku ?? '';
    _fields['baseUnit']!.text = item?.baseUnit ?? '';
    _fields['salePrice']!.text = item?.salePrice.toString() ?? '';
    _fields['costPrice']!.text = item?.costPrice?.toString() ?? '';
    _costPriceEdited = false;
    _fields['description']!.text = item?.description ?? '';
    _fields['imageUrl']!.text = item?.imageUrl ?? '';
    _group = item?.group;
  }

  @override
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  String _text(String key) => _fields[key]!.text;
  void _edited(String key) => setState(() {
    if (key == 'costPrice') _costPriceEdited = true;
    _errors.remove(key);
    if (_errors.isEmpty && (_baseline == null || !menuNeedsReload(_failure))) {
      _failure = null;
    }
  });
  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final controller = ref.read(menuItemControllerProvider);
    final baseline = _baseline;
    final price = MenuPrice.parse(_text('salePrice'));
    final costPrice =
        baseline != null && baseline.costPrice == null && !_costPriceEdited
        ? null
        : MenuPrice.parseOrZero(_text('costPrice'));
    final result = baseline == null
        ? await controller.create(
            CreateMenuItemInput(
              name: _text('name'),
              sku: _text('sku'),
              baseUnit: _text('baseUnit'),
              salePrice: price,
              costPrice: costPrice,
              description: _text('description'),
              imageUrl: _text('imageUrl'),
              groupId: _group?.id,
              active: _active,
            ),
            selectedGroup: _group,
          )
        : await controller.update(
            baseline.id,
            UpdateMenuItemInput.changes(
              baseline,
              name: _text('name'),
              sku: _text('sku'),
              baseUnit: _text('baseUnit'),
              salePrice: price,
              costPrice: costPrice,
              description: _text('description'),
              imageUrl: _text('imageUrl'),
            ),
          );
    if (!mounted) return;
    if (result is Success<MenuItem>) {
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
        .read(menuItemControllerProvider)
        .detail(baseline.id);
    if (!mounted) return;
    setState(() {
      _busy = false;
      switch (result) {
        case Success(value: final item):
          _baseline = item;
          _apply(item);
          _failure = null;
          _errors.clear();
        case Error(failure: final failure):
          _failure = failure;
      }
    });
  }

  Widget _field(
    String key,
    String label,
    String? Function(String?) validator, {
    String? helper,
    TextInputType? keyboard,
    int lines = 1,
  }) => TextFormField(
    key: ValueKey('menu-item-$key'),
    controller: _fields[key],
    forceErrorText: _errors[key],
    decoration: menuField(label, helper: helper),
    keyboardType: keyboard,
    maxLines: lines,
    onChanged: (_) => _edited(key),
    validator: validator,
  );

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(menuItemControllerProvider);
    final creating = _baseline == null;
    return Form(
      key: _form,
      child: MenuFormLayout(
        title: creating ? 'Thêm món' : 'Sửa thông tin món',
        busy: _busy,
        submitLabel: creating ? 'Tạo món' : 'Lưu thay đổi',
        onSubmit:
            (!creating && menuNeedsReload(_failure)) ||
                !controller.can(creating ? 'MENU_CREATE' : 'MENU_UPDATE')
            ? null
            : _save,
        children: [
          MenuFailurePanel(
            failure: _failure,
            onReload: creating ? null : _reload,
          ),
          if (!creating)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                'Nhóm hiện tại: ${_baseline!.group?.name ?? "Chưa phân nhóm"}. Trạng thái và nhóm được thay đổi bằng thao tác riêng.',
              ),
            ),
          ResponsiveColumns(
            children: [
              _field(
                'name',
                'Tên món *',
                (v) => MenuValidation.text(v ?? '', max: 150, required: true),
              ),
              _field(
                'sku',
                'SKU',
                (v) => MenuValidation.text(v ?? '', max: 80),
              ),
              _field(
                'baseUnit',
                'Đơn vị *',
                (v) => MenuValidation.text(v ?? '', max: 30, required: true),
                helper: 'Ví dụ: ly, phần, đĩa.',
              ),
              _field(
                'salePrice',
                'Giá bán *',
                (v) => MenuValidation.price(v ?? ''),
                keyboard: const TextInputType.numberWithOptions(decimal: true),
                helper:
                    'Dùng dấu chấm, ví dụ 35000.50. Tối đa 2 chữ số thập phân.',
              ),
              _field(
                'costPrice',
                'Giá vốn',
                MenuValidation.optionalPrice,
                keyboard: const TextInputType.numberWithOptions(decimal: true),
                helper:
                    !creating &&
                        _baseline!.costPrice == null &&
                        !_costPriceEdited
                    ? 'Để trống để giữ giá vốn hiện tại; nhập 0 để đặt về 0. Dùng dấu chấm, tối đa 2 chữ số thập phân.'
                    : 'Để trống sẽ tính là 0. Dùng dấu chấm, tối đa 2 chữ số thập phân.',
              ),
              _field(
                'imageUrl',
                'URL ảnh',
                MenuValidation.imageUrl,
                keyboard: TextInputType.url,
                helper: 'URL HTTP(S), tối đa 500 ký tự.',
              ),
              if (creating)
                MenuGroupPicker(
                  value: _group,
                  permission: 'MENU_CREATE',
                  errorText: _errors['groupId'],
                  onChanged: (value) {
                    _edited('groupId');
                    setState(() => _group = value);
                  },
                ),
            ],
          ),
          const SizedBox(height: 16),
          _field(
            'description',
            'Mô tả',
            (v) => MenuValidation.text(v ?? '', max: 10000),
            lines: 3,
          ),
          if (creating) ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Đang kinh doanh'),
              value: _active,
              onChanged: (value) => setState(() => _active = value),
            ),
            const Text('Món mới được khởi tạo ở trạng thái có hàng.'),
          ],
        ],
      ),
    );
  }
}
