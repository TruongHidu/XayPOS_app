import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/providers.dart';
import '../../../../core/auth/access_policy.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/ingredient.dart';
import 'menu_dialogs.dart';

Future<T?> showIngredientDialog<T>(
  BuildContext context,
  WidgetRef ref, {
  required String permission,
  required Widget child,
}) {
  final session = ref.read(authControllerProvider).state.session;
  if (!AccessPolicy.canIngredient(session, permission)) return Future.value();
  final scope = AccessPolicy.ingredientScope(session);
  return showDialog<T>(
    context: context,
    barrierDismissible: false,
    builder: (_) => IngredientScopeGuard(
      scope: scope,
      permission: permission,
      child: child,
    ),
  );
}

class IngredientScopeGuard extends ConsumerWidget {
  const IngredientScopeGuard({
    super.key,
    required this.scope,
    required this.permission,
    required this.child,
  });

  final Object? scope;
  final String permission;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authControllerProvider).state.session;
    if (AccessPolicy.ingredientScope(session) != scope ||
        !AccessPolicy.canIngredient(session, permission)) {
      final route = ModalRoute.of(context);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted && route != null && route.isActive) {
          Navigator.of(context).removeRoute(route);
        }
      });
      return const SizedBox.shrink();
    }
    return child;
  }
}

bool ingredientNeedsReload(Failure? failure) =>
    failure?.code == 'CONCURRENT_INGREDIENT_UPDATE' ||
    failure?.type == FailureType.notFound ||
    failure?.code == 'INVALID_INGREDIENT_TRANSITION';

Future<bool> confirmIngredientDraftReload(
  BuildContext context,
  WidgetRef ref,
  String permission,
) async =>
    await showIngredientDialog<bool>(
      context,
      ref,
      permission: permission,
      child: AlertDialog(
        title: const Text('Thay thế bản đang sửa?'),
        content: const Text(
          'Tải lại sẽ thay nội dung bạn đang sửa bằng dữ liệu mới nhất từ máy chủ.',
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(context, rootNavigator: true).pop(false),
            child: const Text('Giữ bản nháp'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context, rootNavigator: true).pop(true),
            child: const Text('Thay thế bản nháp'),
          ),
        ],
      ),
    ) ??
    false;

Future<Result<Object?>> ingredientDeleteResult(
  Future<Result<void>> future,
) async => switch (await future) {
  Success() => const Success(null),
  Error(failure: final failure) => Error(failure),
};

class IngredientConfirmDialog extends ConsumerStatefulWidget {
  const IngredientConfirmDialog({
    super.key,
    required this.initial,
    required this.title,
    required this.describe,
    required this.reload,
    required this.submit,
    required this.permission,
    this.label = 'Xác nhận',
  });

  final Ingredient initial;
  final String title, permission, label;
  final String Function(Ingredient) describe;
  final Future<Result<Ingredient>> Function() reload;
  final Future<Result<Object?>> Function(Ingredient) submit;

  @override
  ConsumerState<IngredientConfirmDialog> createState() =>
      _IngredientConfirmDialogState();
}

class _IngredientConfirmDialogState
    extends ConsumerState<IngredientConfirmDialog> {
  late Ingredient _baseline = widget.initial;
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
        !await confirmIngredientDraftReload(context, ref, widget.permission) ||
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
    onSubmit: ingredientNeedsReload(_failure) ? null : _submit,
    children: [
      MenuFailurePanel(failure: _failure, onReload: _reload),
      Text(widget.describe(_baseline)),
    ],
  );
}
