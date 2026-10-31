import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/providers.dart' show authControllerProvider;
import '../../../../core/auth/access_policy.dart';
import '../../../reports/domain/entities/report_date.dart';
import '../../domain/entities/cashbook_meta.dart';
import '../providers/cashbook_providers.dart';
import '../widgets/cashbook_common.dart';
import '../widgets/cashbook_flow_tab.dart';
import '../widgets/cashbook_format.dart';
import '../widgets/expense_form_dialog.dart';

class CashbookScreen extends ConsumerWidget {
  const CashbookScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authControllerProvider).state.session;
    if (!AccessPolicy.canCashbook(session, 'CASHBOOK_VIEW')) {
      return const CashbookAccessDenied(
        message:
            'Chưa có quyền xem sổ thu chi. Tài khoản cần quyền xem sổ thu chi và gói đang hiệu lực có báo cáo chi tiết.',
      );
    }
    return _CashbookWorkspace(
      key: ValueKey(AccessPolicy.cashbookScope(session)),
    );
  }
}

class _CashbookWorkspace extends ConsumerStatefulWidget {
  const _CashbookWorkspace({super.key});

  @override
  ConsumerState<_CashbookWorkspace> createState() => _CashbookWorkspaceState();
}

class _CashbookWorkspaceState extends ConsumerState<_CashbookWorkspace> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(cashbookFlowProvider).initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authControllerProvider).state.session;
    final flow = ref.watch(cashbookFlowProvider);
    final meta = ref.watch(cashbookRangeProvider.select((c) => c.meta));
    final range = ref.watch(cashbookRangeProvider.select((c) => c.applied));
    return Scaffold(
      floatingActionButton: AccessPolicy.canCashbook(session, 'CASHBOOK_CREATE')
          ? FloatingActionButton.extended(
              key: const ValueKey('cashbook-create-action'),
              tooltip: 'Ghi nhận khoản chi',
              onPressed: () => showExpenseFormDialog(context),
              icon: const Icon(Icons.add),
              label: const Text('Ghi nhận chi'),
            )
          : null,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final gutter = CashbookLayout.of(constraints.maxWidth).gutter;
          return RefreshIndicator(
            onRefresh: flow.refresh,
            child: SingleChildScrollView(
              key: const PageStorageKey('cashbook-workspace'),
              physics: const AlwaysScrollableScrollPhysics(),
              // The bottom inset keeps the list end clear of the floating button.
              padding: EdgeInsets.fromLTRB(gutter, gutter, gutter, 88),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1400),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _ScopeHeader(
                        meta: meta,
                        range: range.range,
                        loading: flow.loading,
                        onRefresh: flow.refresh,
                      ),
                      SizedBox(
                        height: 4,
                        child: flow.loading
                            ? const LinearProgressIndicator()
                            : const SizedBox.shrink(),
                      ),
                      const SizedBox(height: 12),
                      if (flow.accessFailure != null)
                        CashbookAccessDenied(
                          message: flow.accessFailure!.message,
                          checking: flow.checkingAccess,
                          onRetry: flow.retryAccess,
                        )
                      else
                        const CashbookFlowTab(),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// What the figures below describe: the applied range, the restaurant's
/// timezone and the currency the server answered in.
class _ScopeHeader extends StatelessWidget {
  const _ScopeHeader({
    required this.meta,
    required this.range,
    required this.loading,
    required this.onRefresh,
  });

  final CashbookMeta? meta;
  final ReportDateRange range;
  final bool loading;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    Widget chip(IconData icon, String text) => Chip(
      avatar: Icon(icon, size: 16),
      label: Text(text),
      visualDensity: VisualDensity.compact,
    );
    final meta = this.meta;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              chip(Icons.event_outlined, cashbookRangeLabel(range)),
              if (meta != null) ...[
                chip(Icons.monetization_on_outlined, meta.currencyCode),
                chip(Icons.public, 'Giờ ${meta.timezone}'),
              ],
            ],
          ),
        ),
        IconButton(
          tooltip: 'Tải lại',
          onPressed: loading ? null : onRefresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
    );
  }
}
