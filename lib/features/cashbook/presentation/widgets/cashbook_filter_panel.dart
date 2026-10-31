import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/providers.dart' show authControllerProvider;
import '../../../../core/auth/access_policy.dart';
import '../../../../core/ui/widgets/anchored_overlay.dart';
import '../../../reports/domain/entities/report_date.dart';
import '../../domain/entities/cashbook_filters.dart';
import '../providers/cashbook_providers.dart';
import 'cashbook_format.dart';

/// App bar action that opens the shared range filter as an overlay panel.
class CashbookFilterAction extends ConsumerWidget {
  const CashbookFilterAction({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authControllerProvider).state.session;
    if (!AccessPolicy.canCashbook(session, 'CASHBOOK_VIEW')) {
      return const SizedBox.shrink();
    }
    final filtered = ref.watch(
      cashbookRangeProvider.select((c) => c.isFiltered),
    );
    return IconButton(
      key: const ValueKey('cashbook-filter-action'),
      tooltip: 'Bộ lọc sổ thu chi',
      onPressed: () => _open(context, ref),
      icon: Badge(
        isLabelVisible: filtered,
        smallSize: 8,
        child: const Icon(Icons.filter_alt_outlined),
      ),
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final applied = await showAnchoredPanel<bool>(
      anchorContext: context,
      barrierLabel: 'Đóng bộ lọc',
      child: const CashbookFilterPanel(),
    );
    // Dismissed without applying: drop the unapplied draft.
    if (applied != true && context.mounted) {
      ref.read(cashbookRangeProvider).discardDraft();
    }
  }
}

class CashbookFilterPanel extends ConsumerWidget {
  const CashbookFilterPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(cashbookRangeProvider);
    final today = cashbookToday(c.meta?.timezone);
    final presets = <(String, ReportDateRange)>[
      ('Hôm nay', ReportDateRange.today(today)),
      ('7 ngày qua', ReportDateRange.last7Days(today)),
      ('30 ngày qua', ReportDateRange.last30Days(today)),
      ('Tháng này', ReportDateRange.thisMonth(today)),
      ('Tháng trước', cashbookLastMonth(today)),
    ];
    final range = c.draft.range;
    return OverlayPanel(
      title: 'Bộ lọc sổ thu chi',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Label('Khoảng thời gian'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final (label, preset) in presets)
                ChoiceChip(
                  label: Text(label),
                  selected: range == preset,
                  onSelected: (selected) {
                    if (selected) c.setDraftRange(preset);
                  },
                ),
            ],
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            icon: const Icon(Icons.date_range, size: 18),
            label: Text(
              '${cashbookRangeLabel(range)} (${range.inclusiveDays} ngày)',
            ),
            onPressed: () => _pickRange(context, ref, range, today),
          ),
          const SizedBox(height: 4),
          Text(
            'Theo ngày của nhà hàng, tối đa 366 ngày.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 20),
          const _Label('Tiền tệ'),
          const SizedBox(height: 8),
          _CurrencyField(
            initial: c.draft.currencyCode ?? '',
            hint: c.meta?.currencyCode ?? 'VND',
            onChanged: c.setDraftCurrency,
          ),
          if (c.validationError != null) ...[
            const SizedBox(height: 8),
            Text(
              c.validationError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    c.reset();
                    Navigator.of(context).pop(true);
                  },
                  child: const Text('Đặt lại'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  key: const ValueKey('cashbook-filter-apply'),
                  icon: const Icon(Icons.filter_alt, size: 18),
                  label: const Text('Áp dụng'),
                  onPressed: () {
                    if (c.apply()) Navigator.of(context).pop(true);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pickRange(
    BuildContext context,
    WidgetRef ref,
    ReportDateRange range,
    ReportDate today,
  ) async {
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(
        start: range.fromDate.toDateTime(),
        end: range.toDate.toDateTime(),
      ),
      firstDate: DateTime(2020),
      lastDate: today.toDateTime(),
    );
    if (picked == null) return;
    ref
        .read(cashbookRangeProvider)
        .setDraftRange(
          ReportDateRange(
            fromDate: ReportDate.fromDateTime(picked.start),
            toDate: ReportDate.fromDateTime(picked.end),
          ),
        );
  }
}

class _CurrencyField extends StatefulWidget {
  const _CurrencyField({
    required this.initial,
    required this.hint,
    required this.onChanged,
  });
  final String initial, hint;
  final ValueChanged<String> onChanged;

  @override
  State<_CurrencyField> createState() => _CurrencyFieldState();
}

class _CurrencyFieldState extends State<_CurrencyField> {
  late final _text = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _text,
    maxLength: 3,
    textCapitalization: TextCapitalization.characters,
    decoration: InputDecoration(
      isDense: true,
      border: const OutlineInputBorder(),
      hintText: widget.hint,
      helperText: 'Để trống để dùng tiền tệ hiện tại của nhà hàng.',
      counterText: '',
    ),
    onChanged: widget.onChanged,
  );
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(
      context,
    ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
  );
}
