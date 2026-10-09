import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/result/result.dart';
import '../../../../core/ui/widgets/responsive_dialog.dart';
import '../../domain/entities/order_entities.dart';
import '../../domain/entities/order_inputs.dart';
import '../../domain/entities/order_quantity.dart';
import '../../domain/policies/order_access_policy.dart';
import '../../domain/policies/order_validation.dart';
import '../providers/order_providers.dart';
import 'order_widgets.dart';

enum OrderFormAction { metadata, line, cancel, cancelLine, confirm }

class OrderMutationForm extends ConsumerStatefulWidget {
  const OrderMutationForm({
    super.key,
    required this.order,
    required this.action,
    this.line,
  });
  final OrderDetail order;
  final OrderFormAction action;
  final OrderLine? line;
  @override
  ConsumerState<OrderMutationForm> createState() => _OrderMutationFormState();
}

class _OrderMutationFormState extends ConsumerState<OrderMutationForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(
    text: widget.order.summary.customerName ?? '',
  );
  late final _phone = TextEditingController(
    text: widget.order.customerPhone ?? '',
  );
  late final _guests = TextEditingController(
    text: widget.order.summary.guestCount.toString(),
  );
  late final _note = TextEditingController(
    text: (widget.line?.note ?? widget.order.note) ?? '',
  );
  late final _quantity = TextEditingController(
    text: widget.line?.quantity.toString() ?? '1',
  );
  final _reason = TextEditingController();
  bool _busy = false;
  String? _error;
  bool _touched = false;
  String get permission => widget.action == OrderFormAction.cancel
      ? 'ORDER_CANCEL'
      : widget.action == OrderFormAction.cancelLine
      ? OrderAccessPolicy.lineCancelPermission(widget.order)
      : 'ORDER_UPDATE';
  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    final controller = ref.read(orderDetailProvider(widget.order.id));
    setState(() => _busy = true);
    final version = widget.order.version;
    final Future<Result<OrderDetail>> request;
    switch (widget.action) {
      case OrderFormAction.metadata:
        request = controller.update(
          UpdateOrderInput(
            expectedVersion: version,
            customerName:
                _name.text == (widget.order.summary.customerName ?? '')
                ? null
                : _name.text,
            customerPhone: _phone.text == (widget.order.customerPhone ?? '')
                ? null
                : _phone.text,
            guestCount:
                _guests.text == widget.order.summary.guestCount.toString()
                ? null
                : int.tryParse(_guests.text),
            note: _note.text == (widget.order.note ?? '') ? null : _note.text,
          ),
        );
      case OrderFormAction.line:
        final quantity = OrderQuantity.parse(_quantity.text);
        request = controller.editLine(
          widget.line!.id,
          UpdateOrderLineInput(
            expectedVersion: version,
            quantity: quantity == widget.line!.quantity ? null : quantity,
            note: _note.text == (widget.line!.note ?? '') ? null : _note.text,
          ),
        );
      case OrderFormAction.cancel:
        request = controller.cancel(version, _reason.text);
      case OrderFormAction.cancelLine:
        request = controller.cancelItem(widget.line!.id, version, _reason.text);
      case OrderFormAction.confirm:
        request = controller.confirm(version);
    }
    final result = await request;
    if (!mounted || !controller.current) return;
    setState(() => _busy = false);
    if (result is Success<OrderDetail>) {
      Navigator.of(context).pop();
    } else {
      final failure = (result as Error<OrderDetail>).failure;
      setState(
        () => _error = [
          failure.message,
          ...failure.fieldErrors.values,
        ].join('\n'),
      );
    }
  }

  Future<void> _close() async {
    if (_busy) return;
    if (_touched &&
        !await confirmOrderAction(
          context,
          ref,
          permission,
          'Bỏ bản đang nhập?',
          'Các thay đổi trong hộp thoại chưa được lưu sẽ bị bỏ.',
        )) {
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _guests, _note, _quantity, _reason]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(orderDetailProvider(widget.order.id));
    final title = switch (widget.action) {
      OrderFormAction.metadata => 'Thông tin đơn',
      OrderFormAction.line => 'Sửa dòng món',
      OrderFormAction.cancel => 'Hủy đơn',
      OrderFormAction.cancelLine => 'Hủy dòng món',
      OrderFormAction.confirm => 'Xác nhận đơn',
    };
    Widget field(
      TextEditingController controller,
      String label, {
      int? max,
      int lines = 1,
      String? Function(String?)? validator,
      TextInputType? keyboard,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        maxLength: max,
        minLines: 1,
        maxLines: lines,
        readOnly: _busy,
        keyboardType: keyboard,
        onChanged: (_) => _touched = true,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        validator:
            validator ??
            (v) => max == null ? null : OrderValidation.text(v, max),
      ),
    );
    return PopScope(
      canPop: !_busy && !_touched,
      child: ResponsiveDialog(
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 16),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (c.requiresVerification)
                  const Text(
                    'Kết quả đã thay đổi hoặc chưa xác định. Bản đang nhập được giữ. Đóng hộp thoại rồi tải lại đơn để đối chiếu; không tự gửi lại.',
                  ),
                if (widget.action == OrderFormAction.metadata) ...[
                  field(_name, 'Tên khách', max: 100),
                  field(
                    _phone,
                    'Số điện thoại',
                    max: 30,
                    keyboard: TextInputType.phone,
                  ),
                  field(
                    _guests,
                    'Số khách',
                    keyboard: TextInputType.number,
                    validator: (v) {
                      final n = int.tryParse(v ?? '');
                      return n == null || n < 1 || n > 32767
                          ? 'Nhập số từ 1 đến 32767'
                          : null;
                    },
                  ),
                  field(_note, 'Ghi chú đơn', max: 2000, lines: 3),
                ],
                if (widget.action == OrderFormAction.line) ...[
                  field(
                    _quantity,
                    'Số lượng',
                    keyboard: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: (v) {
                      try {
                        OrderQuantity.parse(v ?? '');
                        return null;
                      } on FormatException catch (e) {
                        return e.message.toString();
                      }
                    },
                  ),
                  field(_note, 'Ghi chú món', max: 2000, lines: 3),
                ],
                if (const {
                  OrderFormAction.cancel,
                  OrderFormAction.cancelLine,
                }.contains(widget.action))
                  field(
                    _reason,
                    'Lý do hủy',
                    max: 1000,
                    lines: 3,
                    validator: (v) =>
                        OrderValidation.text(v, 1000, required: true),
                  ),
                if (widget.action == OrderFormAction.confirm)
                  const Text(
                    'Xác nhận khóa sửa thông tin và món đã lưu. Bạn vẫn có thể gọi thêm vào đơn này; hủy món sau xác nhận cần ORDER_CANCEL. Chưa gửi bếp hoặc thanh toán.',
                  ),
                const SizedBox(height: 12),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton(
                      onPressed: _busy ? null : _close,
                      child: const Text('Đóng'),
                    ),
                    FilledButton(
                      onPressed: _busy || c.busy || c.requiresVerification
                          ? null
                          : _save,
                      child: Text(_busy ? 'Đang xử lý...' : 'Xác nhận'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
