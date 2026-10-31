import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/providers.dart';
import '../../../../core/auth/access_policy.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../../menu/domain/entities/menu_item.dart';
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
import '../widgets/takeaway_submitted_view.dart';
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
        isOrderCreateFlow: true,
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

class _OrderComposerState extends ConsumerState<OrderComposer>
    with SingleTickerProviderStateMixin {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(),
      _phone = TextEditingController(),
      _note = TextEditingController();
  late final _guests = TextEditingController(
    text: widget.contextInput.fromTable
        ? ''
        : widget.contextInput.guestCount.toString(),
  );
  late final int _tabCount = (widget.contextInput.tableSessionId != null)
      ? 3
      : 2;
  late final TabController _tabController = TabController(
    length: _tabCount,
    vsync: this,
  );

  OrderDraftController? _draft;
  OrderExitGuard? _exit;

  /// Takeaway is a quick counter sale: no guest count, customer details on
  /// the menu tab, and drafts tucked into the overflow menu.
  bool get _takeaway => widget.contextInput.serviceType == ServiceType.takeaway;
  bool _moreInfo = false;

  void _startNew() {
    for (final c in [_name, _phone, _note]) {
      c.clear();
    }
    _tabController.index = 0;
    setState(() => _moreInfo = false);
    ref.invalidate(orderDraftProvider(widget.contextInput));
  }

  @override
  void dispose() {
    _tabController.dispose();
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

  void _increment(OrderDraftController d, MenuItem item) {
    final matching = d.lines.where((l) => l.item.id == item.id).toList();
    if (matching.isEmpty) {
      d.add(item);
    } else if (matching.length == 1) {
      final line = matching.first;
      d.edit(line.id, line.quantity + OrderQuantity.one, line.note);
    } else {
      _tabController.animateTo(1);
    }
  }

  void _decrement(OrderDraftController d, MenuItem item) {
    final matching = d.lines.where((l) => l.item.id == item.id).toList();
    if (matching.isEmpty) return;
    if (matching.length == 1) {
      final line = matching.first;
      if (line.quantity.milliUnits <= 1000) {
        d.remove(line.id);
      } else {
        d.edit(line.id, line.quantity - OrderQuantity.one, line.note);
      }
    } else {
      _tabController.animateTo(1);
    }
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

  Future<void> _onBack() async {
    final allowed = await ref.read(orderExitGuardProvider).allow(context);
    if (!mounted || !allowed) return;
    if (context.canPop()) {
      context.pop();
    } else if (_takeaway &&
        AccessPolicy.canTakeawayOrders(
          ref.read(authControllerProvider).state.session,
        )) {
      context.go('/app/takeaway');
    } else {
      context.go('/app/order-create');
    }
  }

  /// Name first (used to call the customer at pickup); phone and note fold away.
  Widget _takeawayCustomer(OrderDraftController d) {
    final expanded =
        _moreInfo || _phone.text.isNotEmpty || _note.text.isNotEmpty;
    InputDecoration field(String hint, IconData icon) => InputDecoration(
      isDense: true,
      counterText: '',
      hintText: hint,
      prefixIcon: Icon(icon, size: 20),
      filled: true,
      fillColor: const Color(0xFFF9FAFB),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
    );
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('takeaway-customer-name'),
                  controller: _name,
                  readOnly: d.frozen,
                  maxLength: 100,
                  textInputAction: TextInputAction.done,
                  onChanged: (_) => _fields(d),
                  decoration: field(
                    'Tên khách (để gọi khi lấy món)',
                    Icons.person_outline,
                  ),
                ),
              ),
              IconButton(
                tooltip: expanded ? 'Ẩn SĐT và ghi chú' : 'Thêm SĐT, ghi chú',
                onPressed: () => setState(() => _moreInfo = !expanded),
                icon: Icon(
                  expanded ? Icons.expand_less : Icons.add_comment_outlined,
                ),
              ),
            ],
          ),
          if (expanded) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: TextField(
                controller: _phone,
                readOnly: d.frozen,
                maxLength: 30,
                keyboardType: TextInputType.phone,
                onChanged: (_) => _fields(d),
                decoration: field('Số điện thoại', Icons.phone_outlined),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: TextField(
                controller: _note,
                readOnly: d.frozen,
                maxLength: 2000,
                minLines: 1,
                maxLines: 2,
                onChanged: (_) => _fields(d),
                decoration: field('Ghi chú đơn', Icons.notes),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = ref.watch(orderDraftProvider(widget.contextInput));
    d.adoptSeatingHint(widget.contextInput);
    _draft = d;
    _exit = ref.read(orderExitGuardProvider);
    _exit!.draft = d;
    if (d.result != null && _takeaway) {
      return TakeawaySubmittedView(
        order: d.result!,
        onCreateAnother: d.canCreate ? _startNew : null,
      );
    }
    if (d.result != null) {
      return OrderDetailScreen(
        id: d.result!.id,
        initialOrder: d.result,
        isOrderCreateFlow: true,
        tableName: widget.contextInput.tableName,
      );
    }
    final hasHistory =
        widget.contextInput.tableSessionId != null && d.can('ORDER_VIEW');

    final title =
        widget.contextInput.tableName ??
        (widget.contextInput.serviceType == ServiceType.takeaway
            ? 'Mang đi'
            : widget.contextInput.serviceType.label);

    final statusText = widget.contextInput.sessionAlreadyOpen
        ? 'Đang phục vụ'
        : 'Chưa gửi đơn';

    return Material(
      color: Colors.grey.shade50,
      child: SafeArea(
        child: Column(
          children: [
            // ── In-page Header ────────────────────────────────────────
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              child: Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.chevron_left, size: 22),
                      tooltip: 'Quay lại',
                      onPressed: _onBack,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 38,
                        minHeight: 38,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF111827),
                          ),
                        ),
                        if (!_takeaway)
                          Container(
                            margin: const EdgeInsets.only(top: 2),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: widget.contextInput.sessionAlreadyOpen
                                  ? const Color(0xFFFFF0EB)
                                  : const Color(0xFFF3F4F6),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              statusText,
                              style: TextStyle(
                                fontSize: 11,
                                color: widget.contextInput.sessionAlreadyOpen
                                    ? OrderPalette.orange
                                    : Colors.grey.shade700,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (!_takeaway) ...[
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.search, size: 18),
                        tooltip: 'Tìm kiếm',
                        onPressed: () => _tabController.animateTo(0),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 38,
                          minHeight: 38,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, size: 18),
                      tooltip: 'Thao tác khác',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 38,
                        minHeight: 38,
                      ),
                      itemBuilder: (context) => [
                        if (_takeaway && d.canDraft && d.canSubmit)
                          PopupMenuItem(
                            value: 'draft',
                            enabled:
                                !d.busy &&
                                !d.uncertain &&
                                d.canPick &&
                                d.lines.isNotEmpty,
                            onTap: () => _submit(d, OrderSubmissionMode.draft),
                            child: const Text('Lưu nháp (chưa gửi bếp)'),
                          ),
                        if (widget.contextInput.tableId != null &&
                            d.can('ORDER_VIEW'))
                          PopupMenuItem(
                            value: 'check_table',
                            onTap: () => _checkTable(d),
                            child: const Text('Kiểm tra bàn'),
                          ),
                        PopupMenuItem(
                          value: 'refresh',
                          onTap: () {
                            ref.invalidate(
                              orderMenuPickerProvider('ORDER_CREATE'),
                            );
                          },
                          child: const Text('Làm mới menu'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Tab Bar ───────────────────────────────────────────────
            Container(
              color: Colors.white,
              child: TabBar(
                controller: _tabController,
                indicatorColor: OrderPalette.orange,
                labelColor: OrderPalette.orange,
                unselectedLabelColor: Colors.grey.shade700,
                tabs: [
                  const Tab(text: 'Chọn món'),
                  Tab(text: 'Giỏ (${d.lines.length})'),
                  if (hasHistory) const Tab(text: 'Lịch sử trong phiên'),
                ],
              ),
            ),

            if (d.busy) const LinearProgressIndicator(),

            // ── Error & Review notices ────────────────────────────────
            OrderFailurePanel(
              failure: d.failure,
              retry: d.canRetry ? d.retry : null,
              label: 'Kiểm tra lại lần gửi này',
            ),
            if (d.needsTableReview && d.can('ORDER_VIEW'))
              Padding(
                padding: const EdgeInsets.all(4),
                child: TextButton(
                  onPressed: d.busy ? null : () => _checkTable(d),
                  child: const Text('Kiểm tra đơn của bàn'),
                ),
              ),
            if (d.keyConflict)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text(
                  'Lần gửi này trùng với một lần gửi trước nhưng nội dung khác. Đừng gửi lại, hãy nhờ người quản lý kiểm tra đơn.',
                ),
              ),
            if (d.uncertain)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text(
                  'Chưa xác định đơn đã được tạo hay chưa. Giỏ đã khóa; thử lại giữ nguyên yêu cầu và key.',
                ),
              ),

            // ── Main Content Area ─────────────────────────────────────
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Tab 1: Menu Picker with Item Steppers
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_takeaway) _takeawayCustomer(d),
                      Expanded(
                        child: OrderMenuPicker(
                          permission: 'ORDER_CREATE',
                          cartLines: d.lines,
                          onSelect: d.add,
                          onIncrement: (item) => _increment(d, item),
                          onDecrement: (item) => _decrement(d, item),
                          onEditLine: (item) => _tabController.animateTo(1),
                          enabled: !d.frozen && d.canPick,
                        ),
                      ),
                    ],
                  ),

                  // Tab 2: Cart Review & Details
                  Form(
                    key: _form,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
                      children: [
                        if (d.lines.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(24),
                            child: Center(child: Text('Chưa chọn món nào.')),
                          ),
                        for (final line in d.lines)
                          Card(
                            color: Colors.white,
                            elevation: 0,
                            margin: const EdgeInsets.only(bottom: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: BorderSide(color: Colors.grey.shade200),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          line.item.name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        orderMoney(line.previewMinor),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: OrderPalette.orange,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${line.quantity} ${line.item.baseUnit}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                  if (line.note?.isNotEmpty == true) ...[
                                    const SizedBox(height: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.amber.shade50,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        'Ghi chú: ${line.note}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.brown.shade700,
                                        ),
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      TextButton.icon(
                                        onPressed: d.frozen
                                            ? null
                                            : () => _edit(d, line),
                                        icon: const Icon(
                                          Icons.edit_note,
                                          size: 16,
                                        ),
                                        label: const Text('Số lượng / ghi chú'),
                                      ),
                                      TextButton.icon(
                                        onPressed: d.frozen
                                            ? null
                                            : () => d.remove(line.id),
                                        icon: const Icon(
                                          Icons.delete_outline,
                                          size: 16,
                                        ),
                                        label: const Text('Bỏ món'),
                                        style: TextButton.styleFrom(
                                          foregroundColor: Colors.red.shade700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (!_takeaway) ...[
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _name,
                            readOnly: d.frozen,
                            maxLength: 100,
                            onChanged: (_) => _fields(d),
                            decoration: InputDecoration(
                              labelText: 'Tên khách (không bắt buộc)',
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _phone,
                            readOnly: d.frozen,
                            maxLength: 30,
                            onChanged: (_) => _fields(d),
                            keyboardType: TextInputType.phone,
                            decoration: InputDecoration(
                              labelText: 'Số điện thoại (không bắt buộc)',
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _guests,
                            readOnly: d.frozen,
                            keyboardType: TextInputType.number,
                            onChanged: (_) => _fields(d),
                            decoration: InputDecoration(
                              labelText: widget.contextInput.fromTable
                                  ? 'Số khách (không bắt buộc)'
                                  : 'Số khách',
                              hintText: widget.contextInput.guestCount
                                  .toString(),
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
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
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _note,
                            readOnly: d.frozen,
                            maxLength: 2000,
                            maxLines: 3,
                            onChanged: (_) => _fields(d),
                            decoration: InputDecoration(
                              labelText: 'Ghi chú đơn',
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Tab 3: History (if available)
                  if (hasHistory)
                    OrderListScreen(
                      sessionId: widget.contextInput.tableSessionId,
                    ),
                ],
              ),
            ),

            // ── Sticky Bottom Cart Bar ────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${d.lines.length} món',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF111827),
                              ),
                            ),
                            Text(
                              'Tạm tính : ${orderMoney(d.previewMinor)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            OutlinedButton(
                              onPressed: () => _tabController.animateTo(1),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: OrderPalette.orange,
                                side: const BorderSide(
                                  color: OrderPalette.orange,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Text('Xem đơn'),
                                  SizedBox(width: 4),
                                  Icon(Icons.arrow_upward, size: 15),
                                ],
                              ),
                            ),
                            FilledButton(
                              onPressed:
                                  d.busy ||
                                      d.uncertain ||
                                      !d.canPick ||
                                      !d.canSubmit ||
                                      d.lines.isEmpty
                                  ? null
                                  : () =>
                                        _submit(d, OrderSubmissionMode.submit),
                              style: FilledButton.styleFrom(
                                backgroundColor: OrderPalette.orange,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: Text(d.busy ? 'Đang xử lý...' : 'Gửi đơn'),
                            ),
                          ],
                        ),
                      ],
                    ),
                    // Takeaway keeps drafts in the "⋮" menu unless sending
                    // is not allowed, in which case drafting is the only way.
                    if ((d.canDraft && !(_takeaway && d.canSubmit)) ||
                        (!d.canSubmit && d.canCreate))
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (!d.canSubmit && d.canCreate)
                              Expanded(
                                child: Text(
                                  widget.contextInput.fromTable
                                      ? 'Bạn chưa có quyền gửi đơn hoặc mở bàn, nhưng vẫn có thể lưu nháp.'
                                      : 'Bạn chưa có quyền gửi đơn, nhưng vẫn có thể lưu nháp.',
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ),
                            if (d.canDraft)
                              TextButton(
                                onPressed:
                                    d.busy ||
                                        d.uncertain ||
                                        !d.canPick ||
                                        d.lines.isEmpty
                                    ? null
                                    : () =>
                                          _submit(d, OrderSubmissionMode.draft),
                                child: const Text('Tạo nháp'),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
