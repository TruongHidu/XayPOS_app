import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/providers.dart';
import '../../../../core/auth/access_policy.dart';
import '../../domain/entities/item_type.dart';
import 'ingredient_dialogs.dart';
import 'ingredient_form.dart';
import 'menu_dialogs.dart';
import 'menu_item_form.dart';

Future<void> showCatalogCreateDialog(
  BuildContext context,
  WidgetRef ref, {
  ItemType defaultType = ItemType.menuItem,
}) async {
  final session = ref.read(authControllerProvider).state.session;
  final canMenuItem = AccessPolicy.canMenu(session, 'MENU_CREATE');
  final canIngredient = AccessPolicy.canIngredient(
    session,
    'INGREDIENT_CREATE',
  );

  if (!canMenuItem && !canIngredient) return;

  if (canMenuItem && !canIngredient) {
    await showMenuDialog(
      context,
      ref,
      permission: 'MENU_CREATE',
      child: const MenuItemForm(),
    );
    return;
  }

  if (!canMenuItem && canIngredient) {
    await showIngredientDialog(
      context,
      ref,
      permission: 'INGREDIENT_CREATE',
      child: const IngredientForm(),
    );
    return;
  }

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => CatalogItemCreateDialog(initialType: defaultType),
  );
}

class CatalogItemCreateDialog extends ConsumerStatefulWidget {
  const CatalogItemCreateDialog({
    super.key,
    this.initialType = ItemType.menuItem,
  });

  final ItemType initialType;

  @override
  ConsumerState<CatalogItemCreateDialog> createState() =>
      _CatalogItemCreateDialogState();
}

class _CatalogItemCreateDialogState
    extends ConsumerState<CatalogItemCreateDialog> {
  late ItemType _selectedType;
  bool _busy = false;
  Object? _initialScope;
  final _visited = <ItemType>{};

  @override
  void initState() {
    super.initState();
    _selectedType = widget.initialType;
    _visited.add(_selectedType);
    final session = ref.read(authControllerProvider).state.session;
    _initialScope = AccessPolicy.menuScope(session);
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authControllerProvider).state.session;
    final currentScope = AccessPolicy.menuScope(session);
    final canMenuItem = AccessPolicy.canMenu(session, 'MENU_CREATE');
    final canIngredient = AccessPolicy.canIngredient(
      session,
      'INGREDIENT_CREATE',
    );

    if (currentScope != _initialScope || (!canMenuItem && !canIngredient)) {
      final route = ModalRoute.of(context);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted && route != null && route.isActive) {
          Navigator.of(context).removeRoute(route);
        }
      });
      return const SizedBox.shrink();
    }

    if (_selectedType == ItemType.menuItem && !canMenuItem && canIngredient) {
      _selectedType = ItemType.ingredient;
    } else if (_selectedType == ItemType.ingredient &&
        !canIngredient &&
        canMenuItem) {
      _selectedType = ItemType.menuItem;
    }

    _visited.add(_selectedType);
    final hasBoth = canMenuItem && canIngredient;

    final typeSelector = hasBoth
        ? Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final type in ItemType.values)
                ChoiceChip(
                  key: ValueKey('create-type-${type.code}'),
                  label: Text(type.label),
                  selected: _selectedType == type,
                  onSelected: _busy
                      ? null
                      : (_) {
                          FocusScope.of(context).unfocus();
                          setState(() {
                            _selectedType = type;
                            _visited.add(type);
                          });
                        },
                ),
            ],
          )
        : null;

    return Stack(
      alignment: Alignment.center,
      children: [
        if (canMenuItem && _visited.contains(ItemType.menuItem))
          Offstage(
            key: const ValueKey(ItemType.menuItem),
            offstage: _selectedType != ItemType.menuItem,
            child: ExcludeFocus(
              excluding: _selectedType != ItemType.menuItem,
              child: TickerMode(
                enabled: _selectedType == ItemType.menuItem,
                child: MenuItemForm(
                  typeSelector: typeSelector,
                  onBusyChanged: (b) => setState(() => _busy = b),
                ),
              ),
            ),
          ),
        if (canIngredient && _visited.contains(ItemType.ingredient))
          Offstage(
            key: const ValueKey(ItemType.ingredient),
            offstage: _selectedType != ItemType.ingredient,
            child: ExcludeFocus(
              excluding: _selectedType != ItemType.ingredient,
              child: TickerMode(
                enabled: _selectedType == ItemType.ingredient,
                child: IngredientForm(
                  typeSelector: typeSelector,
                  onBusyChanged: (b) => setState(() => _busy = b),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
