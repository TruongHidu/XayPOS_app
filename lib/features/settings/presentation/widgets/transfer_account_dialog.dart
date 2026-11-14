import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../../../core/ui/widgets/responsive_dialog.dart';
import '../../../../core/values/vietnam_banks.dart';
import '../../../../core/values/vietnamese_text.dart';
import '../../domain/entities/transfer_account.dart';
import '../providers/settings_providers.dart';

/// Adds or edits the receiving bank account; returns the saved account.
class TransferAccountDialog extends ConsumerStatefulWidget {
  const TransferAccountDialog({super.key, this.account});

  /// Null when adding the first account.
  final TransferAccount? account;

  @override
  ConsumerState<TransferAccountDialog> createState() =>
      _TransferAccountDialogState();
}

class _TransferAccountDialogState extends ConsumerState<TransferAccountDialog> {
  final _form = GlobalKey<FormState>();
  final _bankField = GlobalKey<FormFieldState<String>>();
  late String _bin = widget.account?.bankBin ?? '';
  late final _number = TextEditingController(
    text: widget.account?.accountNumber ?? '',
  );
  late final _name = TextEditingController(
    text: widget.account?.accountName ?? '',
  );
  bool _saving = false;
  bool _submitted = false;
  Failure? _failure;

  @override
  void dispose() {
    _number.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickBank() async {
    final bank = await showDialog<VietnamBank>(
      context: context,
      builder: (_) => BankPickerDialog(selectedBin: _bin),
    );
    if (bank == null || !mounted) return;
    setState(() => _bin = bank.bin);
    _bankField.currentState?.didChange(bank.bin);
  }

  Future<void> _save() async {
    if (_saving) return;
    // After the first attempt, errors clear as the owner fixes each field.
    if (!_submitted) setState(() => _submitted = true);
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _failure = null;
    });
    final result = await ref
        .read(transferAccountRepositoryProvider)
        .save(
          TransferAccountDraft(
            bankBin: _bin,
            accountNumber: _number.text,
            accountName: _name.text,
          ),
        );
    if (!mounted) return;
    switch (result) {
      case Success(:final value):
        Navigator.of(context).pop(value);
      case Error(:final failure):
        setState(() {
          _saving = false;
          _failure = failure;
        });
    }
  }

  String? _fieldError(String field) => _failure?.fieldErrors[field];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final normalized = TransferAccountDraft.normalizeAccountName(_name.text);
    final bank = bankByBin(_bin);
    return ResponsiveDialog(
      child: Form(
        key: _form,
        autovalidateMode: _submitted
            ? AutovalidateMode.onUserInteraction
            : AutovalidateMode.disabled,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.account == null
                    ? 'Thêm tài khoản nhận chuyển khoản'
                    : 'Sửa tài khoản nhận chuyển khoản',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Khách quét mã VietQR sẽ chuyển tiền vào tài khoản này.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              FormField<String>(
                key: _bankField,
                initialValue: _bin,
                validator: (_) => TransferAccountDraft.validateBankBin(_bin),
                builder: (field) => InkWell(
                  key: const ValueKey('transfer-account-bank'),
                  onTap: _saving ? null : _pickBank,
                  borderRadius: BorderRadius.circular(4),
                  child: InputDecorator(
                    isEmpty: _bin.isEmpty,
                    decoration: InputDecoration(
                      labelText: 'Ngân hàng',
                      enabled: !_saving,
                      errorText: field.errorText ?? _fieldError('bankBin'),
                      suffixIcon: const Icon(Icons.arrow_drop_down),
                    ),
                    child: _bin.isEmpty
                        ? null
                        : Text(
                            bank == null
                                ? bankLabel(_bin)
                                : '${bank.shortName} · ${bank.name}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _number,
                enabled: !_saving,
                maxLength: TransferAccountDraft.accountNumberMaxLength,
                keyboardType: TextInputType.visiblePassword,
                autocorrect: false,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Số tài khoản',
                  errorText: _fieldError('accountNumber'),
                ),
                validator: TransferAccountDraft.validateAccountNumber,
              ),
              TextFormField(
                controller: _name,
                enabled: !_saving,
                maxLength: TransferAccountDraft.accountNameMaxLength,
                textCapitalization: TextCapitalization.characters,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: 'Tên chủ tài khoản',
                  helperText: normalized.isNotEmpty && normalized != _name.text
                      ? 'Sẽ lưu là: $normalized'
                      : 'Viết như trên thẻ ngân hàng, ví dụ NGUYEN VAN A.',
                  helperMaxLines: 2,
                  errorText: _fieldError('accountName'),
                  errorMaxLines: 2,
                ),
                onChanged: (_) => setState(() {}),
                validator: TransferAccountDraft.validateAccountName,
                onFieldSubmitted: (_) => _save(),
              ),
              if (_failure != null && _failure!.fieldErrors.isEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  _failure!.message,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('Hủy'),
                  ),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Lưu'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Searchable list of [vietnamBanks]; returns the chosen bank.
class BankPickerDialog extends StatefulWidget {
  const BankPickerDialog({super.key, this.selectedBin});

  final String? selectedBin;

  @override
  State<BankPickerDialog> createState() => _BankPickerDialogState();
}

class _BankPickerDialogState extends State<BankPickerDialog> {
  String _query = '';

  static String _fold(String value) =>
      removeVietnameseDiacritics(value).toLowerCase();

  /// Matches the short name, full name or BIN, ignoring diacritics.
  static bool matches(VietnamBank bank, String query) {
    final q = _fold(query.trim());
    if (q.isEmpty) return true;
    return _fold(bank.shortName).contains(q) ||
        _fold(bank.name).contains(q) ||
        bank.bin.contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final banks = [
      for (final bank in vietnamBanks)
        if (matches(bank, _query)) bank,
    ];
    final height = MediaQuery.sizeOf(context).height;
    return ResponsiveDialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: height * 0.75),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Chọn ngân hàng',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('bank-search'),
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Tìm theo tên hoặc mã BIN',
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: banks.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Không tìm thấy ngân hàng phù hợp.'),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: banks.length,
                      itemBuilder: (context, index) {
                        final bank = banks[index];
                        return ListTile(
                          selected: bank.bin == widget.selectedBin,
                          title: Text(bank.shortName),
                          subtitle: Text(bank.name),
                          trailing: bank.bin == widget.selectedBin
                              ? const Icon(Icons.check)
                              : null,
                          onTap: () => Navigator.of(context).pop(bank),
                        );
                      },
                    ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Đóng'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
