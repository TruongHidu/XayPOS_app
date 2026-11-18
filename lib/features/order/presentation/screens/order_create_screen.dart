import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/theme/app_status_colors.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/ui/widgets/list_states.dart';
import '../../../../core/ui/widgets/status_badge.dart';
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
import '../widgets/menu_item_sheet.dart';
import '../widgets/order_cart_layout.dart';
import '../widgets/order_exit_guard.dart';
import '../widgets/order_menu_item_card.dart';
import '../widgets/order_menu_picker.dart';
import '../widgets/order_widgets.dart';
import '../widgets/takeaway_submitted_view.dart';
import 'order_detail_screen.dart';
import 'order_list_screen.dart';
import '../../../../app/theme/app_tokens.dart';

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
      AccessPolicy.orderScope(ref.watch(currentSessionProvider)),
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
    if (!widget.takeaway) ref.listen(orderServiceContextProvider, (_, _) {});
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
    with TickerProviderStateMixin, OrderCartUndo {
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
  // Created up front: side by side it may never be read during build, and
  // creating it lazily in dispose() would look up a deactivated ancestor.
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabCount, vsync: this);
  }

  /// Menu/history tabs beside the always-visible cart on wide screens.
  TabController? _wideTabsInstance;
  TabController get _wideTabs =>
      _wideTabsInstance ??= TabController(length: 2, vsync: this);

  /// Menu and cart side by side; set on each layout.
  bool _wide = false;

  OrderDraftController? _draft;
  OrderExitGuard? _exit;

  /// Takeaway is a quick counter sale: no guest count, customer details on
  /// the menu tab, and drafts tucked into the overflow menu.
  bool get _takeaway => widget.contextInput.serviceType == ServiceType.takeaway;
  bool _moreInfo = false;

  /// "Thông tin khách" is open in the cart.
  bool _infoOpen = false;

  void _startNew() {
    for (final c in [_name, _phone, _note]) {
      c.clear();
    }
    _tabController.index = 0;
    _wideTabsInstance?.index = 0;
    forgetRemoved();
    setState(() => _moreInfo = false);
    ref.invalidate(orderDraftProvider(widget.contextInput));
  }

  @override
  void dispose() {
    _tabController.dispose();
    _wideTabsInstance?.dispose();
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
      setState(() => _infoOpen = true);
      return;
    }
    if (_form.currentState != null && !_form.currentState!.validate()) {
      setState(() => _infoOpen = true);
      return;
    }
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

  /// Side by side the cart is always in view; only the tabs need a switch.
  void _showCart() {
    if (!_wide) _tabController.animateTo(1);
  }

  void _showMenu() =>
      _wide ? _wideTabsInstance?.animateTo(0) : _tabController.animateTo(0);

  void _removeLine(OrderDraftController d, OrderDraftLine line) {
    final index = d.lines.indexWhere((l) => l.id == line.id);
    if (index < 0) return;
    d.remove(line.id);
    if (!d.lines.any((l) => l.id == line.id)) rememberRemoved(line, index);
  }

  void _undoRemove(OrderDraftController d) {
    final removed = takeRemoved();
    if (removed != null) d.restore(removed.line, removed.index);
  }

  /// The dish's own sheet; the menu stays in view behind it.
  void _openItem(OrderDraftController d, MenuItem item) => showMenuItemSheet(
    context,
    ref,
    item: item,
    cart: d,
    permission: 'ORDER_CREATE',
  );

  void _increment(OrderDraftController d, MenuItem item) {
    final matching = d.lines.where((l) => l.item.id == item.id).toList();
    if (matching.isEmpty) {
      d.add(item);
    } else if (matching.length == 1) {
      final line = matching.first;
      d.edit(line.id, line.quantity + OrderQuantity.one, line.note);
    } else {
      // Several ways of making it: let the cashier pick the line.
      _openItem(d, item);
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
      // Several ways of making it: let the cashier pick the line.
      _openItem(d, item);
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
    );
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.sm,
          AppSpacing.sm,
        ),
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
              const SizedBox(height: AppSpacing.sm),
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.xs),
                child: TextField(
                  controller: _phone,
                  readOnly: d.frozen,
                  maxLength: 30,
                  keyboardType: TextInputType.phone,
                  onChanged: (_) => _fields(d),
                  decoration: field('Số điện thoại', Icons.phone_outlined),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.xs),
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
      ),
    );
  }

  /// One cart line: name and amount, a quick − n +, then its note and the
  /// quantity/note editor and removal.
  Widget _cartLine(OrderDraftController d, OrderDraftLine line) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final danger = context.tone(AppTone.danger);
    final warning = context.tone(AppTone.warning);
    final locked = d.frozen;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Dismissible(
        key: ValueKey('cart-line-${line.id}'),
        direction: locked ? DismissDirection.none : DismissDirection.endToStart,
        onDismissed: (_) => _removeLine(d, line),
        background: DecoratedBox(
          decoration: BoxDecoration(
            color: danger.foreground,
            borderRadius: AppRadius.mdAll,
          ),
          child: Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              child: Text(
                'Bỏ món',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: colors.onError,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
        child: Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.xs,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(line.item.name, style: theme.textTheme.titleSmall),
                        Text(
                          // Quantity as entered, never rounded: "1.5 kg".
                          '${'${line.quantity} ${line.item.baseUnit}'.trim()}'
                          ' · ${orderMoney(line.previewMinor)}',
                          style: theme.textTheme.money.copyWith(
                            fontWeight: FontWeight.w400,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        OrderStepButton(
                          tooltip: 'Bớt 1 ${line.item.name} trong giỏ',
                          icon: Icons.remove,
                          onPressed: locked
                              ? null
                              : () => line.quantity.milliUnits <= 1000
                                    ? _removeLine(d, line)
                                    : d.edit(
                                        line.id,
                                        line.quantity - OrderQuantity.one,
                                        line.note,
                                      ),
                        ),
                        OrderQuantityText(line.quantity),
                        OrderStepButton(
                          tooltip: 'Thêm 1 ${line.item.name} trong giỏ',
                          icon: Icons.add,
                          filled: true,
                          onPressed: locked
                              ? null
                              : () => d.edit(
                                  line.id,
                                  line.quantity + OrderQuantity.one,
                                  line.note,
                                ),
                        ),
                      ],
                    ),
                  ],
                ),
                if (line.note?.isNotEmpty == true) ...[
                  const SizedBox(height: AppSpacing.xs),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: warning.background,
                      borderRadius: AppRadius.xsAll,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: 2,
                      ),
                      child: Text(
                        'Ghi chú: ${line.note}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: warning.foreground,
                        ),
                      ),
                    ),
                  ),
                ],
                // Wraps in the narrow side-by-side cart pane.
                SizedBox(
                  width: double.infinity,
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: AppSpacing.xs,
                    children: [
                      TextButton.icon(
                        onPressed: locked ? null : () => _edit(d, line),
                        icon: const Icon(Icons.edit_note),
                        label: const Text('Số lượng / ghi chú'),
                      ),
                      TextButton.icon(
                        onPressed: locked ? null : () => _removeLine(d, line),
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Bỏ món'),
                        style: TextButton.styleFrom(
                          foregroundColor: danger.foreground,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Name, phone and guest count: optional at a table, so folded away. The
  /// fields stay mounted while folded, so the form still checks them.
  Widget _customerInfo(OrderDraftController d) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final optional = widget.contextInput.fromTable;
    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            key: const ValueKey('order-customer-info'),
            minTileHeight: 56,
            leading: Icon(Icons.person_outline, color: colors.onSurfaceVariant),
            title: Text('Thông tin khách', style: theme.textTheme.titleSmall),
            subtitle: ListenableBuilder(
              listenable: Listenable.merge([_name, _guests]),
              builder: (context, _) {
                final name = _name.text.trim();
                final guests = _guests.text.trim();
                return Text(
                  [
                    if (optional) 'Không bắt buộc',
                    if (name.isNotEmpty) name,
                    if (!optional && guests.isNotEmpty) '$guests khách',
                    if (name.isEmpty && (optional || guests.isEmpty))
                      'Chưa nhập',
                  ].join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                );
              },
            ),
            trailing: Icon(_infoOpen ? Icons.expand_less : Icons.expand_more),
            onTap: () => setState(() => _infoOpen = !_infoOpen),
          ),
          Visibility(
            visible: _infoOpen,
            maintainState: true,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.xs,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _name,
                    readOnly: d.frozen,
                    maxLength: 100,
                    onChanged: (_) => _fields(d),
                    decoration: const InputDecoration(
                      labelText: 'Tên khách (không bắt buộc)',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
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
                  const SizedBox(height: AppSpacing.sm),
                  TextFormField(
                    controller: _guests,
                    readOnly: d.frozen,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => _fields(d),
                    decoration: InputDecoration(
                      labelText: optional
                          ? 'Số khách (không bắt buộc)'
                          : 'Số khách',
                      hintText: widget.contextInput.guestCount.toString(),
                    ),
                    validator: (v) {
                      if (optional && (v?.trim().isEmpty ?? true)) {
                        return null;
                      }
                      final n = int.tryParse(v ?? '');
                      return n == null || n < 1 || n > 32767
                          ? 'Nhập số từ 1 đến 32767'
                          : null;
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Amount and the send button: under the screen on phones, at the foot of
  /// the cart pane when it sits beside the menu.
  Widget _footer(OrderDraftController d, {required bool pane}) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final label = theme.textTheme.bodySmall?.copyWith(
      color: colors.onSurfaceVariant,
    );
    final canSend =
        !(d.busy ||
            d.uncertain ||
            !d.canPick ||
            !d.canSubmit ||
            d.lines.isEmpty);
    final amount = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          children: [
            Text('${d.lines.length} món', style: label),
            Text(' · Tạm tính', style: label),
          ],
        ),
        Text(
          orderMoney(d.previewMinor),
          key: const ValueKey('order-cart-total'),
          softWrap: false,
          style: theme.textTheme.moneyLarge,
        ),
      ],
    );
    final send = FilledButton(
      onPressed: canSend ? () => _submit(d, OrderSubmissionMode.submit) : null,
      style: FilledButton.styleFrom(
        minimumSize: Size(pane ? double.infinity : 0, pane ? 56 : 48),
        // While sending it stays blue, with the spinner, not greyed out.
        disabledBackgroundColor: d.busy
            ? Color.lerp(colors.primary, colors.surface, 0.3)
            : null,
        disabledForegroundColor: d.busy ? colors.onPrimary : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (d.busy) ...[
            SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: colors.onPrimary,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          Text(d.busy ? 'Đang gửi…' : 'Gửi đơn'),
        ],
      ),
    );
    // Takeaway keeps drafts in the "⋮" menu unless sending is not allowed,
    // in which case drafting is the only way.
    final draftRow =
        (d.canDraft && !(_takeaway && d.canSubmit)) ||
            (!d.canSubmit && d.canCreate)
        ? Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!d.canSubmit && d.canCreate)
                  Expanded(
                    child: Text(
                      widget.contextInput.fromTable
                          ? 'Bạn chưa có quyền gửi đơn hoặc mở bàn, nhưng vẫn có thể lưu nháp.'
                          : 'Bạn chưa có quyền gửi đơn, nhưng vẫn có thể lưu nháp.',
                      style: theme.textTheme.bodySmall,
                    ),
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
          )
        : null;

    final content = pane
        ? Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              amount,
              const SizedBox(height: AppSpacing.md),
              send,
              ?draftRow,
            ],
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Large text moves the buttons under the amount.
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.sm,
                children: [
                  amount,
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      OutlinedButton(
                        onPressed: _showCart,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 48),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Xem đơn'),
                            SizedBox(width: AppSpacing.xs),
                            Icon(Icons.expand_less, size: 20),
                          ],
                        ),
                      ),
                      send,
                    ],
                  ),
                ],
              ),
              ?draftRow,
            ],
          );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: pane
              ? const EdgeInsets.fromLTRB(
                  AppSpacing.xxl,
                  AppSpacing.lg,
                  AppSpacing.xxl,
                  AppSpacing.xxl,
                )
              : const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.md,
                ),
          child: content,
        ),
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
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
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

    final Widget menuPane = Column(
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
            onOpenItem: (item) => _openItem(d, item),
            enabled: !d.frozen && d.canPick,
          ),
        ),
      ],
    );

    Widget cartPane({required bool beside}) => Form(
      key: _form,
      child: ListView(
        padding: EdgeInsets.all(beside ? AppSpacing.lg : AppSpacing.lg),
        children: [
          if (d.lines.isEmpty && removedLine == null)
            EmptyState(
              icon: Icons.shopping_cart_outlined,
              message: 'Chưa chọn món nào.',
              hint: beside ? 'Chạm + ở món bên trái để thêm.' : null,
              action: beside
                  ? null
                  : OutlinedButton(
                      onPressed: _showMenu,
                      child: const Text('Chọn món'),
                    ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(
                'MÓN ĐÃ CHỌN',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                  letterSpacing: 0.6,
                ),
              ),
            ),
          ...withUndoTile(
            enabled: !d.frozen && d.canPick,
            onUndo: () => _undoRemove(d),
            [for (final line in d.lines) _cartLine(d, line)],
          ),
          if (!_takeaway) ...[
            const SizedBox(height: AppSpacing.sm),
            _customerInfo(d),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _note,
              readOnly: d.frozen,
              maxLength: 2000,
              maxLines: 3,
              onChanged: (_) => _fields(d),
              decoration: const InputDecoration(labelText: 'Ghi chú đơn'),
            ),
          ],
        ],
      ),
    );

    final Widget? historyPane = hasHistory
        ? OrderListScreen(sessionId: widget.contextInput.tableSessionId)
        : null;

    TabBar tabs(TabController controller, List<Widget> children) => TabBar(
      controller: controller,
      labelStyle: theme.textTheme.titleSmall,
      tabs: children,
    );

    return Material(
      color: theme.scaffoldBackgroundColor,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            _wide = constraints.maxWidth >= orderSplitMinWidth;
            final gutter = _wide ? AppSpacing.xxl : AppSpacing.lg;
            return Column(
              children: [
                // ── In-page header ────────────────────────────────────────
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surface,
                    border: _wide
                        ? Border(
                            bottom: BorderSide(color: colors.outlineVariant),
                          )
                        : null,
                  ),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      AppSpacing.xs,
                      AppSpacing.xs,
                      gutter - AppSpacing.md,
                      AppSpacing.xs,
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back),
                          tooltip: 'Quay lại',
                          onPressed: _onBack,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Wrap(
                            spacing: AppSpacing.sm,
                            runSpacing: AppSpacing.xs,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                title,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (!_takeaway)
                                StatusBadge(
                                  label: statusText,
                                  dot: true,
                                  tone: widget.contextInput.sessionAlreadyOpen
                                      ? AppTone.primary
                                      : AppTone.neutral,
                                ),
                            ],
                          ),
                        ),
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert),
                          tooltip: 'Thao tác khác',
                          itemBuilder: (context) => [
                            if (_takeaway && d.canDraft && d.canSubmit)
                              PopupMenuItem(
                                value: 'draft',
                                enabled:
                                    !d.busy &&
                                    !d.uncertain &&
                                    d.canPick &&
                                    d.lines.isNotEmpty,
                                onTap: () =>
                                    _submit(d, OrderSubmissionMode.draft),
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
                      ],
                    ),
                  ),
                ),

                // ── Tab bar ───────────────────────────────────────────────
                if (!_wide)
                  ColoredBox(
                    color: colors.surface,
                    child: tabs(_tabController, [
                      const Tab(text: 'Chọn món'),
                      Tab(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Flexible(
                              child: Text('Giỏ', overflow: TextOverflow.fade),
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            OrderCartCount(d.lines.length),
                          ],
                        ),
                      ),
                      if (hasHistory) const Tab(text: 'Lịch sử trong phiên'),
                    ]),
                  ),

                if (d.busy) const LinearProgressIndicator(),

                // ── Error & review notices ────────────────────────────────
                OrderFailurePanel(
                  failure: d.failure,
                  retry: d.canRetry ? d.retry : null,
                  label: 'Kiểm tra lại lần gửi này',
                  cart: shortageCartOf(d.lines),
                  onEditCart: _showCart,
                ),
                if (d.needsTableReview && d.can('ORDER_VIEW'))
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.xs),
                    child: TextButton(
                      onPressed: d.busy ? null : () => _checkTable(d),
                      child: const Text('Kiểm tra đơn của bàn'),
                    ),
                  ),
                if (d.keyConflict)
                  const Padding(
                    padding: EdgeInsets.all(AppSpacing.sm),
                    child: Text(
                      'Lần gửi này trùng với một lần gửi trước nhưng nội dung khác. Đừng gửi lại, hãy nhờ người quản lý kiểm tra đơn.',
                    ),
                  ),
                if (d.uncertain)
                  const Padding(
                    padding: EdgeInsets.all(AppSpacing.sm),
                    child: Text(
                      'Chưa xác định đơn đã được tạo hay chưa. Giỏ đã khóa; thử lại giữ nguyên yêu cầu và key.',
                    ),
                  ),

                // ── Main content ──────────────────────────────────────────
                Expanded(
                  child: _wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: historyPane == null
                                  ? menuPane
                                  : Column(
                                      children: [
                                        ColoredBox(
                                          color: colors.surface,
                                          child: tabs(_wideTabs, const [
                                            Tab(text: 'Chọn món'),
                                            Tab(text: 'Lịch sử trong phiên'),
                                          ]),
                                        ),
                                        Expanded(
                                          child: TabBarView(
                                            controller: _wideTabs,
                                            children: [menuPane, historyPane],
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                            VerticalDivider(
                              width: 1,
                              thickness: 1,
                              color: colors.outlineVariant,
                            ),
                            // The cart, its total and the send button stay
                            // in view while the cashier picks dishes.
                            SizedBox(
                              key: const ValueKey('order-cart-pane'),
                              width: orderCartPaneWidth(constraints.maxWidth),
                              child: ColoredBox(
                                color: colors.surface,
                                child: Column(
                                  children: [
                                    OrderCartPaneHeader(
                                      title: 'Giỏ',
                                      count: d.lines.length,
                                    ),
                                    Expanded(child: cartPane(beside: true)),
                                    _footer(d, pane: true),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        )
                      : TabBarView(
                          controller: _tabController,
                          children: [
                            menuPane,
                            cartPane(beside: false),
                            ?historyPane,
                          ],
                        ),
                ),

                // ── Sticky bottom bar (phones) ────────────────────────────
                if (!_wide) _footer(d, pane: false),
              ],
            );
          },
        ),
      ),
    );
  }
}
