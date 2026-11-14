import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/auth/access_policy.dart';
import '../../../../core/formatters/money_format.dart';
import '../../../../core/ui/widgets/app_network_image.dart';
import '../../../menu/domain/entities/menu_item.dart';
import '../../domain/entities/order_quantity.dart';
import '../../domain/policies/order_line_policy.dart';
import '../controllers/order_cart_editor.dart';
import '../controllers/order_draft_controller.dart' show OrderDraftLine;
import 'order_cart_layout.dart';
import 'order_widgets.dart';

/// Opens the dish's own sheet over the menu: what it is, the lines of it
/// already in the cart, and a composer for a new portion. The menu stays on
/// screen underneath; only the Giỏ tab or "Xem đơn" goes to the cart.
Future<void> showMenuItemSheet(
  BuildContext context,
  WidgetRef ref, {
  required MenuItem item,
  required OrderCartEditor cart,
  required String permission,
  String? currencyCode,
}) {
  final session = ref.read(authControllerProvider).state.session;
  // Same source as the menu card's "Sắp hết" badge.
  final lowStock =
      item.trackInventory &&
      (ref.read(lowStockMenuItemIdsProvider).value?.contains(item.id) ?? false);
  if (!AccessPolicy.canOrders(session, permission)) return Future.value();
  final scope = AccessPolicy.orderScope(session);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) => OrderScopeGuard(
      scope: scope,
      permission: permission,
      child: MenuItemSheet(
        item: item,
        cart: cart,
        currencyCode: currencyCode,
        lowStock: lowStock,
      ),
    ),
  );
}

class MenuItemSheet extends StatefulWidget {
  const MenuItemSheet({
    super.key,
    required this.item,
    required this.cart,
    this.currencyCode,
    this.lowStock = false,
  });

  final MenuItem item;
  final OrderCartEditor cart;
  final String? currencyCode;
  final bool lowStock;

  @override
  State<MenuItemSheet> createState() => _MenuItemSheetState();
}

class _MenuItemSheetState extends State<MenuItemSheet> with OrderCartUndo {
  final _note = TextEditingController();
  OrderQuantity _quantity = OrderQuantity.one;

  /// Set when the cart refused the last add, to show its reason here.
  bool _refused = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  String _money(BigInt minor) =>
      orderMoney(minor, currency: widget.currencyCode ?? defaultCurrencySymbol);

  void _add() {
    final added = widget.cart.addLine(widget.item, _quantity, note: _note.text);
    if (!added) {
      setState(() => _refused = true);
      return;
    }
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop();
  }

  void _step(OrderDraftLine line, int delta) {
    final next = line.quantity.milliUnits + delta * 1000;
    if (next <= 0) {
      final index = widget.cart.lines.indexWhere((l) => l.id == line.id);
      widget.cart.remove(line.id);
      if (!widget.cart.lines.any((l) => l.id == line.id)) {
        rememberRemoved(line, index);
      }
      return;
    }
    HapticFeedback.selectionClick();
    widget.cart.edit(line.id, OrderQuantity.fromMilli(next), line.note);
  }

  void _undo() {
    final removed = takeRemoved();
    if (removed != null) widget.cart.restore(removed.line, removed.index);
  }

  /// Where chosen toppings will go: each choice becomes part of the line's
  /// OrderLineConfiguration, so different toppings make different lines.
  List<Widget> _options() => const [];

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.cart,
    builder: (context, _) {
      final item = widget.item;
      final cart = widget.cart;
      final orderable = OrderLinePolicy.orderable(item);
      final canChange = cart.canChangeCart && orderable;
      final mine = [
        for (final line in cart.lines)
          if (line.item.id == item.id) line,
      ];
      final removed = removedLine;
      final showUndo =
          removed != null && removed.line.item.id == item.id && canChange;
      final total = OrderDraftLine('preview', item, _quantity, null);
      final theme = Theme.of(context);
      return Padding(
        // Keeps the note field above the keyboard.
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          key: const ValueKey('menu-item-sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Header(
                      item: item,
                      price: _money(BigInt.from(item.salePrice.minorUnits)),
                      lowStock: widget.lowStock,
                    ),
                    if (item.description?.trim().isNotEmpty == true) ...[
                      const SizedBox(height: 12),
                      Text(
                        item.description!.trim(),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppColors.grey700,
                        ),
                      ),
                    ],
                    if (mine.isNotEmpty || showUndo) ...[
                      const SizedBox(height: 20),
                      const _SectionLabel('Đang có trong giỏ'),
                      const SizedBox(height: 8),
                      for (final line in mine)
                        _CartLineRow(
                          key: ValueKey('menu-item-sheet-line-${line.id}'),
                          line: line,
                          price: _money(line.previewMinor),
                          enabled: canChange,
                          onMinus: () => _step(line, -1),
                          onPlus: () => _step(line, 1),
                        ),
                      if (showUndo)
                        OrderRemovedLineTile(
                          name: removed.line.item.name,
                          onUndo: _undo,
                        ),
                    ],
                    const SizedBox(height: 20),
                    _SectionLabel(mine.isEmpty ? 'Số lượng' : 'Thêm phần mới'),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _Stepper(
                          keyPrefix: 'menu-item-sheet-quantity',
                          value: _quantity,
                          unit: item.baseUnit,
                          onMinus:
                              canChange &&
                                  _quantity.milliUnits >
                                      OrderQuantity.one.milliUnits
                              ? () => setState(
                                  () => _quantity -= OrderQuantity.one,
                                )
                              : null,
                          onPlus: canChange
                              ? () => setState(
                                  () => _quantity += OrderQuantity.one,
                                )
                              : null,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      key: const ValueKey('menu-item-sheet-note'),
                      controller: _note,
                      enabled: canChange,
                      maxLength: OrderLinePolicy.maxNoteLength,
                      minLines: 1,
                      maxLines: 3,
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        labelText: 'Ghi chú món (không bắt buộc)',
                        hintText: 'Ví dụ: ít cay, không hành',
                        counterText: '',
                        prefixIcon: const Icon(Icons.edit_note),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    ..._options(),
                    if (_refused && cart.failure != null)
                      OrderFailurePanel(failure: cart.failure),
                    if (!orderable)
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: Text(
                          'Món này hiện chưa bán được nên chưa thêm vào giỏ.',
                          style: TextStyle(color: AppColors.danger),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1, color: AppColors.grey200),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: FilledButton.icon(
                key: const ValueKey('menu-item-sheet-add'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                onPressed: canChange ? _add : null,
                icon: const Icon(Icons.add_shopping_cart_rounded),
                label: Text('Thêm vào giỏ · ${_money(total.previewMinor)}'),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _Header extends StatelessWidget {
  const _Header({
    required this.item,
    required this.price,
    required this.lowStock,
  });
  final MenuItem item;
  final String price;
  final bool lowStock;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final orderable = OrderLinePolicy.orderable(item);
    final outOfStock = item.availabilityStatus == AvailabilityStatus.outOfStock;
    final (label, color, soft) = !orderable
        ? (
            outOfStock
                ? 'Hết hàng'
                : !item.active
                ? 'Ngừng bán'
                : 'Chưa thể bán',
            AppColors.danger,
            AppColors.dangerSoft,
          )
        : lowStock
        ? ('Sắp hết', AppColors.warning, AppColors.warningSoft)
        : ('Còn món', AppColors.success, AppColors.successSoft);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SizedBox.square(
            dimension: 88,
            child: AppNetworkImage(
              url: item.imageUrl,
              placeholder: Container(
                color: AppColors.primarySoft,
                alignment: Alignment.center,
                child: const Icon(
                  Icons.restaurant,
                  color: AppColors.primary,
                  size: 32,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.name,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text.rich(
                TextSpan(
                  text: price,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w800,
                  ),
                  children: [
                    if (item.baseUnit.isNotEmpty)
                      TextSpan(
                        text: ' / ${item.baseUnit}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppColors.grey600,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: soft,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                  ),
                  if (item.group != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.grey100,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        item.group!.name,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.grey700,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context).textTheme.titleSmall?.copyWith(
      color: AppColors.grey700,
      fontWeight: FontWeight.w600,
    ),
  );
}

/// A line of this dish already in the cart, adjustable in place.
class _CartLineRow extends StatelessWidget {
  const _CartLineRow({
    super.key,
    required this.line,
    required this.price,
    required this.enabled,
    required this.onMinus,
    required this.onPlus,
  });
  final OrderDraftLine line;
  final String price;
  final bool enabled;
  final VoidCallback onMinus, onPlus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: AppColors.grey50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.grey200),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.note ?? 'Không ghi chú',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: line.note == null
                        ? AppColors.grey600
                        : AppColors.grey900,
                  ),
                ),
                Text(
                  price,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.grey600,
                  ),
                ),
              ],
            ),
          ),
          _Stepper(
            keyPrefix: 'menu-item-sheet-line-${line.id}',
            value: line.quantity,
            unit: null,
            onMinus: enabled ? onMinus : null,
            onPlus: enabled ? onPlus : null,
          ),
        ],
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.keyPrefix,
    required this.value,
    required this.unit,
    required this.onMinus,
    required this.onPlus,
  });
  final String keyPrefix;
  final OrderQuantity value;
  final String? unit;
  final VoidCallback? onMinus, onPlus;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton.outlined(
        key: ValueKey('$keyPrefix-minus'),
        tooltip: 'Bớt',
        onPressed: onMinus,
        icon: const Icon(Icons.remove),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text(
          unit == null || unit!.isEmpty ? '$value' : '$value $unit',
          key: ValueKey('$keyPrefix-value'),
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      IconButton.filled(
        key: ValueKey('$keyPrefix-plus'),
        tooltip: 'Thêm',
        onPressed: onPlus,
        icon: const Icon(Icons.add),
      ),
    ],
  );
}
