import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/providers.dart';
import '../../../../core/auth/access_policy.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../../../core/ui/widgets/responsive_dialog.dart';
import '../../domain/entities/ingredient.dart';
import '../../domain/entities/recipe.dart';
import '../../domain/entities/recipe_amount.dart';
import '../../domain/entities/recipe_inputs.dart';
import '../../domain/use_cases/ingredient_use_cases.dart';
import '../../domain/use_cases/menu_item_use_cases.dart';
import '../../domain/validation/recipe_validation.dart';
import '../providers/recipe_providers.dart';
import 'recipe_dialogs.dart';
import 'recipe_ingredient_picker.dart';

class _DraftLine {
  _DraftLine({
    required this.key,
    required this.ingredientId,
    required this.name,
    required this.sku,
    required this.unit,
    required String quantity,
    required String waste,
  }) : quantity = TextEditingController(text: quantity),
       waste = TextEditingController(text: waste);
  final int key;
  String ingredientId;
  String name;
  String? sku;
  String unit;
  final TextEditingController quantity;
  final TextEditingController waste;
  final anchor = GlobalKey();
  final errors = <String, String>{};
  String? blocked;
  String? notice;
  bool verifyBeforeSave = false;
  void dispose() {
    quantity.dispose();
    waste.dispose();
  }
}

/// The form owns its draft. Controller refreshes never write into these fields.
class RecipeForm extends ConsumerStatefulWidget {
  const RecipeForm({
    super.key,
    required this.menuItemId,
    this.baseline,
    this.source,
    this.yieldUnit,
    this.reconcileHistory = false,
  });
  final String menuItemId;

  /// Only the current active aggregate supplies the mutation id and lock version.
  final Recipe? baseline;

  /// Historical content is deliberately separate from the update baseline.
  final Recipe? source;
  final String? yieldUnit;
  final bool reconcileHistory;

  @override
  ConsumerState<RecipeForm> createState() => _RecipeFormState();
}

class _RecipeFormState extends ConsumerState<RecipeForm> {
  final _yield = TextEditingController();
  final _yieldAnchor = GlobalKey();
  final _rowsAnchor = GlobalKey();
  final _lines = <_DraftLine>[];
  Recipe? _baseline;
  String? _unit;
  String? _yieldError;
  String? _listError;
  String? _verificationError;
  String? _yieldNotice;
  Failure? _failure;
  int _nextKey = 0;
  bool _busy = false;
  bool _verifying = false;
  bool _dirty = false;
  bool _allowClose = false;
  bool _outcomeUnknown = false;
  bool _savedWithoutApplication = false;
  late Object? _scope;
  String get _permission =>
      _baseline == null ? 'RECIPE_CREATE' : 'RECIPE_UPDATE';

  @override
  void initState() {
    super.initState();
    _baseline = widget.baseline;
    _scope = AccessPolicy.recipeScope(
      ref.read(authControllerProvider).state.session,
    );
    _apply(widget.source ?? widget.baseline, widget.yieldUnit);
    if (widget.reconcileHistory) {
      for (final line in _lines) {
        line.verifyBeforeSave = true;
      }
      _verifying = true;
      Future.microtask(_reconcile);
    }
  }

  bool get _current =>
      mounted &&
      _scope ==
          AccessPolicy.recipeScope(
            ref.read(authControllerProvider).state.session,
          );

  void _apply(Recipe? source, String? unit) {
    for (final line in _lines) {
      line.dispose();
    }
    _lines.clear();
    _yield.text = source?.yieldQuantity.toString() ?? '';
    _unit = source?.yieldUnit ?? unit;
    if (source != null) {
      for (final row in source.ingredients) {
        _lines.add(
          _DraftLine(
            key: _nextKey++,
            ingredientId: row.ingredientId,
            name: row.name,
            sku: row.sku,
            unit: row.unit,
            quantity: row.quantity.toString(),
            waste: row.wastePercent.toString(),
          ),
        );
      }
    }
  }

  Future<void> _reconcile() async {
    final session = ref.read(authControllerProvider).state.session;
    if (!AccessPolicy.canMenu(session, 'MENU_VIEW') ||
        !AccessPolicy.canIngredient(session, 'INGREDIENT_VIEW')) {
      if (!mounted || !_current) return;
      setState(() {
        _verifying = false;
        _verificationError =
            'Cần quyền xem món và xem nguyên liệu để đối chiếu đơn vị, tình trạng hiện tại trước khi dùng lại lịch sử. Nội dung lịch sử vẫn được giữ để xem.';
      });
      return;
    }
    final menu = await GetMenuItemDetail(ref.read(menuItemRepositoryProvider))(
      widget.menuItemId,
    );
    if (!mounted || !_current) return;
    if (menu case Error(failure: final failure)) {
      setState(() {
        _verifying = false;
        _verificationError =
            'Chưa xác minh được đơn vị món: ${failure.message}';
      });
      return;
    }
    final currentMenu = (menu as Success).value;
    if (_unit != currentMenu.baseUnit) {
      _unit = currentMenu.baseUnit;
      _yield.clear();
      _yieldNotice =
          'Đơn vị món đã đổi. Hãy nhập lại sản lượng theo đơn vị $_unit; số lượng cũ không được quy đổi.';
    }
    final detail = GetIngredientDetail(ref.read(ingredientRepositoryProvider));
    // Keep one result per stable draft row; never match by a name or guessed id.
    final rows = List<_DraftLine>.of(_lines);
    final results = await Future.wait(
      rows.map((line) => detail(line.ingredientId)),
    );
    if (!mounted || !_current) return;
    for (var i = 0; i < rows.length; i++) {
      final line = rows[i];
      switch (results[i]) {
        case Success(value: final item):
          if (item.id != line.ingredientId || !item.active) {
            line.blocked =
                'Nguyên liệu không còn hoạt động. Hãy thay hoặc bỏ dòng này.';
            continue;
          }
          line.name = item.name;
          line.sku = item.sku;
          if (line.unit != item.baseUnit) {
            line.quantity.clear();
            line.notice =
                'Đơn vị đã đổi từ ${line.unit} sang ${item.baseUnit}. Hãy nhập lại lượng dùng; không tự quy đổi.';
          }
          line.unit = item.baseUnit;
        case Error(failure: final failure):
          line.blocked = failure.code == 'INGREDIENT_NOT_FOUND'
              ? 'Nguyên liệu đã bị xóa hoặc không còn truy cập được. Hãy thay hoặc bỏ dòng này.'
              : 'Chưa xác minh được nguyên liệu: ${failure.message} Hãy thay hoặc bỏ dòng này.';
      }
    }
    setState(() {
      _verifying = false;
      _dirty = true;
    });
  }

  @override
  void dispose() {
    _yield.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  void _edited() {
    setState(() => _dirty = true);
  }

  Future<void> _close() async {
    if (_busy || _verifying) return;
    if (_dirty &&
        !await confirmRecipeChange(
          context,
          ref,
          permission: _permission,
          title: 'Bỏ thay đổi công thức?',
          message:
              'Bản nháp chưa lưu sẽ bị bỏ. Phiên bản hiện hành không thay đổi.',
          confirmLabel: 'Bỏ bản nháp',
        )) {
      return;
    }
    if (!mounted) return;
    setState(() => _allowClose = true);
    Navigator.of(context).pop();
  }

  Future<void> _pick({_DraftLine? replace}) async {
    if (_busy || _verifying || _lines.length >= 100 && replace == null) return;
    final session = ref.read(authControllerProvider).state.session;
    if (!AccessPolicy.canIngredient(session, 'INGREDIENT_VIEW')) return;
    final result = await showRecipeDialog<List<Ingredient>>(
      context,
      ref,
      permission: _permission,
      child: RecipeIngredientPicker(
        menuItemId: widget.menuItemId,
        permission: _permission,
        maxSelection: replace == null ? 100 - _lines.length : 1,
        selectedIds: {for (final line in _lines) line.ingredientId},
      ),
    );
    if (!_current || result == null || result.isEmpty) return;
    setState(() {
      for (final item in result) {
        if (_lines.any((line) => line.ingredientId == item.id)) continue;
        if (replace != null) {
          replace.ingredientId = item.id;
          replace.name = item.name;
          replace.sku = item.sku;
          replace.unit = item.baseUnit;
          replace.quantity.clear();
          replace.waste.text = '0';
          replace.blocked = null;
          replace.notice = 'Hãy nhập lượng dùng cho nguyên liệu thay thế.';
          replace.errors.clear();
          replace.verifyBeforeSave = true;
          break;
        }
        if (_lines.length >= 100) break;
        _lines.add(
          _DraftLine(
            key: _nextKey++,
            ingredientId: item.id,
            name: item.name,
            sku: item.sku,
            unit: item.baseUnit,
            quantity: '',
            waste: '0',
          )..verifyBeforeSave = true,
        );
      }
      _listError = null;
      _dirty = true;
    });
  }

  Future<void> _scrollTo(GlobalKey key) async {
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    final target = key.currentContext;
    if (target != null && target.mounted) {
      await Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 200),
        alignment: .1,
      );
    }
  }

  bool _validate() {
    _yieldError = RecipeValidation.quantity(_yield.text);
    _listError = _lines.isEmpty || _lines.length > 100
        ? 'Công thức cần từ 1 đến 100 nguyên liệu.'
        : null;
    final seen = <String>{};
    for (final line in _lines) {
      line.errors.clear();
      final quantity = RecipeValidation.quantity(line.quantity.text);
      final waste = RecipeValidation.wastePercent(line.waste.text);
      if (quantity != null) line.errors['quantity'] = quantity;
      if (waste != null) line.errors['wastePercent'] = waste;
      if (!seen.add(line.ingredientId)) {
        line.errors['ingredientId'] = 'Nguyên liệu đã có trong công thức.';
      }
      if (line.blocked != null) line.errors['ingredientId'] = line.blocked!;
    }
    setState(() {});
    if (_yieldError != null) {
      unawaited(_scrollTo(_yieldAnchor));
      return false;
    }
    if (_listError != null) {
      unawaited(_scrollTo(_rowsAnchor));
      return false;
    }
    for (final line in _lines) {
      if (line.errors.isNotEmpty) {
        unawaited(_scrollTo(line.anchor));
        return false;
      }
    }
    return true;
  }

  Future<void> _save({bool useRecipe = false}) async {
    if (_busy ||
        _savedWithoutApplication ||
        _verifying ||
        _verificationError != null ||
        _outcomeUnknown ||
        recipeNeedsReload(_failure) ||
        _baseline == null && _unit == null ||
        !_validate()) {
      return;
    }
    final controller = ref.read(recipeControllerProvider(widget.menuItemId));
    if (!controller.can(_permission)) return;
    setState(() => _busy = true);
    if (!await _verifyForSave()) {
      if (mounted && _current) setState(() => _busy = false);
      return;
    }
    if (!mounted || !_current) return;
    final input = RecipeInput(
      yieldQuantity: RecipeQuantity.parse(_yield.text),
      ingredients: [
        for (final line in _lines)
          RecipeIngredientInput(
            ingredientId: line.ingredientId,
            quantity: RecipeQuantity.parse(line.quantity.text),
            wastePercent: RecipeWastePercent.parseOrZero(line.waste.text),
          ),
      ],
    );
    setState(() {
      _busy = true;
      _failure = null;
    });
    // The mapping remains stable even if later rows are removed after a failure.
    final submittedRows = List<_DraftLine>.of(_lines);
    final baseline = _baseline;
    Future<Result<Recipe>> saveDefinition() => baseline == null
        ? controller.create(input)
        : controller.createVersion(baseline, input);
    final application = useRecipe
        ? ref.read(recipeApplicationProvider(widget.menuItemId))
        : null;
    final result = application == null
        ? await saveDefinition()
        : await application.saveAndEnable(saveDefinition);
    if (!mounted || !_current) return;
    switch (result) {
      case Success():
        setState(() {
          _busy = false;
          _allowClose = true;
          _dirty = false;
        });
        Navigator.of(context).pop(true);
      case Error(failure: final failure):
        final definitionSaved =
            useRecipe && application?.savedDefinition != null;
        setState(() {
          _busy = false;
          _failure = failure;
          _savedWithoutApplication = definitionSaved;
          _outcomeUnknown = !definitionSaved && failure.isNetwork;
          if (definitionSaved) {
            _allowClose = true;
            _dirty = false;
          }
          for (final entry in failure.fieldErrors.entries) {
            if (entry.key == 'yieldQuantity') {
              _yieldError = entry.value;
            } else if (entry.key == 'ingredients') {
              _listError = entry.value;
            } else {
              final match = RegExp(
                r'^ingredients(?:\[(\d+)\]|\.(\d+))\.(\w+)$',
              ).firstMatch(entry.key);
              final index = match == null
                  ? null
                  : int.tryParse(match[1] ?? match[2]!);
              if (index != null && index < submittedRows.length) {
                submittedRows[index].errors[match![3]!] = entry.value;
              }
            }
          }
        });
        if (_yieldError != null) {
          unawaited(_scrollTo(_yieldAnchor));
        } else {
          for (final line in submittedRows) {
            if (line.errors.isNotEmpty) {
              unawaited(_scrollTo(line.anchor));
              break;
            }
          }
        }
    }
  }

  Future<void> _enableSavedDefinition() async {
    if (_busy || !_savedWithoutApplication || !_current) return;
    final application = ref.read(recipeApplicationProvider(widget.menuItemId));
    if (!application.canSet(true)) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    await application.load();
    if (!mounted || !_current) return;
    if (application.failure != null || application.item == null) {
      setState(() {
        _busy = false;
        _failure = application.failure;
      });
      return;
    }
    final result = await application.setEnabled(true);
    if (!mounted || !_current) return;
    switch (result) {
      case Success():
        setState(() {
          _busy = false;
          _allowClose = true;
        });
        Navigator.of(context).pop(true);
      case Error(failure: final failure):
        setState(() {
          _busy = false;
          _failure = failure;
        });
    }
  }

  /// Unsaved catalog selections are checked again because their units can change
  /// before any active recipe protects them. Existing active snapshots need no lookup.
  Future<bool> _verifyForSave() async {
    var valid = true;
    final session = ref.read(authControllerProvider).state.session;
    if (_baseline == null) {
      if (!AccessPolicy.canMenu(session, 'MENU_VIEW')) {
        setState(
          () => _verificationError =
              'Cần quyền xem món để xác minh đơn vị sản lượng trước khi thiết lập công thức.',
        );
        return false;
      }
      final result = await GetMenuItemDetail(
        ref.read(menuItemRepositoryProvider),
      )(widget.menuItemId);
      if (!mounted || !_current) return false;
      switch (result) {
        case Success(value: final item):
          if (_unit != item.baseUnit) {
            _unit = item.baseUnit;
            _yield.clear();
            _dirty = true;
            valid = false;
            _yieldNotice =
                'Đơn vị món đã đổi. Hãy nhập lại sản lượng theo đơn vị $_unit; không tự quy đổi.';
          }
        case Error(failure: final failure):
          setState(() {
            _failure = failure;
            _unit = null;
            _verificationError =
                'Chưa xác minh được đơn vị món: ${failure.message}';
          });
          return false;
      }
    }
    final rows = _lines.where((line) => line.verifyBeforeSave).toList();
    if (rows.isNotEmpty &&
        !AccessPolicy.canIngredient(session, 'INGREDIENT_VIEW')) {
      setState(
        () => _verificationError =
            'Cần quyền xem nguyên liệu để xác minh các nguyên liệu mới chọn.',
      );
      return false;
    }
    final detail = GetIngredientDetail(ref.read(ingredientRepositoryProvider));
    final results = await Future.wait(
      rows.map((line) => detail(line.ingredientId)),
    );
    if (!mounted || !_current) return false;
    for (var i = 0; i < rows.length; i++) {
      final line = rows[i];
      switch (results[i]) {
        case Success(value: final item):
          if (!item.active || item.id != line.ingredientId) {
            line.blocked =
                'Nguyên liệu không còn hoạt động. Hãy thay hoặc bỏ dòng này.';
            valid = false;
          } else if (line.unit != item.baseUnit) {
            line.notice =
                'Đơn vị đã đổi từ ${line.unit} sang ${item.baseUnit}. Hãy nhập lại lượng dùng; không tự quy đổi.';
            line.unit = item.baseUnit;
            line.quantity.clear();
            _dirty = true;
            valid = false;
          }
        case Error(failure: final failure):
          line.blocked =
              'Chưa xác minh được nguyên liệu: ${failure.message} Hãy thay hoặc bỏ dòng này.';
          valid = false;
      }
    }
    setState(() {});
    if (!valid) _validate();
    return valid;
  }

  Future<void> _check() async {
    if (_busy) return;
    setState(() => _busy = true);
    final controller = ref.read(recipeControllerProvider(widget.menuItemId));
    await Future.wait([controller.loadActive(), controller.loadHistory()]);
    if (!mounted || !_current) return;
    setState(() {
      _busy = false;
      if (controller.activeFailure == null &&
          controller.historyFailure == null) {
        _outcomeUnknown = false;
        _failure = Failure(
          type: FailureType.conflict,
          code: 'CONCURRENT_RECIPE_UPDATE',
          message:
              'Đã kiểm tra dữ liệu mới nhất. ${controller.active == null ? "Món chưa có phiên bản hiện hành." : "Phiên bản hiện hành phiên bản ${controller.active!.recipeVersion}."} Bản nháp của bạn được giữ nguyên. Hãy xem lại dữ liệu trước khi quyết định lưu hoặc tải lại bản nháp.',
        );
      } else {
        _failure = controller.activeFailure ?? controller.historyFailure;
      }
    });
  }

  Future<void> _reloadDraft() async {
    if (_busy ||
        !await confirmRecipeChange(
          context,
          ref,
          permission: _permission,
          title: 'Tải lại bản nháp từ phiên bản hiện hành?',
          message:
              'Bản nháp hiện tại sẽ bị thay bằng dữ liệu mới nhất. Bạn cần xem lại trước khi lưu.',
          confirmLabel: 'Thay bản nháp',
        )) {
      return;
    }
    if (!mounted || !_current) return;
    setState(() => _busy = true);
    final controller = ref.read(recipeControllerProvider(widget.menuItemId));
    await controller.refresh();
    if (!mounted || !_current) return;
    String? freshUnit;
    Failure? unitFailure;
    if (controller.active == null && controller.activeFailure == null) {
      final session = ref.read(authControllerProvider).state.session;
      if (AccessPolicy.canMenu(session, 'MENU_VIEW')) {
        final result = await GetMenuItemDetail(
          ref.read(menuItemRepositoryProvider),
        )(widget.menuItemId);
        if (!mounted || !_current) return;
        switch (result) {
          case Success(value: final item):
            freshUnit = item.baseUnit;
          case Error(failure: final failure):
            unitFailure = failure;
        }
      }
    }
    setState(() {
      _busy = false;
      if (controller.activeFailure != null || !controller.activeLoaded) {
        _failure = controller.activeFailure;
        return;
      }
      final next = controller.active;
      final nextPermission = next == null ? 'RECIPE_CREATE' : 'RECIPE_UPDATE';
      if (!controller.can(nextPermission)) {
        _failure = const Failure(
          type: FailureType.forbidden,
          message: 'Bạn không có quyền lưu công thức theo trạng thái mới nhất.',
        );
        return;
      }
      _baseline = next;
      _apply(next, freshUnit);
      _failure = null;
      _yieldError = null;
      _listError = null;
      _verificationError = next == null && freshUnit == null
          ? 'Chưa xác minh được đơn vị món hiện tại.${unitFailure == null ? " Cần quyền xem món." : " ${unitFailure.message}"}'
          : null;
      _yieldNotice = null;
      _outcomeUnknown = false;
      _dirty = false;
    });
  }

  Widget _line(_DraftLine line, bool canRead) => Card(
    key: ValueKey('recipe-draft-${line.key}'),
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      key: line.anchor,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(line.name, style: Theme.of(context).textTheme.titleMedium),
          if (line.sku?.isNotEmpty == true) Text('SKU: ${line.sku}'),
          Text('Đơn vị cơ sở: ${line.unit}'),
          if (line.blocked != null)
            RecipeNotice(message: line.blocked!, error: true),
          if (line.notice != null) RecipeNotice(message: line.notice!),
          if (line.errors['ingredientId'] != null)
            RecipeNotice(message: line.errors['ingredientId']!, error: true),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final fields = [
                TextField(
                  key: ValueKey('recipe-quantity-${line.key}'),
                  controller: line.quantity,
                  enabled:
                      !_busy &&
                      !_verifying &&
                      !_savedWithoutApplication &&
                      line.blocked == null,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Lượng dùng cho cả công thức',
                    helperText: 'Đơn vị: ${line.unit}',
                    errorText: line.errors['quantity'],
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) {
                    line.errors.remove('quantity');
                    _edited();
                  },
                ),
                TextField(
                  key: ValueKey('recipe-waste-${line.key}'),
                  controller: line.waste,
                  enabled:
                      !_busy &&
                      !_verifying &&
                      !_savedWithoutApplication &&
                      line.blocked == null,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Hao hụt (%)',
                    helperText: 'Từ 0 đến 100',
                    errorText: line.errors['wastePercent'],
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) {
                    line.errors.remove('wastePercent');
                    _edited();
                  },
                ),
              ];
              if (constraints.maxWidth >= 640 &&
                  MediaQuery.textScalerOf(context).scale(1) < 1.7) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 2, child: fields[0]),
                    const SizedBox(width: 12),
                    Expanded(child: fields[1]),
                  ],
                );
              }
              return Column(
                children: [fields[0], const SizedBox(height: 12), fields[1]],
              );
            },
          ),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (canRead)
                TextButton.icon(
                  onPressed: _busy || _verifying || _savedWithoutApplication
                      ? null
                      : () => _pick(replace: line),
                  icon: const Icon(Icons.swap_horiz),
                  label: const Text('Thay nguyên liệu'),
                ),
              TextButton.icon(
                key: ValueKey('recipe-remove-${line.key}'),
                onPressed: _busy || _verifying || _savedWithoutApplication
                    ? null
                    : () => setState(() {
                        _lines.remove(line);
                        line.dispose();
                        _dirty = true;
                      }),
                icon: const Icon(Icons.remove_circle_outline),
                label: const Text('Bỏ khỏi công thức'),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(recipeControllerProvider(widget.menuItemId));
    final session = ref.watch(authControllerProvider).state.session;
    final application = AccessPolicy.canMenu(session, 'MENU_UPDATE')
        ? ref.watch(recipeApplicationProvider(widget.menuItemId))
        : null;
    final canRead = AccessPolicy.canIngredient(session, 'INGREDIENT_VIEW');
    final available =
        !_savedWithoutApplication &&
        controller.can(_permission) &&
        _scope == AccessPolicy.recipeScope(session);
    return PopScope(
      canPop: _allowClose || !_dirty && !_busy && !_verifying,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_close());
      },
      child: ResponsiveDialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _baseline == null ? 'Thiết lập công thức' : 'Tạo phiên bản mới',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            if (_busy || _verifying) const LinearProgressIndicator(),
            Flexible(
              child: SingleChildScrollView(
                key: const ValueKey('recipe-form-scroll'),
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_failure != null)
                      RecipeNotice(
                        message: _failure!.message,
                        error: true,
                        action: _savedWithoutApplication
                            ? null
                            : Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  TextButton(
                                    onPressed: _busy ? null : _check,
                                    child: const Text(
                                      'Kiểm tra hiện hành và lịch sử',
                                    ),
                                  ),
                                  if (recipeNeedsReload(_failure) ||
                                      _failure!.isNetwork)
                                    TextButton(
                                      onPressed: _busy ? null : _reloadDraft,
                                      child: const Text('Tải lại bản nháp'),
                                    ),
                                ],
                              ),
                      ),
                    if (_savedWithoutApplication)
                      RecipeNotice(
                        message:
                            'Công thức đã được lưu. Chỉ cần kiểm tra và bật sử dụng; không lưu lại công thức.',
                        action: TextButton(
                          onPressed: _busy || application?.canSet(true) != true
                              ? null
                              : _enableSavedDefinition,
                          child: const Text('Kiểm tra và bật sử dụng'),
                        ),
                      ),
                    if (_verificationError != null)
                      RecipeNotice(message: _verificationError!, error: true),
                    if (_baseline == null &&
                        _unit == null &&
                        _verificationError == null)
                      const RecipeNotice(
                        message:
                            'Cần quyền xem món và dữ liệu đơn vị món hiện tại để thiết lập công thức.',
                        error: true,
                      ),
                    if (_verifying)
                      const RecipeNotice(
                        message:
                            'Đang đối chiếu món và nguyên liệu hiện tại. Bản lịch sử không được kích hoạt trực tiếp.',
                      ),
                    Text(
                      'Sản lượng công thức',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const ValueKey('recipe-yield'),
                      controller: _yield,
                      enabled: !_busy && !_verifying && available,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Sản lượng của cả công thức',
                        helperText: _unit == null
                            ? 'Đơn vị theo món; chưa có dữ liệu danh mục được phép đọc.'
                            : 'Đơn vị: $_unit (chỉ đọc)',
                        errorText: _yieldError,
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (_) {
                        _yieldError = null;
                        _edited();
                      },
                    ),
                    SizedBox(key: _yieldAnchor, height: 8),
                    if (_yieldNotice != null)
                      RecipeNotice(message: _yieldNotice!),
                    const Text(
                      'Ví dụ: công thức tạo ra 10 tô thì lượng nguyên liệu bên dưới là lượng dùng cho cả 10 tô.',
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Danh sách nguyên liệu (${_lines.length}/100)',
                      key: _rowsAnchor,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (_listError != null)
                      RecipeNotice(message: _listError!, error: true),
                    const SizedBox(height: 12),
                    for (final line in _lines) _line(line, canRead),
                    if (!canRead)
                      const RecipeNotice(
                        message:
                            'Cần quyền xem nguyên liệu để thêm hoặc thay nguyên liệu. Bạn vẫn có thể chỉnh định lượng các dòng snapshot đang có.',
                      ),
                    if (_lines.length >= 100)
                      const RecipeNotice(
                        message: 'Đã đạt giới hạn 100 nguyên liệu.',
                      ),
                    OutlinedButton.icon(
                      key: const ValueKey('recipe-add-ingredient'),
                      onPressed:
                          !canRead ||
                              _busy ||
                              _verifying ||
                              _lines.length >= 100 ||
                              !available
                          ? null
                          : _pick,
                      icon: const Icon(Icons.add),
                      label: const Text('Thêm nguyên liệu'),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Lưu công thức không tự bật sử dụng. Phiên bản hiện hành và lựa chọn sử dụng được quản lý riêng.',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                TextButton(
                  onPressed: _busy || _verifying ? null : _close,
                  child: const Text('Đóng'),
                ),
                FilledButton(
                  key: const ValueKey('recipe-submit'),
                  onPressed:
                      _busy ||
                          _verifying ||
                          !available ||
                          _verificationError != null ||
                          _outcomeUnknown ||
                          recipeNeedsReload(_failure) ||
                          _baseline == null && _unit == null
                      ? null
                      : _save,
                  child: Text(
                    _busy
                        ? 'Đang xử lý…'
                        : _baseline == null
                        ? 'Lưu công thức'
                        : 'Tạo phiên bản mới',
                  ),
                ),
                if (_baseline == null &&
                    application?.canSet(true) == true &&
                    !_savedWithoutApplication)
                  FilledButton.icon(
                    key: const ValueKey('recipe-submit-and-enable'),
                    onPressed:
                        _busy ||
                            _verifying ||
                            !available ||
                            _verificationError != null ||
                            _outcomeUnknown ||
                            recipeNeedsReload(_failure) ||
                            _unit == null
                        ? null
                        : () => _save(useRecipe: true),
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Lưu & sử dụng công thức'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
