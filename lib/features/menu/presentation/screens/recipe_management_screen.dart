import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/providers.dart';
import '../../../../app/router/app_routes.dart';
import '../../../../core/auth/access_policy.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../../../core/ui/formatters/local_date.dart';
import '../../../../core/ui/widgets/responsive_dialog.dart';
import '../../domain/entities/menu_item.dart';
import '../../domain/entities/recipe.dart';
import '../controllers/recipe_controller.dart';
import '../providers/recipe_providers.dart';
import '../widgets/recipe_details.dart';
import '../widgets/recipe_dialogs.dart';
import '../widgets/recipe_form.dart';

class RecipeManagementScreen extends ConsumerWidget {
  const RecipeManagementScreen({
    super.key,
    required this.menuItemId,
    this.initialMenuItem,
  });
  final String menuItemId;
  final MenuItem? initialMenuItem;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authControllerProvider).state.session;
    if (!AccessPolicy.canRecipe(session, 'RECIPE_VIEW')) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Bạn không có quyền xem công thức hoặc tính năng công thức chưa khả dụng.',
          ),
        ),
      );
    }
    final scope = AccessPolicy.recipeScope(session);
    return _RecipeWorkspace(
      key: ValueKey((scope, menuItemId)),
      menuItemId: menuItemId,
      initialMenuItem:
          AccessPolicy.canMenu(session, 'MENU_VIEW') &&
              initialMenuItem?.id == menuItemId
          ? initialMenuItem
          : null,
    );
  }
}

class _RecipeWorkspace extends ConsumerStatefulWidget {
  const _RecipeWorkspace({
    super.key,
    required this.menuItemId,
    this.initialMenuItem,
  });
  final String menuItemId;
  final MenuItem? initialMenuItem;
  @override
  ConsumerState<_RecipeWorkspace> createState() => _RecipeWorkspaceState();
}

class _RecipeWorkspaceState extends ConsumerState<_RecipeWorkspace> {
  bool _history = false;
  bool _opening = false;
  MenuItem? get _menu =>
      ref.read(recipeMenuPriceProvider(widget.menuItemId)).menu;
  Failure? get _menuFailure =>
      ref.read(recipeMenuPriceProvider(widget.menuItemId)).failure;
  late final Object? _scope;
  RecipeController get _controller =>
      ref.read(recipeControllerProvider(widget.menuItemId));

  @override
  void initState() {
    super.initState();
    _scope = AccessPolicy.recipeScope(
      ref.read(authControllerProvider).state.session,
    );
  }

  bool get _current =>
      mounted &&
      _scope ==
          AccessPolicy.recipeScope(
            ref.read(authControllerProvider).state.session,
          );

  Future<void> _loadMenu() async {
    await ref.read(recipeMenuPriceProvider(widget.menuItemId)).load();
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _form({Recipe? source}) async {
    if (_opening || _controller.busy) return;
    setState(() => _opening = true);
    final controller = _controller;
    // Reusing history must always read the current baseline, independently of its content.
    if (source != null) await controller.loadActive();
    if (!mounted || !_current) return;
    if (controller.activeFailure != null || !controller.activeLoaded) {
      _message(
        controller.activeFailure?.message ??
            'Chưa tải được công thức đang áp dụng.',
      );
      setState(() => _opening = false);
      return;
    }
    final baseline = controller.active;
    final permission = baseline == null ? 'RECIPE_CREATE' : 'RECIPE_UPDATE';
    if (!controller.can(permission)) {
      setState(() => _opening = false);
      _message(
        'Bạn không có quyền ${baseline == null ? "thiết lập công thức" : "tạo phiên bản mới"} theo trạng thái đang áp dụng hiện tại.',
      );
      return;
    }
    if (baseline == null) {
      // An inactive history does not protect the current menu unit from edits.
      await _loadMenu();
      if (!mounted || !_current) return;
    }
    setState(() => _opening = false);
    await showRecipeDialog<bool>(
      context,
      ref,
      permission: permission,
      child: RecipeForm(
        menuItemId: widget.menuItemId,
        baseline: baseline,
        source: source,
        yieldUnit: _menu?.baseUnit,
        reconcileHistory: source != null,
      ),
    );
  }

  Future<void> _deactivate(Recipe recipe) async {
    if (_opening || _controller.busy || !_controller.can('RECIPE_DELETE')) {
      return;
    }
    if (!await confirmRecipeChange(
          context,
          ref,
          permission: 'RECIPE_DELETE',
          title: 'Ngừng áp dụng công thức?',
          message:
              'Ngừng áp dụng phiên bản ${recipe.recipeVersion}? Công thức và lịch sử vẫn được lưu.',
          confirmLabel: 'Ngừng áp dụng',
          cancelLabel: 'Hủy',
        ) ||
        !_current) {
      return;
    }
    final result = await _controller.deactivate(recipe);
    if (!mounted || !_current) return;
    switch (result) {
      case Success():
        _message(
          'Đã ngừng áp dụng phiên bản ${recipe.recipeVersion}.${_controller.activeFailure == null ? "" : " Chưa xác minh được công thức đang áp dụng: ${_controller.activeFailure!.message}"}',
        );
      case Error(failure: final failure):
        _message(failure.message);
    }
  }

  Future<void> _detail(RecipeSummary summary) async {
    final result = await showRecipeDialog<Recipe>(
      context,
      ref,
      permission: 'RECIPE_VIEW',
      child: _HistoryDetail(
        menuItemId: widget.menuItemId,
        recipeId: summary.id,
      ),
    );
    if (_current && result != null) await _form(source: result);
  }

  Widget _active(RecipeController controller) {
    if (controller.activeLoading && !controller.activeLoaded) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (controller.activeFailure != null) {
      return RecipeNotice(
        message: controller.activeFailure!.message,
        error: true,
        action: TextButton(
          onPressed: controller.loadActive,
          child: const Text('Thử lại'),
        ),
      );
    }
    final recipe = controller.active;
    if (recipe == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.menu_book_outlined, size: 40),
            const SizedBox(height: 12),
            Text(
              'Món chưa có công thức đang áp dụng',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Thiết lập sản lượng và nguyên liệu cho cả công thức. Bạn vẫn có thể xem các phiên bản trong Lịch sử.',
            ),
            if (controller.can('RECIPE_CREATE')) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed:
                    _opening || controller.busy || !controller.activeLoaded
                    ? null
                    : _form,
                icon: const Icon(Icons.add),
                label: const Text('Thiết lập công thức'),
              ),
            ],
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.end,
          children: [
            if (controller.can('RECIPE_UPDATE'))
              FilledButton.icon(
                onPressed: _opening || controller.busy ? null : _form,
                icon: const Icon(Icons.edit_note),
                label: const Text('Tạo phiên bản mới'),
              ),
            if (controller.can('RECIPE_DELETE'))
              PopupMenuButton<String>(
                tooltip: 'Thao tác công thức',
                enabled: !controller.busy && !_opening,
                onSelected: (_) => _deactivate(recipe),
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'deactivate',
                    child: Text('Ngừng áp dụng'),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 16),
        RecipeDetails(recipe: recipe),
      ],
    );
  }

  Widget _historyList(RecipeController controller) {
    final history = controller.history;
    final query = controller.query;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: 260,
              child: DropdownButtonFormField<String>(
                value: query.sortBy,
                itemHeight: null,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Sắp xếp theo',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'recipeVersion',
                    child: Text('Phiên bản'),
                  ),
                  DropdownMenuItem(value: 'createdAt', child: Text('Ngày tạo')),
                  DropdownMenuItem(
                    value: 'updatedAt',
                    child: Text('Ngày cập nhật'),
                  ),
                ],
                onChanged: controller.historyLoading
                    ? null
                    : (value) {
                        if (value != null) {
                          controller.setHistoryQuery(
                            query.copyWith(page: 0, sortBy: value),
                          );
                        }
                      },
              ),
            ),
            SizedBox(
              width: 260,
              child: DropdownButtonFormField<String>(
                value: query.direction,
                itemHeight: null,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Thứ tự',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'desc', child: Text('Giảm dần')),
                  DropdownMenuItem(value: 'asc', child: Text('Tăng dần')),
                ],
                onChanged: controller.historyLoading
                    ? null
                    : (value) {
                        if (value != null) {
                          controller.setHistoryQuery(
                            query.copyWith(page: 0, direction: value),
                          );
                        }
                      },
              ),
            ),
          ],
        ),
        if (controller.historyLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: LinearProgressIndicator(),
          ),
        if (controller.historyFailure != null)
          RecipeNotice(
            message: controller.historyFailure!.message,
            error: true,
            action: TextButton(
              onPressed: controller.loadHistory,
              child: const Text('Thử lại'),
            ),
          ),
        if (history != null &&
            history.content.isEmpty &&
            !controller.historyLoading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('Chưa có lịch sử công thức.'),
          ),
        const SizedBox(height: 12),
        if (history != null)
          for (final row in history.content)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                key: ValueKey('recipe-history-${row.id}'),
                borderRadius: BorderRadius.circular(12),
                onTap: () => _detail(row),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Phiên bản ${row.recipeVersion}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(row.active ? 'Đang áp dụng' : 'Đã ngừng áp dụng'),
                      Text('Sản lượng: ${row.yieldQuantity} ${row.yieldUnit}'),
                      Text('${row.ingredientCount} nguyên liệu'),
                      Text('Cập nhật: ${formatLocalDate(row.updatedAt)}'),
                      const SizedBox(height: 8),
                      const Text(
                        'Xem chi tiết',
                        style: TextStyle(decoration: TextDecoration.underline),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        if (history != null)
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              IconButton(
                tooltip: 'Trang lịch sử trước',
                onPressed: query.page == 0 || controller.historyLoading
                    ? null
                    : () => controller.setHistoryQuery(
                        query.copyWith(page: query.page - 1),
                      ),
                icon: const Icon(Icons.chevron_left),
              ),
              Text(
                'Trang ${query.page + 1}/${history.totalPages < 1 ? 1 : history.totalPages} • ${history.totalElements} công thức',
              ),
              IconButton(
                tooltip: 'Trang lịch sử sau',
                onPressed:
                    query.page + 1 >= history.totalPages ||
                        controller.historyLoading
                    ? null
                    : () => controller.setHistoryQuery(
                        query.copyWith(page: query.page + 1),
                      ),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(recipeControllerProvider(widget.menuItemId));
    ref.watch(recipeMenuPriceProvider(widget.menuItemId));
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                IconButton(
                  tooltip: 'Quay lại',
                  onPressed: () {
                    if (Navigator.of(context).canPop()) {
                      Navigator.of(context).pop();
                    } else {
                      context.go(
                        AccessPolicy.canMenu(
                              ref.read(authControllerProvider).state.session,
                              'MENU_VIEW',
                            )
                            ? AppRoutes.menu
                            : AppRoutes.appHome,
                      );
                    }
                  },
                  icon: const Icon(Icons.arrow_back),
                ),
                Text(
                  'Công thức',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                IconButton(
                  tooltip: 'Làm mới công thức',
                  onPressed: controller.busy ? null : controller.refresh,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
          if (controller.activeLoading && controller.activeLoaded)
            const LinearProgressIndicator(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: double.infinity),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_menu != null) ...[
                        Text(
                          _menu!.name,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        if (_menu!.sku?.isNotEmpty == true)
                          Text('SKU: ${_menu!.sku}'),
                        Text('Đơn vị món: ${_menu!.baseUnit}'),
                      ],
                      if (_menuFailure != null)
                        RecipeNotice(
                          message:
                              'Chưa tải được thông tin danh mục món: ${_menuFailure!.message}',
                        ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('Đang áp dụng'),
                            selected: !_history,
                            onSelected: (_) => setState(() => _history = false),
                          ),
                          ChoiceChip(
                            label: const Text('Lịch sử'),
                            selected: _history,
                            onSelected: (_) {
                              setState(() => _history = true);
                              if (controller.history == null &&
                                  !controller.historyLoading) {
                                unawaited(controller.loadHistory());
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _history ? _historyList(controller) : _active(controller),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryDetail extends ConsumerStatefulWidget {
  const _HistoryDetail({required this.menuItemId, required this.recipeId});
  final String menuItemId;
  final String recipeId;
  @override
  ConsumerState<_HistoryDetail> createState() => _HistoryDetailState();
}

class _HistoryDetailState extends ConsumerState<_HistoryDetail> {
  Recipe? _recipe;
  Failure? _failure;
  bool _loading = true;
  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failure = null;
    });
    final controller = ref.read(recipeControllerProvider(widget.menuItemId));
    final result = await controller.detail(widget.recipeId);
    if (!mounted || !controller.isCurrent) return;
    setState(() {
      _loading = false;
      switch (result) {
        case Success(value: final recipe):
          _recipe = recipe;
        case Error(failure: final failure):
          _failure = failure;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(recipeControllerProvider(widget.menuItemId));
    return ResponsiveDialog(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Chi tiết công thức',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          if (_loading) const LinearProgressIndicator(),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_failure != null)
                    RecipeNotice(
                      message: _failure!.message,
                      error: true,
                      action: TextButton(
                        onPressed: _load,
                        child: const Text('Thử lại'),
                      ),
                    ),
                  if (_recipe != null) RecipeDetails(recipe: _recipe!),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Đóng'),
              ),
              if (_recipe != null &&
                  controller.can(
                    controller.active == null
                        ? 'RECIPE_CREATE'
                        : 'RECIPE_UPDATE',
                  ))
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(_recipe),
                  child: const Text('Dùng nội dung này tạo phiên bản mới'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
