import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/auth/access_policy.dart';
import '../../../../core/ui/widgets/create_speed_dial_fab.dart';
import 'ingredient_dialogs.dart';
import 'ingredient_form.dart';
import 'menu_dialogs.dart';
import 'menu_group_form.dart';
import 'menu_item_form.dart';

List<SpeedDialOption> _createOptions(WidgetRef ref) {
  final session = ref.watch(authControllerProvider).state.session;
  final canMenu = AccessPolicy.canMenu(session, 'MENU_CREATE');
  final canIngredient = AccessPolicy.canIngredient(
    session,
    'INGREDIENT_CREATE',
  );
  return [
    if (canMenu) ...[
      SpeedDialOption(
        label: 'Thêm món',
        icon: Icons.restaurant_outlined,
        onSelected: (context) => showMenuDialog<void>(
          context,
          ref,
          permission: 'MENU_CREATE',
          child: const MenuItemForm(),
        ),
      ),
      SpeedDialOption(
        label: 'Thêm nhóm món',
        icon: Icons.folder_outlined,
        onSelected: (context) => showMenuDialog<void>(
          context,
          ref,
          permission: 'MENU_CREATE',
          child: const MenuGroupForm(),
        ),
      ),
    ],
    if (canIngredient)
      SpeedDialOption(
        label: 'Thêm nguyên liệu',
        icon: Icons.kitchen_outlined,
        onSelected: (context) => showIngredientDialog<void>(
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
  Widget build(BuildContext context, WidgetRef ref) =>
      CreateSpeedDialFab(options: _createOptions(ref));
}
