import 'package:flutter/material.dart';

import '../../../order/domain/entities/order_entities.dart' show ServiceType;
import '../../domain/entities/report_date.dart';
import '../../domain/entities/report_enums.dart';

class DailyReportFilterBar extends StatelessWidget {
  final ReportDate? selectedDate;
  final String? currencyCode;
  final ServiceType? serviceType;
  final ReportSourceChannel? sourceChannel;
  final ValueChanged<ReportDate?> onDateChanged;
  final ValueChanged<String?> onCurrencyChanged;
  final ValueChanged<ServiceType?> onServiceTypeChanged;
  final ValueChanged<ReportSourceChannel?> onSourceChannelChanged;
  final VoidCallback onApply;
  final VoidCallback onReset;
  final VoidCallback onRefresh;
  final bool isLoading;

  const DailyReportFilterBar({
    super.key,
    required this.selectedDate,
    required this.currencyCode,
    required this.serviceType,
    required this.sourceChannel,
    required this.onDateChanged,
    required this.onCurrencyChanged,
    required this.onServiceTypeChanged,
    required this.onSourceChannelChanged,
    required this.onApply,
    required this.onReset,
    required this.onRefresh,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.spaceBetween,
          children: [
            // Left filters
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // Date Button
                OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today, size: 18),
                  label: Text(
                    selectedDate != null
                        ? selectedDate!.formatDisplay()
                        : 'Hôm nay (mặc định)',
                  ),
                  onPressed: () async {
                    final now = DateTime.now();
                    final initial = selectedDate?.toDateTime() ?? now;
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: initial,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      onDateChanged(ReportDate.fromDateTime(picked));
                    }
                  },
                ),
                // Service Type Dropdown
                _ReportFilterDropdown<ServiceType?>(
                  value: serviceType,
                  hint: const Text('Loại phục vụ: Tất cả'),
                  items: const [
                    DropdownMenuItem(
                      value: null,
                      child: Text('Loại phục vụ: Tất cả'),
                    ),
                    DropdownMenuItem(
                      value: ServiceType.dineIn,
                      child: Text('Ăn tại bàn'),
                    ),
                    DropdownMenuItem(
                      value: ServiceType.takeaway,
                      child: Text('Mang đi'),
                    ),
                  ],
                  onChanged: onServiceTypeChanged,
                ),
                // Source Channel Dropdown
                _ReportFilterDropdown<ReportSourceChannel?>(
                  value: sourceChannel,
                  hint: const Text('Kênh tạo: Tất cả'),
                  items: const [
                    DropdownMenuItem(
                      value: null,
                      child: Text('Kênh tạo: Tất cả'),
                    ),
                    DropdownMenuItem(
                      value: ReportSourceChannel.cashier,
                      child: Text('Thu ngân'),
                    ),
                    DropdownMenuItem(
                      value: ReportSourceChannel.waiter,
                      child: Text('Phục vụ'),
                    ),
                    DropdownMenuItem(
                      value: ReportSourceChannel.qrStatic,
                      child: Text('QR tĩnh'),
                    ),
                    DropdownMenuItem(
                      value: ReportSourceChannel.qrTable,
                      child: Text('QR bàn'),
                    ),
                  ],
                  onChanged: onSourceChannelChanged,
                ),
              ],
            ),
            // Right action buttons
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: onReset,
                  child: const Text('Đặt lại'),
                ),
                FilledButton.icon(
                  icon: isLoading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.filter_alt, size: 18),
                  label: const Text('Áp dụng'),
                  onPressed: isLoading ? null : onApply,
                ),
                IconButton(
                  tooltip: 'Tải lại',
                  icon: const Icon(Icons.refresh),
                  onPressed: isLoading ? null : onRefresh,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportFilterDropdown<T> extends StatelessWidget {
  const _ReportFilterDropdown({
    required this.value,
    required this.hint,
    required this.items,
    required this.onChanged,
  });

  final T? value;
  final Widget hint;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 280 * textScale.clamp(1.0, double.infinity),
      ),
      child: DropdownButton<T>(
        value: value,
        hint: hint,
        isExpanded: true,
        itemHeight: null,
        items: items,
        onChanged: onChanged,
      ),
    );
  }
}
