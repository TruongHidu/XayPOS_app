import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/auth/access_policy.dart';
import 'ingredient_dialogs.dart';
import 'ingredient_form.dart';
import 'menu_dialogs.dart';
import 'menu_group_form.dart';
import 'menu_item_form.dart';

typedef _CreateOption = ({
  String label,
  IconData icon,
  Future<void> Function(BuildContext context, WidgetRef ref) open,
});

List<_CreateOption> _createOptions(WidgetRef ref) {
  final session = ref.watch(authControllerProvider).state.session;
  final canMenu = AccessPolicy.canMenu(session, 'MENU_CREATE');
  final canIngredient = AccessPolicy.canIngredient(
    session,
    'INGREDIENT_CREATE',
  );
  return [
    if (canMenu) ...[
      (
        label: 'Thêm món',
        icon: Icons.restaurant_outlined,
        open: (context, ref) => showMenuDialog<void>(
          context,
          ref,
          permission: 'MENU_CREATE',
          child: const MenuItemForm(),
        ),
      ),
      (
        label: 'Thêm nhóm món',
        icon: Icons.folder_outlined,
        open: (context, ref) => showMenuDialog<void>(
          context,
          ref,
          permission: 'MENU_CREATE',
          child: const MenuGroupForm(),
        ),
      ),
    ],
    if (canIngredient)
      (
        label: 'Thêm nguyên liệu',
        icon: Icons.kitchen_outlined,
        open: (context, ref) => showIngredientDialog<void>(
          context,
          ref,
          permission: 'INGREDIENT_CREATE',
          child: const IngredientForm(),
        ),
      ),
  ];
}

/// Whether the current session may create anything from the menu workspace.
bool canCreateInMenuWorkspace(WidgetRef ref) => _createOptions(ref).isNotEmpty;

/// Floating add button; opens a speed-dial overlay to pick what to create,
/// then the matching form. A single allowed type opens its form directly.
class MenuCreateFab extends ConsumerWidget {
  const MenuCreateFab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final options = _createOptions(ref);
    if (options.isEmpty) return const SizedBox.shrink();

    return FloatingActionButton(
      tooltip: 'Thêm mới',
      onPressed: () async {
        if (options.length == 1) {
          await options.single.open(context, ref);
          return;
        }
        final chosen = await _showOptions(context, options);
        if (chosen != null && context.mounted) {
          await chosen.open(context, ref);
        }
      },
      child: const Icon(Icons.add),
    );
  }

  Future<_CreateOption?> _showOptions(
    BuildContext context,
    List<_CreateOption> options,
  ) {
    final box = context.findRenderObject()! as RenderBox;
    final fabRect = box.localToGlobal(Offset.zero) & box.size;

    return showGeneralDialog<_CreateOption>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Đóng',
      barrierColor: Colors.black38,
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (dialogContext, _, _) {
        final screen = MediaQuery.sizeOf(dialogContext);
        return Stack(
          children: [
            Positioned(
              left: 16,
              right: screen.width - fabRect.right,
              bottom: screen.height - fabRect.top + 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final option in options)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: _OptionRow(
                        option: option,
                        width: fabRect.width,
                        onTap: () => Navigator.of(dialogContext).pop(option),
                      ),
                    ),
                ],
              ),
            ),
            Positioned.fromRect(
              rect: fabRect,
              child: FloatingActionButton(
                heroTag: null,
                tooltip: 'Đóng',
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Icon(Icons.close),
              ),
            ),
          ],
        );
      },
      transitionBuilder: (_, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0, 0.03),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.option,
    required this.width,
    required this.onTap,
  });

  final _CreateOption option;
  final double width;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Material(
            elevation: 3,
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                child: Text(option.label, style: theme.textTheme.labelLarge),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Centre the small button over the main FAB.
        SizedBox(
          width: width,
          child: Center(
            child: FloatingActionButton.small(
              heroTag: null,
              tooltip: option.label,
              onPressed: onTap,
              child: Icon(option.icon),
            ),
          ),
        ),
      ],
    );
  }
}
