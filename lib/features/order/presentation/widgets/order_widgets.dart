import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/providers.dart';
import '../../../../app/router/app_routes.dart';
import '../../../../core/auth/access_policy.dart';
import '../../../../core/auth/app_session.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/formatters/money_format.dart';
import '../../../../core/ui/widgets/responsive_dialog.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/values/ingredient_quantity.dart';
import '../../domain/entities/order_quantity.dart';
import '../../domain/policies/stock_shortage_summary.dart';
import '../controllers/order_draft_controller.dart';
import 'stock_shortage_dialog.dart';
import '../../../../app/theme/app_colors.dart';

abstract final class OrderPalette {
  static const clear = Colors.transparent;
  static const primary = AppTheme.primaryColor;
  static const grey = AppColors.grey300;
}

/// What a stock refusal needs from the cart to name each refused line.
List<ShortageCartLine> shortageCartOf(List<OrderDraftLine> lines) => [
  for (final line in lines)
    ShortageCartLine(
      menuItemId: line.item.id,
      quantity: IngredientQuantity.fromScaled(
        BigInt.from(line.quantity.milliUnits),
      ),
      note: line.note,
    ),
];

String orderMoney(BigInt minor, {String? currency}) =>
    formatMinorUnits(minor, currency: currency);

class OrderFailurePanel extends StatelessWidget {
  const OrderFailurePanel({
    super.key,
    required this.failure,
    this.retry,
    this.label = 'Tải lại để xác minh',
    this.cart = const [],
    this.onEditCart,
  });
  final Failure? failure;
  final VoidCallback? retry;
  final String label;

  /// The cart that was sent, so a stock refusal can name each line's note.
  final List<ShortageCartLine> cart;

  /// Shown in the stock refusal as a shortcut back to the cart. Cart screens
  /// pass it and get the refusal as the dialog alone: a banner above the menu
  /// only takes room, and sending again brings the dialog back.
  final VoidCallback? onEditCart;
  @override
  Widget build(BuildContext context) => failure == null
      ? const SizedBox.shrink()
      : failure!.stockShortage != null && onEditCart != null
      ? _StockShortageButton(
          failure: failure!,
          shortage: failure!.stockShortage!,
          cart: cart,
          onEditCart: onEditCart,
          visible: false,
        )
      : Padding(
          padding: const EdgeInsets.all(8),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(failure!.message),
                if (failure!.fieldErrors.isNotEmpty)
                  Text(failure!.fieldErrors.values.join('\n')),
                if (failure!.stockShortage case final shortage?)
                  _StockShortageButton(
                    failure: failure!,
                    shortage: shortage,
                    cart: cart,
                    onEditCart: onEditCart,
                  ),
                if (retry != null)
                  TextButton(onPressed: retry, child: Text(label)),
                if (failure!.code == 'INVENTORY_DEFAULT_WAREHOUSE_REQUIRED')
                  const _WarehouseSettingsLink(),
              ],
            ),
          ),
        );
}

/// Opens the shortage list as soon as the refusal shows up, then stays as a
/// button so it can be reopened while the cart is being fixed.
class _StockShortageButton extends StatefulWidget {
  const _StockShortageButton({
    required this.failure,
    required this.shortage,
    required this.cart,
    required this.onEditCart,
    this.visible = true,
  });
  final Failure failure;
  final StockShortage shortage;
  final List<ShortageCartLine> cart;
  final VoidCallback? onEditCart;

  /// False only pops the dialog up, leaving no button behind.
  final bool visible;
  @override
  State<_StockShortageButton> createState() => _StockShortageButtonState();
}

class _StockShortageButtonState extends State<_StockShortageButton> {
  /// Per refusal, not per panel: the same failure may sit in more than one
  /// panel (screen and dialog) and must pop up only once.
  static final _opened = Expando<bool>();

  @override
  void initState() {
    super.initState();
    _openOnce();
  }

  @override
  void didUpdateWidget(_StockShortageButton old) {
    super.didUpdateWidget(old);
    if (!identical(old.failure, widget.failure)) _openOnce();
  }

  void _openOnce() {
    if (_opened[widget.failure] == true) return;
    _opened[widget.failure] = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ModalRoute.of(context)?.isCurrent != false) {
        _open();
      }
    });
  }

  void _open() => showStockShortageDialog(
    context,
    widget.shortage,
    cart: widget.cart,
    onEditCart: widget.onEditCart,
  );

  @override
  Widget build(BuildContext context) {
    if (!widget.visible) return const SizedBox.shrink();
    final dishes = {for (final l in widget.shortage.lines) l.menuItemId};
    return TextButton.icon(
      onPressed: _open,
      icon: const Icon(Icons.list_alt),
      label: Text('Xem ${dishes.length} món thiếu nguyên liệu'),
    );
  }
}

/// Pushed over the order screen so the cart survives; dialogs keep their draft
/// by not offering the link.
class _WarehouseSettingsLink extends ConsumerWidget {
  const _WarehouseSettingsLink();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = GoRouter.maybeOf(context);
    final allowed = AccessPolicy.canInventory(
      ref.watch(authControllerProvider).state.session,
      'WAREHOUSE_UPDATE',
    );
    if (!allowed || router == null || ModalRoute.of(context) is PopupRoute) {
      return const SizedBox.shrink();
    }
    return TextButton(
      onPressed: () => router.push(AppRoutes.inventoryWarehouses),
      child: const Text('Mở quản lý kho'),
    );
  }
}

Future<T?> showOrderDialog<T>(
  BuildContext context,
  WidgetRef ref, {
  required String permission,
  required Widget child,
}) {
  final session = ref.read(authControllerProvider).state.session;
  if (!AccessPolicy.canOrders(session, permission)) return Future.value();
  final scope = AccessPolicy.orderScope(session);
  return showDialog<T>(
    context: context,
    barrierDismissible: false,
    builder: (_) =>
        OrderScopeGuard(scope: scope, permission: permission, child: child),
  );
}

class OrderScopeGuard extends ConsumerWidget {
  const OrderScopeGuard({
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
    final AppSession? session = ref.watch(authControllerProvider).state.session;
    if (AccessPolicy.orderScope(session) != scope ||
        !AccessPolicy.canOrders(session, permission)) {
      final route = ModalRoute.of(context);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted && route?.isActive == true) {
          Navigator.of(context).removeRoute(route!);
        }
      });
      return const SizedBox.shrink();
    }
    return child;
  }
}

Future<bool> confirmOrderAction(
  BuildContext context,
  WidgetRef ref,
  String permission,
  String title,
  String message,
) async =>
    await showOrderDialog<bool>(
      context,
      ref,
      permission: permission,
      child: AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(context, rootNavigator: true).pop(false),
            child: const Text('Quay lại'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context, rootNavigator: true).pop(true),
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    ) ??
    false;

class OrderLineEditor extends StatefulWidget {
  const OrderLineEditor({super.key, required this.quantity, this.note});
  final OrderQuantity quantity;
  final String? note;
  @override
  State<OrderLineEditor> createState() => _OrderLineEditorState();
}

class _OrderLineEditorState extends State<OrderLineEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _quantity = TextEditingController(
    text: widget.quantity.toString(),
  );
  late final TextEditingController _note = TextEditingController(
    text: widget.note ?? '',
  );
  @override
  void dispose() {
    _quantity.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ResponsiveDialog(
    child: SingleChildScrollView(
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Số lượng và ghi chú',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _quantity,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Số lượng',
                border: OutlineInputBorder(),
              ),
              validator: (text) {
                try {
                  OrderQuantity.parse(text ?? '');
                  return null;
                } on FormatException catch (e) {
                  return e.message.toString();
                }
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _note,
              maxLength: 2000,
              minLines: 1,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Ghi chú món'),
            ),
            Wrap(
              alignment: WrapAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Bỏ thay đổi'),
                ),
                FilledButton(
                  onPressed: () => _form.currentState!.validate()
                      ? Navigator.of(
                          context,
                        ).pop((OrderQuantity.parse(_quantity.text), _note.text))
                      : null,
                  child: const Text('Áp dụng'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
