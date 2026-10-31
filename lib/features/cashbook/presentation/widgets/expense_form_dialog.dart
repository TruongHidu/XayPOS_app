import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/providers.dart' show authControllerProvider;
import '../../../../core/auth/access_policy.dart';
import '../../domain/entities/cashbook_enums.dart';
import '../../domain/entities/cashbook_inputs.dart';
import '../../domain/entities/cashbook_records.dart';
import '../../domain/policies/expense_validation.dart';
import '../providers/cashbook_providers.dart';
import 'cashbook_common.dart';
import 'cashbook_dialog_frame.dart';
import 'cashbook_format.dart';
import 'stock_receipt_picker_dialog.dart';
import 'stock_receipts_table.dart';

/// Records money that was already paid. After a successful save the cashbook
/// rereads every tab and the caller gets the stored voucher.
Future<void> showExpenseFormDialog(BuildContext context) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final result = await showDialog<ExpenseCreateResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const ExpenseFormDialog(),
  );
  if (result == null) return;
  final code = result.expense.expenseCode;
  messenger?.showSnackBar(
    SnackBar(
      content: Text(
        result.replayed
            ? 'Phiếu chi $code đã được ghi nhận trước đó, không tạo trùng.'
            : 'Đã ghi nhận phiếu chi $code.',
      ),
    ),
  );
}

class ExpenseFormDialog extends ConsumerStatefulWidget {
  const ExpenseFormDialog({super.key});

  @override
  ConsumerState<ExpenseFormDialog> createState() => _ExpenseFormDialogState();
}

class _ExpenseFormDialogState extends ConsumerState<ExpenseFormDialog> {
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  final _payee = TextEditingController();
  final _note = TextEditingController();
  String? _categoryCode;
  CashbookPaymentMethod _method = CashbookPaymentMethod.cash;
  late DateTime _paidAt;
  CashbookStockReceipt? _receipt;
  Map<String, String> _errors = const {};
  String? _notice;
  bool _submitted = false;

  String? get _zone => ref.read(cashbookRangeProvider).meta?.timezone;

  @override
  void initState() {
    super.initState();
    final wall = cashbookWallTime(DateTime.now(), _zone);
    _paidAt = DateTime(wall.year, wall.month, wall.day, wall.hour, wall.minute);
    for (final field in [_amount, _reference, _payee, _note]) {
      field.addListener(_edited);
    }
  }

  @override
  void dispose() {
    for (final field in [_amount, _reference, _payee, _note]) {
      field.dispose();
    }
    super.dispose();
  }

  void _edited() {
    if (_submitted) setState(() => _errors = _validate());
  }

  DateTime get _instant => cashbookInstantFromWallTime(_paidAt, _zone);

  Map<String, String> _validate() => validateExpenseDraft(
    categoryCode: _categoryCode,
    amountText: _amount.text,
    expenseAt: _instant,
    now: DateTime.now().add(const Duration(minutes: 1)),
    stockDocumentId: _receipt?.stockDocumentId,
    referenceNo: _reference.text,
    payeeName: _payee.text,
    note: _note.text,
  );

  String? get _currency {
    final receipt = _receipt;
    if (receipt != null && !receipt.currencyUnknown) {
      return receipt.currencyCode;
    }
    final range = ref.read(cashbookRangeProvider);
    return range.applied.currencyCode ?? range.meta?.currencyCode;
  }

  Future<void> _submit() async {
    _submitted = true;
    final errors = _validate();
    setState(() {
      _errors = errors;
      _notice = null;
    });
    if (errors.isNotEmpty) return;
    final receipt = _receipt;
    final range = ref.read(cashbookRangeProvider).applied;
    final input = CreateExpenseInput(
      categoryCode: _categoryCode!,
      amount: parseExpenseAmount(_amount.text).value!,
      paymentMethod: _method,
      expenseAt: _instant,
      // A known receipt currency must match; otherwise the server falls back
      // to the restaurant currency unless the cashbook is pinned to another.
      currencyCode: receipt != null && !receipt.currencyUnknown
          ? receipt.currencyCode
          : range.currencyCode,
      stockDocumentId: receipt?.stockDocumentId,
      referenceNo: _reference.text,
      payeeName: _payee.text,
      note: _note.text,
    );
    final submitter = ref.read(expenseSubmitProvider);
    final result = await submitter.submit(input);
    if (!mounted) return;
    if (result == null) {
      final failure = submitter.failure;
      setState(() => _errors = {..._errors, ...?failure?.fieldErrors});
      return;
    }
    ref.read(cashbookChangesProvider.notifier).notifyChanged();
    if (result.replayed && result.expense.isVoided) {
      setState(
        () => _notice =
            'Khoản chi này đã được ghi nhận trước đó (${result.expense.expenseCode}) và đã bị hủy. Không tạo phiếu mới; hãy đổi nội dung nếu cần ghi lại.',
      );
      return;
    }
    Navigator.of(context).pop(result);
  }

  Future<void> _pickDate() async {
    final today = cashbookToday(_zone).toDateTime();
    final picked = await showDatePicker(
      context: context,
      initialDate: _paidAt.isAfter(today) ? today : _paidAt,
      firstDate: DateTime(2020),
      lastDate: today,
      helpText: 'Ngày đã chi tiền',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _paidAt = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _paidAt.hour,
        _paidAt.minute,
      );
      if (_submitted) _errors = _validate();
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_paidAt),
      helpText: 'Giờ đã chi tiền',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _paidAt = DateTime(
        _paidAt.year,
        _paidAt.month,
        _paidAt.day,
        picked.hour,
        picked.minute,
      );
      if (_submitted) _errors = _validate();
    });
  }

  Future<void> _pickReceipt() async {
    final picked = await showStockReceiptPicker(context);
    if (picked == null || !mounted) return;
    setState(() {
      _receipt = picked;
      if (_submitted) _errors = _validate();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final submitter = ref.watch(expenseSubmitProvider);
    final categories = ref.watch(cashbookCategoriesProvider);
    final session = ref.watch(authControllerProvider).state.session;
    final canLink = AccessPolicy.canLinkCashbookStockReceipt(session);
    final busy = submitter.submitting;
    final expenseCategories = [
      for (final c in categories.value ?? const <CashbookCategory>[])
        if (c.type == CashbookEntryType.expense && c.active) c,
    ];
    final ingredient =
        _categoryCode == CashbookCategoryCodes.ingredientPurchase;
    final currency = _currency;
    final receipt = _receipt;

    return PopScope(
      canPop: !busy,
      child: CashbookDialogFrame(
        title: 'Ghi nhận khoản chi',
        subtitle:
            'Ghi sổ khoản tiền đã trả cho nhà cung cấp, lương, điện nước…',
        icon: Icons.request_quote_outlined,
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.of(context).pop(),
            child: const Text('Hủy'),
          ),
          FilledButton.icon(
            key: const ValueKey('expense-form-submit'),
            onPressed: busy ? null : _submit,
            icon: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: const Text('Ghi nhận'),
          ),
        ],
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const CashbookNotice(
              message:
                  'Chỉ ghi nhận sau khi đã trả tiền. Hệ thống không thực hiện chuyển khoản.',
            ),
            if (_notice != null) ...[
              const SizedBox(height: 8),
              CashbookNotice(
                message: _notice!,
                tone: CashbookNoticeTone.warning,
              ),
            ],
            if (submitter.failure != null) ...[
              const SizedBox(height: 8),
              CashbookNotice(
                message: submitter.failure!.isNetwork
                    ? '${submitter.failure!.message} Bấm Ghi nhận để thử lại; hệ thống sẽ không tạo trùng.'
                    : submitter.failure!.message,
                tone: CashbookNoticeTone.error,
              ),
            ],
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              key: const ValueKey('expense-form-category'),
              value: expenseCategories.any((c) => c.code == _categoryCode)
                  ? _categoryCode
                  : null,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Danh mục chi *',
                border: const OutlineInputBorder(),
                errorText: _errors['categoryCode'],
                helperText: categories.hasError
                    ? 'Chưa tải được danh mục. Đóng và mở lại form.'
                    : null,
              ),
              items: [
                for (final c in expenseCategories)
                  DropdownMenuItem(value: c.code, child: Text(c.name)),
              ],
              onChanged: busy
                  ? null
                  : (value) => setState(() {
                      _categoryCode = value;
                      if (value != CashbookCategoryCodes.ingredientPurchase) {
                        _receipt = null;
                      }
                      if (_submitted) _errors = _validate();
                    }),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('expense-form-amount'),
              controller: _amount,
              enabled: !busy,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              decoration: InputDecoration(
                labelText: 'Số tiền đã chi *',
                hintText: 'Ví dụ 1.250.000',
                border: const OutlineInputBorder(),
                suffixText: currency ?? 'tiền tệ nhà hàng',
                errorText: _errors['amount'],
              ),
            ),
            const SizedBox(height: 16),
            Text('Phương thức', style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            SegmentedButton<CashbookPaymentMethod>(
              segments: const [
                ButtonSegment(
                  value: CashbookPaymentMethod.cash,
                  icon: Icon(Icons.payments_outlined),
                  label: Text('Tiền mặt'),
                ),
                ButtonSegment(
                  value: CashbookPaymentMethod.transfer,
                  icon: Icon(Icons.account_balance_outlined),
                  label: Text('Chuyển khoản'),
                ),
              ],
              selected: {_method},
              onSelectionChanged: busy
                  ? null
                  : (value) => setState(() => _method = value.first),
            ),
            const SizedBox(height: 16),
            _PaidAtField(
              value: _paidAt,
              zone: _zone,
              error: _errors['expenseAt'],
              onPickDate: busy ? null : _pickDate,
              onPickTime: busy ? null : _pickTime,
            ),
            if (ingredient && canLink) ...[
              const SizedBox(height: 16),
              _ReceiptField(
                receipt: receipt,
                error: _errors['stockDocumentId'],
                onPick: busy ? null : _pickReceipt,
                onClear: busy ? null : () => setState(() => _receipt = null),
                onUseValue: busy || receipt == null
                    ? null
                    : () =>
                          _amount.text = cashbookAmountInput(receipt.totalCost),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _reference,
              enabled: !busy,
              maxLength: ExpenseLimits.referenceNo,
              decoration: InputDecoration(
                labelText: _method == CashbookPaymentMethod.transfer
                    ? 'Mã giao dịch ngân hàng'
                    : 'Mã tham chiếu',
                helperText: _method == CashbookPaymentMethod.transfer
                    ? 'Nên nhập để đối soát sao kê.'
                    : 'Số hóa đơn, biên nhận… (không bắt buộc)',
                border: const OutlineInputBorder(),
                errorText: _errors['referenceNo'],
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _payee,
              enabled: !busy,
              maxLength: ExpenseLimits.payeeName,
              decoration: InputDecoration(
                labelText: 'Người nhận',
                hintText: 'Nhà cung cấp, nhân viên…',
                border: const OutlineInputBorder(),
                errorText: _errors['payeeName'],
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _note,
              enabled: !busy,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: 'Ghi chú',
                border: const OutlineInputBorder(),
                errorText: _errors['note'],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaidAtField extends StatelessWidget {
  const _PaidAtField({
    required this.value,
    required this.zone,
    required this.error,
    required this.onPickDate,
    required this.onPickTime,
  });

  final DateTime value;
  final String? zone;
  final String? error;
  final VoidCallback? onPickDate, onPickTime;

  @override
  Widget build(BuildContext context) {
    String two(int n) => n.toString().padLeft(2, '0');
    return InputDecorator(
      decoration: InputDecoration(
        labelText: 'Thời điểm đã chi *',
        border: const OutlineInputBorder(),
        errorText: error,
        helperText:
            'Giờ ${zone ?? 'thiết bị'}. Có thể chọn ngày trước nếu ghi sổ muộn.',
        helperMaxLines: 2,
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: onPickDate,
            icon: const Icon(Icons.event, size: 18),
            label: Text('${two(value.day)}/${two(value.month)}/${value.year}'),
          ),
          OutlinedButton.icon(
            onPressed: onPickTime,
            icon: const Icon(Icons.schedule, size: 18),
            label: Text('${two(value.hour)}:${two(value.minute)}'),
          ),
        ],
      ),
    );
  }
}

class _ReceiptField extends StatelessWidget {
  const _ReceiptField({
    required this.receipt,
    required this.error,
    required this.onPick,
    required this.onClear,
    required this.onUseValue,
  });

  final CashbookStockReceipt? receipt;
  final String? error;
  final VoidCallback? onPick, onClear, onUseValue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final receipt = this.receipt;
    return InputDecorator(
      decoration: InputDecoration(
        labelText: 'Phiếu nhập liên kết',
        border: const OutlineInputBorder(),
        errorText: error,
        helperText: 'Không bắt buộc. Có thể ghi nhiều lần chi cho một phiếu.',
      ),
      child: receipt == null
          ? Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                key: const ValueKey('expense-form-pick-receipt'),
                onPressed: onPick,
                icon: const Icon(Icons.inventory_2_outlined, size: 18),
                label: const Text('Chọn phiếu nhập'),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${receipt.documentCode} · ${receipt.warehouseName}',
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Bỏ liên kết',
                      onPressed: onClear,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                Text(
                  'Giá trị phiếu: ${receiptMoney(receipt)} · Đã ghi chi: ${receiptRecorded(receipt)}',
                  style: theme.textTheme.bodySmall,
                ),
                if (receipt.currencyUnknown)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Phiếu cũ chưa rõ tiền tệ; khoản chi dùng tiền tệ hiện tại của nhà hàng.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.tertiary,
                      ),
                    ),
                  ),
                TextButton(
                  onPressed: onUseValue,
                  child: const Text('Dùng giá trị phiếu làm số tiền'),
                ),
              ],
            ),
    );
  }
}
