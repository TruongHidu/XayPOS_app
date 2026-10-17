import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../../../core/ui/widgets/responsive_columns.dart';
import '../../domain/entities/ingredient.dart';
import '../../domain/entities/ingredient_inputs.dart';
import '../../domain/entities/menu_price.dart';
import '../../domain/validation/ingredient_validation.dart';
import '../providers/menu_providers.dart';
import 'ingredient_dialogs.dart';
import 'menu_dialogs.dart';

class IngredientForm extends ConsumerStatefulWidget {
  const IngredientForm({
    super.key,
    this.initial,
    this.typeSelector,
    this.onBusyChanged,
    this.onSuccess,
  });

  final Ingredient? initial;
  final Widget? typeSelector;
  final ValueChanged<bool>? onBusyChanged;
  final VoidCallback? onSuccess;

  @override
  ConsumerState<IngredientForm> createState() => _IngredientFormState();
}

class _IngredientFormState extends ConsumerState<IngredientForm> {
  final _form = GlobalKey<FormState>();
  final _fields = <String, TextEditingController>{};
  final _errors = <String, String>{};
  Ingredient? _baseline;
  bool _trackInventory = false;
  bool _active = true;
  bool _busy = false;
  bool _costPriceEdited = false;
  Failure? _failure;

  @override
  void initState() {
    super.initState();
    _baseline = widget.initial;
    for (final key in ['name', 'sku', 'baseUnit', 'costPrice', 'description']) {
      _fields[key] = TextEditingController();
    }
    _apply(_baseline);
  }

  void _apply(Ingredient? item) {
    _fields['name']!.text = item?.name ?? '';
    _fields['sku']!.text = item?.sku ?? '';
    _fields['baseUnit']!.text = item?.baseUnit ?? '';
    _fields['costPrice']!.text = item?.costPrice.toString() ?? '';
    _costPriceEdited = false;
    _fields['description']!.text = item?.description ?? '';
    _trackInventory = item?.trackInventory ?? false;
    _active = item?.active ?? true;
  }

  @override
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  void _setBusy(bool value) {
    if (_busy == value) return;
    setState(() => _busy = value);
    widget.onBusyChanged?.call(value);
  }

  String _text(String key) => _fields[key]!.text;

  void _edited(String key) => setState(() {
    if (key == 'costPrice') _costPriceEdited = true;
    _errors.remove(key);
    if (_errors.isEmpty &&
        (_baseline == null || !ingredientNeedsReload(_failure))) {
      _failure = null;
    }
  });

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    _setBusy(true);

    final controller = ref.read(ingredientControllerProvider);
    final baseline = _baseline;
    final costPrice = baseline == null
        ? MenuPrice.parseOrZero(_text('costPrice'))
        : (!_costPriceEdited
              ? null
              : MenuPrice.parseOrZero(_text('costPrice')));

    final result = baseline == null
        ? await controller.create(
            CreateIngredientInput(
              name: _text('name'),
              sku: _text('sku'),
              baseUnit: _text('baseUnit'),
              costPrice: costPrice ?? MenuPrice.zero,
              description: _text('description'),
              trackInventory: _trackInventory,
              active: _active,
            ),
          )
        : await controller.update(
            baseline.id,
            UpdateIngredientInput.changes(
              baseline,
              name: _text('name'),
              sku: _text('sku'),
              baseUnit: _text('baseUnit'),
              costPrice: costPrice,
              description: _text('description'),
              trackInventory: _trackInventory,
            ),
          );

    if (!mounted) return;
    if (result is Success<Ingredient>) {
      _setBusy(false);
      if (widget.onSuccess != null) {
        widget.onSuccess!();
      } else {
        Navigator.of(context).pop(true);
      }
    } else if (result case Error(failure: final failure)) {
      _setBusy(false);
      setState(() {
        _failure = failure;
        _errors.addAll(failure.fieldErrors);
        if (failure.code == 'SKU_EXISTS') {
          _errors['sku'] =
              'SKU có thể đang được món bán, nguyên liệu hoặc bản ghi đã xóa sử dụng.';
        }
      });
    }
  }

  Future<void> _reload() async {
    final baseline = _baseline;
    if (_busy || baseline == null) return;
    if (!await confirmIngredientDraftReload(
          context,
          ref,
          'INGREDIENT_UPDATE',
        ) ||
        !mounted) {
      return;
    }

    _setBusy(true);
    final result = await ref
        .read(ingredientControllerProvider)
        .detail(baseline.id);
    if (!mounted) return;
    _setBusy(false);

    setState(() {
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
    key: ValueKey('ingredient-$key'),
    controller: _fields[key],
    forceErrorText: _errors[key],
    decoration: menuField(label, helper: helper),
    keyboardType: keyboard,
    maxLines: lines,
    onChanged: (_) => _edited(key),
    validator: validator,
  );

  Widget _buildSectionHeader(String title) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(ingredientControllerProvider);
    final creating = _baseline == null;

    return Form(
      key: _form,
      child: MenuFormLayout(
        title: creating ? 'Thêm nguyên liệu' : 'Sửa thông tin nguyên liệu',
        header: widget.typeSelector,
        busy: _busy,
        submitLabel: creating ? 'Tạo nguyên liệu' : 'Lưu thay đổi',
        onSubmit:
            (!creating && ingredientNeedsReload(_failure)) ||
                !controller.can(
                  creating ? 'INGREDIENT_CREATE' : 'INGREDIENT_UPDATE',
                )
            ? null
            : _save,
        children: [
          MenuFailurePanel(
            failure: _failure,
            onReload: creating ? null : _reload,
          ),
          if (!creating)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text('Trạng thái: '),
                  Chip(
                    padding: EdgeInsets.zero,
                    labelPadding: const EdgeInsets.symmetric(horizontal: 8),
                    label: Text(
                      _baseline!.active ? 'Đang sử dụng' : 'Ngừng sử dụng',
                      style: const TextStyle(fontSize: 12),
                    ),
                    backgroundColor: _baseline!.active
                        ? Colors.green.withAlpha(30)
                        : Colors.grey.withAlpha(30),
                  ),
                  const Text(
                    'Trạng thái được đổi bằng thao tác riêng.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          _buildSectionHeader('Thông tin cơ bản'),
          ResponsiveColumns(
            children: [
              _field('name', 'Tên nguyên liệu *', IngredientValidation.name),
              _field(
                'sku',
                'SKU',
                IngredientValidation.sku,
                helper: 'Tối đa 80 ký tự, tự động viết hoa.',
              ),
              _field(
                'baseUnit',
                'Đơn vị cơ sở *',
                IngredientValidation.baseUnit,
                helper: 'Ví dụ: g, kg, ml, lít, cái.',
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildSectionHeader('Giá vốn và theo dõi'),
          ResponsiveColumns(
            children: [
              _field(
                'costPrice',
                'Giá vốn / đơn vị',
                IngredientValidation.costPrice,
                keyboard: const TextInputType.numberWithOptions(decimal: true),
                helper:
                    'Giá vốn tính cho 1 đơn vị cơ sở. Để trống là 0. Dùng dấu chấm, tối đa 2 chữ số thập phân.',
              ),
              SwitchListTile(
                key: const ValueKey('ingredient-track-inventory'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Theo dõi tồn kho'),
                subtitle: const Text(
                  'Đánh dấu nguyên liệu cần theo dõi tồn kho',
                ),
                value: _trackInventory,
                onChanged: (val) {
                  _edited('trackInventory');
                  setState(() => _trackInventory = val);
                },
              ),
              if (creating)
                SwitchListTile(
                  key: const ValueKey('ingredient-active'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Đang sử dụng'),
                  subtitle: Text(_active ? 'Đang sử dụng' : 'Ngừng sử dụng'),
                  value: _active,
                  onChanged: (val) => setState(() => _active = val),
                ),
            ],
          ),
          const SizedBox(height: 8),
          _buildSectionHeader('Mô tả'),
          _field(
            'description',
            'Mô tả',
            IngredientValidation.description,
            lines: 3,
            helper: 'Tùy chọn, tối đa 10.000 ký tự.',
          ),
        ],
      ),
    );
  }
}
