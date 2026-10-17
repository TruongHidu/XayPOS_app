import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/providers.dart';
import '../../../../core/auth/access_policy.dart';
import '../../../../core/errors/failure.dart';

Future<T?> showRecipeDialog<T>(
  BuildContext context,
  WidgetRef ref, {
  required String permission,
  required Widget child,
}) {
  final session = ref.read(authControllerProvider).state.session;
  if (!AccessPolicy.canRecipe(session, permission)) return Future.value();
  return showDialog<T>(
    context: context,
    barrierDismissible: false,
    builder: (_) => RecipeScopeGuard(
      scope: AccessPolicy.recipeScope(session),
      permission: permission,
      child: child,
    ),
  );
}

/// Recipe authorization is independent from menu and ingredient authorization.
class RecipeScopeGuard extends ConsumerWidget {
  const RecipeScopeGuard({
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
    if (scope != AccessPolicy.recipeScope(session) ||
        !AccessPolicy.canRecipe(session, permission)) {
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

bool recipeNeedsReload(Failure? failure) => const {
  'CONCURRENT_RECIPE_UPDATE',
  'ACTIVE_RECIPE_ALREADY_EXISTS',
  'RECIPE_NOT_ACTIVE',
  'RECIPE_NOT_FOUND',
  'ACTIVE_RECIPE_NOT_FOUND',
}.contains(failure?.code);

class RecipeNotice extends StatelessWidget {
  const RecipeNotice({
    super.key,
    required this.message,
    this.error = false,
    this.action,
  });
  final String message;
  final bool error;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: error ? colors.errorContainer : colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              message,
              style: TextStyle(color: error ? colors.onErrorContainer : null),
            ),
            if (action != null) ...[const SizedBox(height: 8), action!],
          ],
        ),
      ),
    );
  }
}

Future<bool> confirmRecipeChange(
  BuildContext context,
  WidgetRef ref, {
  required String permission,
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Giữ bản nháp',
}) async =>
    await showRecipeDialog<bool>(
      context,
      ref,
      permission: permission,
      child: Builder(
        builder: (dialogContext) => AlertDialog(
          scrollable: true,
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(cancelLabel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(confirmLabel),
            ),
          ],
        ),
      ),
    ) ??
    false;
