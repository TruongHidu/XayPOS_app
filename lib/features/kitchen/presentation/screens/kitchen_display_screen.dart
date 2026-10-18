import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/result/result.dart';
import '../../../order/domain/entities/order_entities.dart';
import '../../domain/entities/kitchen_queue.dart';
import '../controllers/kitchen_display_controller.dart';
import '../providers/kitchen_providers.dart';
import '../widgets/kitchen_cards.dart';
import '../widgets/kitchen_action_confirmation_dialog.dart';

class KitchenDisplayScreen extends ConsumerStatefulWidget {
  const KitchenDisplayScreen({super.key});
  @override
  ConsumerState<KitchenDisplayScreen> createState() =>
      _KitchenDisplayScreenState();
}

class _KitchenDisplayScreenState extends ConsumerState<KitchenDisplayScreen>
    with WidgetsBindingObserver, RouteAware {
  final _search = TextEditingController();
  Timer? _tick;
  KitchenDisplayController? _display;
  ModalRoute<void>? _route;
  RouteObserver<ModalRoute<void>>? _observer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted &&
          _route?.isCurrent == true &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        setState(() {});
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of<void>(context);
    if (_route == route) return;
    _observer?.unsubscribe(this);
    _route = route;
    _observer = ref.read(kitchenRouteObserverProvider);
    if (route != null) _observer!.subscribe(this, route);
  }

  @override
  void didPushNext() => _display?.setVisible(false);
  @override
  void didPopNext() => _display?.setVisible(true);
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _display?.setForeground(state == AppLifecycleState.resumed);
  @override
  void dispose() {
    _tick?.cancel();
    _search.dispose();
    _observer?.unsubscribe(this);
    _display?.setVisible(false);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _act(
    KitchenQueueItem item,
    KitchenAction action, {
    bool wholeOrder = false,
  }) async {
    final actions = ref.read(kitchenActionsProvider);
    if (action == KitchenAction.markReady) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (_) => KitchenActionConfirmationDialog(
          item: item,
          scope: actions.scope,
          wholeOrder: wholeOrder,
        ),
      );
      if (!mounted || confirm != true || !actions.current) return;
    }
    final response = await (wholeOrder
        ? actions.readyOrder(item.orderId)
        : actions.act(item, action));
    if (!mounted || !actions.current) return;
    final message = switch (response) {
      Success(value: final order) =>
        actions.state(item.orderId)?.failure?.message ??
            (order.summary.status == OrderStatus.ready
                ? 'Đơn ${order.summary.orderCode} đã sẵn sàng.'
                : 'Đã cập nhật trạng thái món.'),
      Error(failure: final failure) => failure.message,
    };
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final display = ref.watch(kitchenDisplayProvider);
    final actions = ref.watch(kitchenActionsProvider);
    if (!identical(_display, display)) {
      _display?.setVisible(false);
      _display = display;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && identical(_display, display)) {
          display.setForeground(
            WidgetsBinding.instance.lifecycleState == null ||
                WidgetsBinding.instance.lifecycleState ==
                    AppLifecycleState.resumed,
          );
          display.setVisible(_route?.isCurrent ?? true);
        }
      });
    }
    if (!display.can('KITCHEN_VIEW')) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Cần KITCHEN_VIEW và KITCHEN_DISPLAY để xem màn hình bếp.',
          ),
        ),
      );
    }
    final rows = display.visibleItems;
    final groups = display.visibleOrders.values.toList();
    return ColoredBox(
      color: KitchenStyle.background,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
          final minWidth = 280.0 * scale.clamp(1, 1.5);
          final columns = ((constraints.maxWidth - 16) / (minWidth + 12))
              .floor()
              .clamp(1, 4);
          final count = display.mode == KitchenViewMode.items
              ? rows.length
              : groups.length;
          final now = display.clock();
          final trouble = actions.states.entries
              .where(
                (e) =>
                    e.value.busy ||
                    e.value.uncertain ||
                    e.value.needsReview ||
                    e.value.failure != null,
              )
              .toList();
          return CustomScrollView(
            key: const PageStorageKey('kitchen-scroll'),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 16,
                        runSpacing: 8,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                display.lastUpdated == null
                                    ? 'Đang tải hàng đợi'
                                    : (display.loading
                                          ? 'Đang đồng bộ...'
                                          : 'Cập nhật ${_time(display.lastUpdated!)}'),
                                style: TextStyle(
                                  color: Colors.blueGrey.shade700,
                                ),
                              ),
                            ],
                          ),
                          Wrap(
                            children: [
                              IconButton(
                                tooltip: 'Tải lại hàng đợi',
                                onPressed: display.loading
                                    ? null
                                    : display.refresh,
                                icon:
                                    display.loading && display.items.isNotEmpty
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.refresh),
                              ),
                              const IconButton(
                                tooltip: 'Âm thanh · Sắp có',
                                onPressed: null,
                                icon: Icon(Icons.volume_up_outlined),
                              ),
                              const IconButton(
                                tooltip: 'In phiếu bếp · Sắp có',
                                onPressed: null,
                                icon: Icon(Icons.print_outlined),
                              ),
                              const IconButton(
                                tooltip: 'Thiết lập bếp · Sắp có',
                                onPressed: null,
                                icon: Icon(Icons.settings_outlined),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final mode in KitchenViewMode.values)
                            ChoiceChip(
                              label: Text(
                                mode == KitchenViewMode.items
                                    ? 'Theo món'
                                    : 'Theo đơn',
                              ),
                              selected: display.mode == mode,
                              onSelected: (_) => display.setMode(mode),
                            ),
                          const Tooltip(
                            message: 'Theo nhóm · Sắp có',
                            child: ChoiceChip(
                              label: Text('Theo nhóm'),
                              selected: false,
                              onSelected: null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ChoiceChip(
                            label: Text('Tất cả (${display.items.length})'),
                            selected: display.filter == null,
                            onSelected: (_) => display.setFilter(null),
                          ),
                          for (final status in kitchenStatuses)
                            ChoiceChip(
                              label: Text(
                                '${KitchenStyle.label(status)} (${display.items.where((r) => r.itemStatus == status).length})',
                              ),
                              selected: display.filter == status,
                              onSelected: (_) => display.setFilter(status),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _search,
                        onChanged: display.setSearch,
                        maxLength: 100,
                        decoration: InputDecoration(
                          hintText: 'Tìm món, mã đơn, tên bàn…',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          counterText: '',
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                        ),
                      ),
                      if (display.loading && display.items.isEmpty) ...[
                        const SizedBox(height: 12),
                        const LinearProgressIndicator(),
                        Text(
                          'Đang tải đủ hàng đợi · ${display.loadedPages} trang đã tải',
                        ),
                      ],
                      if (display.items.isNotEmpty)
                        SizedBox(
                          height: 4,
                          child: display.loading
                              ? const LinearProgressIndicator(minHeight: 2)
                              : const SizedBox(height: 4),
                        ),
                      if (!display.complete && !display.loading)
                        const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: Text(
                            'Dữ liệu chưa đầy đủ hoặc đã cũ. Tải lại trước khi thao tác cả đơn.',
                          ),
                        ),
                      if (display.inconsistentOrders.isNotEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: Text(
                            'Một số đơn đang thay đổi giữa các trang. Vui lòng tải lại để đối chiếu.',
                          ),
                        ),
                      for (final error in display.failures.entries)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${KitchenStyle.label(error.key)}: ${error.value.message}',
                              ),
                              TextButton(
                                onPressed: display.loading
                                    ? null
                                    : display.refresh,
                                child: const Text('Thử tải lại'),
                              ),
                            ],
                          ),
                        ),
                      for (final e in trouble)
                        Card(
                          color: const Color(0xFFFFF7E8),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Đơn ${display.forOrder(e.key).firstOrNull?.orderCode ?? e.value.lastResponse?.summary.orderCode ?? e.key}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  e.value.busy
                                      ? 'Đang cập nhật trạng thái…'
                                      : e.value.uncertain
                                      ? 'Chưa xác định kết quả. Cần kiểm tra lại đúng thao tác; tải hiện trạng không xác nhận lần gửi này.'
                                      : e.value.failure?.message ??
                                            'Hãy xem lại dữ liệu mới.',
                                ),
                                if (e.value.uncertain)
                                  TextButton(
                                    onPressed: actions.canRetry(e.key)
                                        ? () => actions.retry(e.key)
                                        : null,
                                    child: const Text(
                                      'Kiểm tra lại đúng thao tác',
                                    ),
                                  ),
                                if (e.value.needsReview)
                                  TextButton(
                                    onPressed: display.complete && !e.value.busy
                                        ? () => actions.review(e.key)
                                        : null,
                                    child: const Text('Đã xem dữ liệu mới'),
                                  ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (count == 0 && !display.loading)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Text(
                        display.items.isEmpty && display.complete
                            ? 'Bếp đã xử lý hết món. Chưa có món trong hàng đợi.'
                            : 'Không có món phù hợp trong dữ liệu đã tải.',
                      ),
                    ),
                  ),
                ),
              SliverPadding(
                padding: const EdgeInsets.all(12),
                sliver: SliverList.builder(
                  itemCount: (count / columns).ceil(),
                  itemBuilder: (context, index) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var column = 0; column < columns; column++) ...[
                          if (column > 0) const SizedBox(width: 12),
                          Expanded(
                            child: index * columns + column >= count
                                ? const SizedBox.shrink()
                                : Builder(
                                    builder: (context) {
                                      final i = index * columns + column;
                                      if (display.mode ==
                                          KitchenViewMode.items) {
                                        final row = rows[i];
                                        return KitchenItemCard(
                                          key: ValueKey(
                                            'kitchen-item-${row.key}',
                                          ),
                                          item: row,
                                          now: now,
                                          busy:
                                              actions
                                                  .state(row.orderId)
                                                  ?.busy ==
                                              true,
                                          onStart:
                                              actions.canAct(
                                                row,
                                                KitchenAction.startCooking,
                                              )
                                              ? () => _act(
                                                  row,
                                                  KitchenAction.startCooking,
                                                )
                                              : null,
                                          onReady:
                                              actions.canAct(
                                                row,
                                                KitchenAction.markReady,
                                              )
                                              ? () => _act(
                                                  row,
                                                  KitchenAction.markReady,
                                                )
                                              : null,
                                        );
                                      }
                                      final group = groups[i];
                                      return KitchenOrderCard(
                                        key: ValueKey(
                                          'kitchen-order-${group.first.orderId}',
                                        ),
                                        items: group,
                                        now: now,
                                        complete: display.orderComplete(
                                          group.first.orderId,
                                        ),
                                        busy:
                                            actions
                                                .state(group.first.orderId)
                                                ?.busy ==
                                            true,
                                        orderStatus: display
                                            .orderStatuses[group.first.orderId],
                                        actionFor: (row) {
                                          final action =
                                              row.itemStatus ==
                                                  OrderItemStatus.pending
                                              ? KitchenAction.startCooking
                                              : KitchenAction.markReady;
                                          return actions.canAct(row, action)
                                              ? () => _act(row, action)
                                              : null;
                                        },
                                        onReadyOrder:
                                            actions.canReadyOrder(
                                              group.first.orderId,
                                            )
                                            ? () => _act(
                                                group.first,
                                                KitchenAction.markReady,
                                                wholeOrder: true,
                                              )
                                            : null,
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                sliver: SliverToBoxAdapter(
                  child: KitchenSummaryBar(
                    items: display.items,
                    complete: display.complete,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _time(DateTime date) {
    final local = date.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}:${local.second.toString().padLeft(2, '0')}';
  }
}
