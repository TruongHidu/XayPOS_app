import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/providers.dart';
import '../../../../core/auth/access_policy.dart';
import '../../../../core/auth/app_session.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/ui/widgets/responsive_dialog.dart';
import '../../domain/entities/order_quantity.dart';

abstract final class OrderPalette {
  static const white = Color(0x000063E2);
  static const orange = Color(0xFF0063E2);
  static const grey = Color(0xFFD0D0D0);
}

String orderMoney(BigInt minor, {String? currency}) {
  final whole = (minor ~/ BigInt.from(100)).toString();
  final grouped = whole.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => '.',
  );
  final fraction = (minor % BigInt.from(100)).toString().padLeft(2, '0');
  return '$grouped${fraction == '00' ? '' : ',$fraction'}${currency == null ? '' : ' $currency'}';
}

class OrderFailurePanel extends StatelessWidget {
  const OrderFailurePanel({
    super.key,
    required this.failure,
    this.retry,
    this.label = 'Tải lại để xác minh',
  });
  final Failure? failure;
  final VoidCallback? retry;
  final String label;
  @override
  Widget build(BuildContext context) => failure == null
      ? const SizedBox.shrink()
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
                if (retry != null)
                  TextButton(onPressed: retry, child: Text(label)),
              ],
            ),
          ),
        );
}

class OrderPaging extends StatelessWidget {
  const OrderPaging({
    super.key,
    required this.page,
    required this.totalPages,
    required this.loading,
    required this.onPage,
  });
  final int page, totalPages;
  final bool loading;
  final void Function(int) onPage;
  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.center,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      IconButton(
        tooltip: 'Trang trước',
        onPressed: loading || page == 0 ? null : () => onPage(page - 1),
        icon: const Icon(Icons.chevron_left),
      ),
      Text('Trang ${totalPages == 0 ? 0 : page + 1}/$totalPages'),
      IconButton(
        tooltip: 'Trang sau',
        onPressed: loading || page + 1 >= totalPages
            ? null
            : () => onPage(page + 1),
        icon: const Icon(Icons.chevron_right),
      ),
    ],
  );
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
