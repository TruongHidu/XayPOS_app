import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/providers.dart';
import '../../../../core/auth/access_policy.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/order_inputs.dart';
import '../../domain/entities/order_entities.dart';
import '../../domain/entities/order_table_workspace.dart';
import '../../domain/entities/order_quantity.dart';
import '../../domain/entities/order_submission.dart';
import '../../domain/policies/order_access_policy.dart';
import '../controllers/order_draft_controller.dart';
import '../widgets/order_exit_guard.dart';
import '../widgets/order_menu_picker.dart';
import '../widgets/order_widgets.dart';
import 'order_detail_screen.dart';
import 'order_list_screen.dart';

class OrderCreateScreen extends ConsumerWidget {
  const OrderCreateScreen({
    super.key,
    this.tableId,
    this.sessionId,
    this.takeaway = false,
  });
  final String? tableId, sessionId;
  final bool takeaway;
  @override
  Widget build(BuildContext context, WidgetRef ref) => _OrderCreateBody(
    key: ValueKey((
      AccessPolicy.orderScope(ref.watch(authControllerProvider).state.session),
      sessionId,
      tableId,
      takeaway,
    )),
    sessionId: sessionId,
    tableId: tableId,
    takeaway: takeaway,
  );
}

class _OrderCreateBody extends ConsumerStatefulWidget {
  const _OrderCreateBody({
    super.key,
    required this.sessionId,
    required this.tableId,
    required this.takeaway,
  });
  final String? tableId, sessionId;
  final bool takeaway;
  @override
  ConsumerState<_OrderCreateBody> createState() => _OrderCreateBodyState();
}

class _OrderCreateBodyState extends ConsumerState<_OrderCreateBody> {
  OrderCreationContext? _context;
  OrderDetail? _existingOrder;
  Failure? _failure;
  bool _loading = false;
  @override
  void initState() {
    super.initState();
    if (widget.takeaway && widget.sessionId == null && widget.tableId == null) {
      _context = const OrderCreationContext.takeaway();
    } else {
      Future.microtask(_resolve);
    }
  }

  Future<void> _resolve() async {
    if (!mounted) return;
    if (widget.takeaway ||
        (widget.tableId != null && widget.sessionId != null) ||
        !OrderAccessPolicy.isUuid(widget.tableId ?? widget.sessionId)) {
      setState(
        () => _failure = const Failure(
          type: FailureType.validation,
          message: 'Thông tin bàn/phiên không hợp lệ. Chỉ dùng một tham chiếu.',
        ),
      );
      return;
    }
    setState(() {
      _loading = true;
      _failure = null;
    });
    final c = ref.read(orderServiceContextProvider);
    if (widget.tableId != null) {
      final selected = await c.selectTable(widget.tableId!);
      if (!mounted || !c.current) return;
      setState(() {
        _loading = false;
        switch (selected) {
          case Success(value: ViewTableOrder(order: final order)):
            _existingOrder = order;
          case Success(value: ComposeTableOrder(context: final context)):
            _context = context;
          case Error(failure: final error):
            _failure = error;
        }
      });
      return;
    }
    final result = await c.resolveSession(widget.sessionId!);
    if (!mounted || !c.current) return;
    setState(() {
      _loading = false;
      switch (result) {
        case Success(value: final v):
          _context = v;
        case Error(failure: final f):
          _failure = f;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.takeaway) ref.watch(orderServiceContextProvider);
    if (_existingOrder != null) {
      return OrderDetailScreen(
        id: _existingOrder!.id,
        initialOrder: _existingOrder,
      );
    }
    return _context == null
        ? Column(
            children: [
              if (_loading) const LinearProgressIndicator(),
              OrderFailurePanel(failure: _failure, retry: _resolve),
              TextButton(
                onPressed: () => context.go('/app/order-create'),
                child: const Text('Chọn lại bàn'),
              ),
            ],
          )
        : OrderComposer(key: ValueKey(_context), contextInput: _context!);
  }
}

class OrderComposer extends ConsumerStatefulWidget {
  const OrderComposer({super.key, required this.contextInput});
  final OrderCreationContext contextInput;
  @override
  ConsumerState<OrderComposer> createState() => _OrderComposerState();
}

class _OrderComposerState extends ConsumerState<OrderComposer> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(),
      _phone = TextEditingController(),
      _note = TextEditingController();
  late final _guests = TextEditingController(
    text: widget.contextInput.fromTable
        ? ''
        : widget.contextInput.guestCount.toString(),
  );
  OrderDraftController? _draft;
  OrderExitGuard? _exit;
  @override
  void dispose() {
    if (identical(_exit?.draft, _draft)) _exit?.draft = null;
    for (final c in [_name, _phone, _note, _guests]) {
      c.dispose();
    }
    super.dispose();
  }

  void _fields(OrderDraftController d) => d.setFields(
    customerName: _name.text,
    customerPhone: _phone.text,
    note: _note.text,
    guestCount: int.tryParse(_guests.text),
  );
  Future<void> _submit(OrderDraftController d, OrderSubmissionMode mode) async {
    if (int.tryParse(_guests.text) == null &&
        !(widget.contextInput.fromTable && _guests.text.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Số khách phải là số nguyên.')),
      );
      return;
    }
    if (_form.currentState != null && !_form.currentState!.validate()) return;
    _fields(d);
    await d.submit(mode: mode);
  }

  Future<void> _edit(OrderDraftController d, OrderDraftLine line) async {
    final result = await showOrderDialog<(OrderQuantity, String)>(
      context,
      ref,
      permission: 'ORDER_CREATE',
      child: OrderLineEditor(quantity: line.quantity, note: line.note),
    );
    if (result != null && mounted) d.edit(line.id, result.$1, result.$2);
  }

  Future<void> _checkTable(OrderDraftController draft) async {
    final id = widget.contextInput.tableId;
    if (id == null || draft.frozen || !draft.can('ORDER_VIEW')) return;
    final workspace = ref.read(orderServiceContextProvider);
    final result = await workspace.selectTable(id);
    if (!mounted || !draft.current || !workspace.current) return;
    switch (result) {
      case Error(failure: final error):
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      case Success(value: ViewTableOrder(order: final order)):
        await showOrderDialog<void>(
          context,
          ref,
          permission: 'ORDER_VIEW',
          child: AlertDialog(
            title: const Text('Bàn đã có đơn đang phục vụ'),
            content: Text(
              '${order.summary.orderCode}\nTổng: ${orderMoney(BigInt.from(order.summary.totalAmount.minorUnits), currency: order.summary.currencyCode)}\nGiỏ đang nhập được giữ nguyên, không chuyển thành gọi thêm.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Giữ giỏ, quay lại'),
              ),
            ],
          ),
        );
      case Success(value: ComposeTableOrder(context: final latest)):
        final confirmed = await confirmOrderAction(
          context,
          ref,
          'ORDER_CREATE',
          'Dùng trạng thái bàn mới?',
          'Hiện chưa có đơn đang phục vụ. Giữ giỏ và chủ động gửi một yêu cầu mới?',
        );
        if (mounted && confirmed && draft.current) {
          draft.acknowledgeTableContext(latest);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = ref.watch(orderDraftProvider(widget.contextInput));
    d.adoptSeatingHint(widget.contextInput);
    _draft = d;
    _exit = ref.read(orderExitGuardProvider);
    _exit!.draft = d;
    if (d.result != null) {
      return OrderDetailScreen(id: d.result!.id, initialOrder: d.result);
    }
    final hasHistory =
        widget.contextInput.tableSessionId != null && d.can('ORDER_VIEW');
    return DefaultTabController(
      length: hasHistory ? 3 : 2,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              widget.contextInput.tableName ??
                  widget.contextInput.serviceType.label,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          TabBar(
            tabs: [
              const Tab(text: 'Chọn món'),
              Tab(text: 'Giỏ (${d.lines.length})'),
              if (hasHistory) const Tab(text: 'Lịch sử trong phiên'),
            ],
          ),
          if (d.busy) const LinearProgressIndicator(),
          OrderFailurePanel(
            failure: d.failure,
            retry: d.canRetry ? d.retry : null,
            label: 'Kiểm tra bằng yêu cầu tạo ban đầu',
          ),
          if (d.needsTableReview && d.can('ORDER_VIEW'))
            TextButton(
              onPressed: d.busy ? null : () => _checkTable(d),
              child: const Text('Kiểm tra đơn của bàn'),
            ),
          if (d.keyConflict)
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text(
                'Key xung đột. Không tạo key mới; cần đối chiếu với người quản lý.',
              ),
            ),
          if (d.uncertain)
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text(
                'Chưa xác định đơn đã được tạo hay chưa. Giỏ đã khóa; thử lại giữ nguyên yêu cầu và key.',
              ),
            ),
          Expanded(
            child: TabBarView(
              children: [
                OrderMenuPicker(
                  permission: 'ORDER_CREATE',
                  onSelect: d.add,
                  enabled: !d.frozen && d.canPick,
                ),
                Form(
                  key: _form,
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      if (d.lines.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text('Chưa chọn món.'),
                        ),
                      for (final line in d.lines)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  line.item.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  '${line.quantity} ${line.item.baseUnit} · ${orderMoney(line.previewMinor)}',
                                ),
                                if (line.note?.isNotEmpty == true)
                                  Text(line.note!),
                                Wrap(
                                  children: [
                                    TextButton(
                                      onPressed: d.frozen
                                          ? null
                                          : () => _edit(d, line),
                                      child: const Text('Số lượng / ghi chú'),
                                    ),
                                    TextButton(
                                      onPressed: d.frozen
                                          ? null
                                          : () => d.remove(line.id),
                                      child: const Text('Bỏ món'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      TextFormField(
                        controller: _name,
                        readOnly: d.frozen,
                        maxLength: 100,
                        onChanged: (_) => _fields(d),
                        decoration: const InputDecoration(
                          labelText: 'Tên khách (không bắt buộc)',
                        ),
                      ),
                      TextFormField(
                        controller: _phone,
                        readOnly: d.frozen,
                        maxLength: 30,
                        onChanged: (_) => _fields(d),
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Số điện thoại (không bắt buộc)',
                        ),
                      ),
                      TextFormField(
                        controller: _guests,
                        readOnly: d.frozen,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => _fields(d),
                        decoration: InputDecoration(
                          labelText: widget.contextInput.fromTable
                              ? 'Số khách (không bắt buộc)'
                              : 'Số khách',
                          hintText: widget.contextInput.guestCount.toString(),
                        ),
                        validator: (v) {
                          if (widget.contextInput.fromTable &&
                              (v?.trim().isEmpty ?? true)) {
                            return null;
                          }
                          final n = int.tryParse(v ?? '');
                          return n == null || n < 1 || n > 32767
                              ? 'Nhập số từ 1 đến 32767'
                              : null;
                        },
                      ),
                      TextFormField(
                        controller: _note,
                        readOnly: d.frozen,
                        maxLength: 2000,
                        maxLines: 3,
                        onChanged: (_) => _fields(d),
                        decoration: const InputDecoration(
                          labelText: 'Ghi chú đơn',
                        ),
                      ),
                    ],
                  ),
                ),
                if (hasHistory)
                  OrderListScreen(
                    sessionId: widget.contextInput.tableSessionId,
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Tổng dự kiến: ${orderMoney(d.previewMinor)}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Text('Giá và tổng chính thức do backend xác định.'),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed:
                      d.busy ||
                          d.uncertain ||
                          !d.canPick ||
                          !d.canSubmit ||
                          d.lines.isEmpty
                      ? null
                      : () => _submit(d, OrderSubmissionMode.submit),
                  child: Text(d.busy ? 'Đang xử lý...' : 'Gửi đơn'),
                ),
                if (!d.canSubmit && d.canCreate)
                  Text(
                    widget.contextInput.fromTable
                        ? 'Cần quyền gửi đơn và TABLE_OPEN nếu phải mở phiên mới.'
                        : 'Cần ORDER_UPDATE để gửi đơn. Bạn có thể tạo nháp.',
                  ),
                if (d.canDraft)
                  TextButton(
                    onPressed:
                        d.busy || d.uncertain || !d.canPick || d.lines.isEmpty
                        ? null
                        : () => _submit(d, OrderSubmissionMode.draft),
                    child: const Text('Tạo nháp'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
