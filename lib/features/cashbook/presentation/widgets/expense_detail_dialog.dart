import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/providers.dart' show authControllerProvider;
import '../../../../core/auth/access_policy.dart';
import '../../../../core/errors/failure.dart';
import '../../../inventory/presentation/widgets/stock_widgets.dart'
    show stockDetailLocation;
import '../../domain/entities/cashbook_records.dart';
import '../../domain/policies/expense_validation.dart';
import '../../domain/use_cases/cashbook_use_cases.dart';
import '../controllers/expense_actions_controller.dart';
import '../providers/cashbook_providers.dart';
import 'cashbook_common.dart';
import 'cashbook_dialog_frame.dart';
import 'cashbook_format.dart';

Future<void> showExpenseDetailDialog(
  BuildContext context, {
  required String expenseId,
  CashbookExpense? initial,
}) => showDialog<void>(
  context: context,
  builder: (_) => ExpenseDetailDialog(expenseId: expenseId, initial: initial),
);

/// Full voucher detail. Voiding happens inline so the typed reason survives
/// a version conflict while the newer state is reloaded underneath it.
class ExpenseDetailDialog extends ConsumerStatefulWidget {
  const ExpenseDetailDialog({super.key, required this.expenseId, this.initial});
  final String expenseId;
  final CashbookExpense? initial;

  @override
  ConsumerState<ExpenseDetailDialog> createState() =>
      _ExpenseDetailDialogState();
}

class _ExpenseDetailDialogState extends ConsumerState<ExpenseDetailDialog> {
  late final ExpenseDetailController _controller;
  final _reason = TextEditingController();
  bool _voidOpen = false;
  String? _reasonError;

  @override
  void initState() {
    super.initState();
    final repository = ref.read(cashbookRepositoryProvider);
    _controller = ExpenseDetailController(
      expenseId: widget.expenseId,
      getExpense: GetCashbookExpense(repository),
      voidExpense: VoidCashbookExpense(repository),
      initial: widget.initial,
    );
    // The list row may be stale; the version used for voiding must be fresh.
    _controller.load();
  }

  @override
  void dispose() {
    _controller.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _confirmVoid() async {
    final error = validateVoidReason(_reason.text);
    setState(() => _reasonError = error);
    if (error != null) return;
    final ok = await _controller.voidExpense(_reason.text.trim());
    if (!mounted) return;
    final failure = _controller.voidFailure;
    if (ok || failure?.type == FailureType.conflict) {
      // Either way the stored state changed; every tab must reread it.
      ref.read(cashbookChangesProvider.notifier).notifyChanged();
    }
    if (ok) {
      setState(() => _voidOpen = false);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            'Đã hủy phiếu chi ${_controller.expense?.expenseCode ?? ''}.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authControllerProvider).state.session;
    final timezone = ref.watch(
      cashbookRangeProvider.select((c) => c.meta?.timezone),
    );
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final c = _controller;
        final expense = c.expense;
        final canVoid =
            AccessPolicy.canCashbook(session, 'CASHBOOK_VOID') &&
            expense != null &&
            !expense.isVoided;
        return PopScope(
          canPop: !c.voiding,
          child: CashbookDialogFrame(
            title: expense?.expenseCode ?? 'Phiếu chi',
            subtitle: expense?.categoryName,
            icon: Icons.request_quote_outlined,
            actions: [
              if (canVoid && !_voidOpen)
                TextButton.icon(
                  key: const ValueKey('expense-detail-void'),
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                  onPressed: () => setState(() => _voidOpen = true),
                  icon: const Icon(Icons.block),
                  label: const Text('Hủy phiếu ghi nhầm'),
                ),
              FilledButton(
                onPressed: c.voiding ? null : () => Navigator.of(context).pop(),
                child: const Text('Đóng'),
              ),
            ],
            body: expense == null
                ? (c.loadFailure != null
                      ? CashbookNotice(
                          message: c.loadFailure!.message,
                          tone: CashbookNoticeTone.error,
                          action: TextButton(
                            onPressed: c.load,
                            child: const Text('Thử lại'),
                          ),
                        )
                      : const SizedBox(
                          height: 160,
                          child: Center(child: CircularProgressIndicator()),
                        ))
                : _body(context, expense, timezone),
          ),
        );
      },
    );
  }

  Widget _body(
    BuildContext context,
    CashbookExpense expense,
    String? timezone,
  ) {
    final theme = Theme.of(context);
    final c = _controller;
    final appSession = ref.read(authControllerProvider).state.session;
    final canOpenReceipt =
        expense.stockDocumentId != null &&
        AccessPolicy.canInventory(appSession, 'INVENTORY_VIEW');
    final userId = appSession?.authenticatedUser.id;
    String person(String? id) => id == null
        ? '—'
        : (id == userId ? 'Bạn' : 'Nhân viên ${id.substring(0, 8)}');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (c.loading) const LinearProgressIndicator(),
        if (c.voidFailure != null) ...[
          CashbookNotice(
            message: c.voidFailure!.message,
            tone: CashbookNoticeTone.error,
          ),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            Expanded(
              child: Text(
                cashbookMoney(expense.amount, expense.currencyCode),
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: expense.isVoided
                      ? theme.colorScheme.onSurfaceVariant
                      : CashbookColors.expense(theme.colorScheme),
                  decoration: expense.isVoided
                      ? TextDecoration.lineThrough
                      : null,
                ),
              ),
            ),
            CashbookBadge.status(theme.colorScheme, expense.status),
          ],
        ),
        const SizedBox(height: 12),
        _Section(
          title: 'Thanh toán',
          rows: [
            ('Ngày thực chi', cashbookDateTime(expense.expenseAt, timezone)),
            ('Phương thức', expense.paymentMethod.label),
            ('Người nhận', expense.payeeName ?? '—'),
            ('Mã tham chiếu', expense.referenceNo ?? '—'),
          ],
        ),
        if (expense.stockDocumentId != null)
          _Section(
            title: 'Nguồn liên kết',
            rows: [
              ('Phiếu nhập', expense.sourceDocumentCode ?? '—'),
              if (expense.sourceCurrencyStatus?.apiCode == 'UNKNOWN')
                ('Tiền tệ phiếu nhập', 'Chưa rõ'),
            ],
            action: canOpenReceipt
                ? TextButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      context.push(
                        stockDetailLocation(expense.stockDocumentId!),
                      );
                    },
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('Mở phiếu nhập'),
                  )
                : null,
          ),
        if (expense.note != null)
          _Section(title: 'Ghi chú', rows: [('', expense.note!)]),
        _Section(
          title: 'Ghi sổ',
          rows: [
            ('Người ghi', person(expense.createdBy)),
            ('Thời điểm ghi sổ', cashbookDateTime(expense.createdAt, timezone)),
          ],
        ),
        if (expense.isVoided)
          _Section(
            title: 'Đã hủy',
            rows: [
              ('Người hủy', person(expense.voidedBy)),
              (
                'Thời điểm hủy',
                expense.voidedAt == null
                    ? '—'
                    : cashbookDateTime(expense.voidedAt!, timezone),
              ),
              ('Lý do', expense.voidReason ?? '—'),
            ],
          ),
        if (_voidOpen && !expense.isVoided) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.colorScheme.error),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Hủy phiếu ghi nhầm',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.error,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Phiếu giữ nguyên lịch sử nhưng không còn tính vào tổng chi. '
                  'Không hoàn tiền, không thay đổi tồn kho. Báo cáo các kỳ trước có thể thay đổi. '
                  'Nếu ghi sai, hãy lập phiếu thay thế sau khi hủy.',
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('expense-void-reason'),
                  controller: _reason,
                  enabled: !c.voiding,
                  maxLength: ExpenseLimits.voidReason,
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: 'Lý do hủy *',
                    hintText: 'Ví dụ: ghi nhầm số tiền, sẽ lập phiếu thay thế',
                    border: const OutlineInputBorder(),
                    errorText: _reasonError,
                  ),
                ),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: c.voiding
                          ? null
                          : () => setState(() => _voidOpen = false),
                      child: const Text('Thôi'),
                    ),
                    FilledButton.icon(
                      key: const ValueKey('expense-void-confirm'),
                      style: FilledButton.styleFrom(
                        backgroundColor: theme.colorScheme.error,
                        foregroundColor: theme.colorScheme.onError,
                      ),
                      onPressed: c.voiding || c.loading ? null : _confirmVoid,
                      icon: c.voiding
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.block),
                      label: const Text('Xác nhận hủy'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.rows, this.action});
  final String title;
  final List<(String, String)> rows;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (action != null) action!,
            ],
          ),
          const Divider(height: 12),
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: label.isEmpty
                  ? Text(value)
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 140,
                          child: Text(
                            label,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            value,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
            ),
        ],
      ),
    );
  }
}
