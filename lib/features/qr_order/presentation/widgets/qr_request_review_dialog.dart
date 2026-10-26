import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../order/presentation/widgets/order_widgets.dart';
import '../../domain/entities/qr_request.dart';
import '../../domain/entities/qr_request_messages.dart';
import '../providers/qr_request_providers.dart';
import '../controllers/qr_review_controller.dart';
import 'qr_request_format.dart';

class QrRequestReviewDialog extends ConsumerStatefulWidget {
  const QrRequestReviewDialog({
    super.key,
    required this.id,
    required this.tableName,
  });
  final String id, tableName;
  @override
  ConsumerState<QrRequestReviewDialog> createState() =>
      _QrRequestReviewDialogState();
}

class _QrRequestReviewDialogState extends ConsumerState<QrRequestReviewDialog> {
  final _reason = TextEditingController();
  bool _confirmed = false, _rejecting = false;
  QrRequestReview? _baseline;
  QrReviewController? _controller;
  @override
  void dispose() {
    _controller?.stopVisibleTimers();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(qrReviewProvider(widget.id));
    _controller = c;
    final review = c.review;
    if (!identical(_baseline, review)) {
      _baseline = review;
      _confirmed = false;
      _rejecting = false;
    }
    final row = review?.request;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return PopScope(
      canPop: !c.busy && !c.uncertain,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 760,
            maxHeight: MediaQuery.sizeOf(context).height * .9,
          ),
          child: Column(
            children: [
              // ── Header ──
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                child: Row(
                  children: [
                    Icon(Icons.qr_code_2, color: colors.primary, size: 28),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'QR · ${widget.tableName}',
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                    if (row != null)
                      _StatusChip(status: row.status),
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: 'Đóng chi tiết QR',
                      onPressed: c.busy || c.uncertain
                          ? null
                          : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              if (c.loading || c.busy) const LinearProgressIndicator(),

              // ── Body ──
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  children: [
                    if (row != null) ...[
                      // ── Info card ──
                      _SectionCard(
                        icon: Icons.info_outline,
                        title: 'Thông tin yêu cầu',
                        children: [
                          _InfoRow(
                            icon: Icons.tag,
                            label: 'Mã',
                            value: shortQrId(row.id),
                          ),
                          _InfoRow(
                            icon: Icons.schedule,
                            label: 'Gửi lúc',
                            value: qrRequestTime(row.createdAt),
                          ),
                          _InfoRow(
                            icon: Icons.timer_outlined,
                            label: 'Hạn duyệt',
                            value: qrRequestTime(row.expiresAt),
                          ),
                          if (row.customerName?.isNotEmpty == true)
                            _InfoRow(
                              icon: Icons.person_outline,
                              label: 'Khách',
                              value: row.customerName!,
                            ),
                          if (row.customerPhone?.isNotEmpty == true)
                            _InfoRow(
                              icon: Icons.phone_outlined,
                              label: 'SĐT',
                              value: row.customerPhone!,
                            ),
                          if (row.note?.isNotEmpty == true)
                            _InfoRow(
                              icon: Icons.notes,
                              label: 'Ghi chú',
                              value: row.note!,
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // ── Items card ──
                      _SectionCard(
                        icon: Icons.restaurant_menu,
                        title: 'Món khách yêu cầu (${row.items.length})',
                        children: [
                          for (final line in row.items)
                            _ItemTile(line: line, currency: row.currency),
                          const Divider(height: 1),
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Giá lúc gửi',
                                  style: theme.textTheme.titleSmall,
                                ),
                                Text(
                                  _money(row.estimatedAmount.minorUnits, row.currency),
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      // ── Quote card (current price) ──
                      if (review!.quote != null) ...[
                        const SizedBox(height: 12),
                        _SectionCard(
                          icon: Icons.receipt_long,
                          title: 'Giá hiện tại khi duyệt',
                          borderColor: review.quoteChanged
                              ? colors.error.withValues(alpha: .5)
                              : null,
                          children: [
                            for (final line in review.quote!.lines)
                              _ItemTile(
                                line: line,
                                currency: review.quote!.currency,
                              ),
                            const Divider(height: 1),
                            Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Tổng duyệt',
                                    style: theme.textTheme.titleSmall,
                                  ),
                                  Text(
                                    _money(
                                      review.quote!.amount.minorUnits,
                                      review.quote!.currency,
                                    ),
                                    style:
                                        theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: review.quoteChanged
                                          ? colors.error
                                          : null,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (review.quoteChanged) ...[
                              const SizedBox(height: 8),
                              _WarningBanner(
                                icon: Icons.price_change,
                                message:
                                    'Giá đã thay đổi so với lúc khách gửi. Hãy đối chiếu với khách trước khi duyệt.',
                              ),
                            ],
                          ],
                        ),
                      ],

                      // ── Pending-specific actions ──
                      if (row.status == QrRequestStatus.pending) ...[
                        const SizedBox(height: 12),

                        // Context info card
                        _SectionCard(
                          icon: Icons.table_restaurant,
                          title: 'Thao tác khi duyệt',
                          children: [
                            _InfoRow(
                              icon: Icons.play_circle_outline,
                              label: 'Hành động',
                              value: review.context?.sessionId == null
                                  ? 'Mở phiên bàn mới và tạo đơn'
                                  : review.context?.order == null
                                      ? 'Tạo đơn cho phiên bàn hiện tại'
                                      : 'Thêm món vào đơn hiện tại (giữ món cũ)',
                            ),
                            if (review.context?.sessionId != null)
                              _InfoRow(
                                icon: Icons.groups_outlined,
                                label: 'Phiên bàn',
                                value:
                                    '${widget.tableName}${review.context!.guestCount == null ? '' : ' · ${review.context!.guestCount} khách'}',
                              ),
                            if (review.context?.order != null)
                              _InfoRow(
                                icon: Icons.receipt_outlined,
                                label: 'Đơn hiện tại',
                                value:
                                    '${review.context!.order!.status.label} · ${_money(review.context!.order!.total.minorUnits, review.context!.order!.currency)}',
                              ),
                          ],
                        ),

                        // Warnings
                        if (row.observedSessionId == null &&
                            review.context?.sessionId != null) ...[
                          const SizedBox(height: 8),
                          _WarningBanner(
                            icon: Icons.warning_amber,
                            message:
                                'Khi khách gửi chưa có phiên bàn. Cần xác nhận yêu cầu này thuộc đúng lượt khách hiện tại.',
                          ),
                        ],
                        if (!c.pending) ...[
                          const SizedBox(height: 8),
                          _WarningBanner(
                            icon: Icons.timer_off,
                            message:
                                'Yêu cầu đã hết hạn, không thể duyệt.',
                            isError: true,
                          ),
                        ],
                        if (!review.canApprove ||
                            review.reasonCode != null) ...[
                          const SizedBox(height: 8),
                          _WarningBanner(
                            icon: Icons.block,
                            message: qrReviewReason(review.reasonCode),
                            isError: true,
                          ),
                        ],
                        if (c.localBlocked) ...[
                          const SizedBox(height: 8),
                          _WarningBanner(
                            icon: Icons.lock_outline,
                            message:
                                'Đơn hoặc phiên bàn đang có thao tác khác cần xử lý. Hãy kiểm tra lại sau.',
                          ),
                        ],
                        if (!c.canApprove &&
                            review.canApprove &&
                            !c.busy &&
                            !c.loading &&
                            !c.needsReload &&
                            c.pending &&
                            !c.localBlocked) ...[
                          const SizedBox(height: 8),
                          _WarningBanner(
                            icon: Icons.no_accounts,
                            message:
                                'Bạn chưa có đủ quyền hoặc tính năng để duyệt yêu cầu này.',
                            isError: true,
                          ),
                        ],

                        // ── Confirm switch (replaces checkbox) ──
                        if (!_rejecting) ...[
                          const SizedBox(height: 12),
                          Card(
                            color: _confirmed
                                ? colors.primaryContainer
                                : colors.surfaceContainerHighest,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: _confirmed
                                    ? colors.primary
                                    : colors.outlineVariant,
                                width: _confirmed ? 1.5 : 1,
                              ),
                            ),
                            child: SwitchListTile.adaptive(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              value: _confirmed,
                              onChanged: c.canApprove
                                  ? (v) =>
                                      setState(() => _confirmed = v)
                                  : null,
                              secondary: Icon(
                                _confirmed
                                    ? Icons.check_circle
                                    : Icons.circle_outlined,
                                color: _confirmed
                                    ? colors.primary
                                    : colors.outline,
                              ),
                              title: Text(
                                review.context?.sessionId == null
                                    ? 'Đã kiểm tra món, giá và đúng khách; đồng ý mở phiên'
                                    : 'Đã kiểm tra món, giá và đúng phiên bàn',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],

                        // ── Reject reason ──
                        if (_rejecting) ...[
                          const SizedBox(height: 12),
                          TextField(
                            controller: _reason,
                            enabled: !c.busy,
                            minLines: 2,
                            maxLines: 4,
                            maxLength: 1000,
                            decoration: const InputDecoration(
                              labelText: 'Lý do từ chối',
                              hintText: 'Ví dụ: món đã hết, khách đổi ý',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ],
                      ],

                      if (row.rejectionReason != null) ...[
                        const SizedBox(height: 8),
                        _WarningBanner(
                          icon: Icons.do_not_disturb,
                          message:
                              'Lý do từ chối: ${row.rejectionReason}',
                          isError: true,
                        ),
                      ],
                      if (row.cancellationReason != null) ...[
                        const SizedBox(height: 8),
                        _WarningBanner(
                          icon: Icons.cancel_outlined,
                          message:
                              'Lý do hủy: ${qrReviewReason(row.cancellationReason)}',
                          isError: true,
                        ),
                      ],
                    ],

                    // ── Uncertain / reload ──
                    if (c.uncertain) ...[
                      const SizedBox(height: 8),
                      _WarningBanner(
                        icon: Icons.help_outline,
                        message:
                            'Chưa xác định kết quả. Tải lại đúng yêu cầu này để kiểm tra; không gửi lại hoặc tạo đơn thay thế.',
                        isError: true,
                      ),
                    ],
                    if (c.needsReload && !c.uncertain) ...[
                      const SizedBox(height: 8),
                      _WarningBanner(
                        icon: Icons.sync_problem,
                        message:
                            'Hãy tải lại yêu cầu, kiểm tra thay đổi rồi xác nhận lại trước khi gửi.',
                      ),
                    ],
                    OrderFailurePanel(failure: c.failure),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: c.busy || c.loading || c.coolingDown
                          ? null
                          : c.load,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Tải lại yêu cầu QR'),
                    ),
                  ],
                ),
              ),

              // ── Bottom action bar ──
              Container(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: colors.outlineVariant, width: .5),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Reject button row
                    if (row?.status == QrRequestStatus.pending) ...[
                      if (_rejecting) ...[
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: c.busy
                                    ? null
                                    : () => setState(
                                        () => _rejecting = false),
                                icon: const Icon(Icons.arrow_back),
                                label: const Text('Quay lại'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: !c.canReject
                                    ? null
                                    : () async {
                                        final success = await c.reject(
                                          review!,
                                          _reason.text,
                                        );
                                        if (success &&
                                            context.mounted &&
                                            c.current) {
                                          Navigator.of(context).pop();
                                        }
                                      },
                                icon: const Icon(Icons.close),
                                label: const Text('Xác nhận từ chối'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: colors.error,
                                  foregroundColor: colors.onError,
                                  minimumSize:
                                      const Size.fromHeight(48),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ] else ...[
                        // Approve button (full width, prominent)
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: FilledButton.icon(
                            onPressed: !c.canApprove || !_confirmed
                                ? null
                                : () async {
                                    final success = await c.approve(
                                      review!,
                                      confirmed: _confirmed,
                                    );
                                    if (success &&
                                        context.mounted &&
                                        c.current) {
                                      Navigator.of(context).pop();
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Đã duyệt yêu cầu QR và cập nhật đơn.',
                                          ),
                                        ),
                                      );
                                    }
                                  },
                            icon: const Icon(Icons.check_circle, size: 22),
                            label: const Text(
                              'Duyệt yêu cầu',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          height: 44,
                          child: OutlinedButton.icon(
                            onPressed: !c.canReject
                                ? null
                                : () =>
                                    setState(() => _rejecting = true),
                            icon: Icon(
                              Icons.block,
                              size: 18,
                              color: c.canReject
                                  ? colors.error
                                  : null,
                            ),
                            label: Text(
                              'Từ chối yêu cầu',
                              style: TextStyle(
                                color: c.canReject
                                    ? colors.error
                                    : null,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(
                                color: c.canReject
                                    ? colors.error.withValues(alpha: .5)
                                    : colors.outlineVariant,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Private helpers
// ─────────────────────────────────────────────────────────────────────────────

String _money(int minor, String currency) =>
    orderMoney(BigInt.from(minor), currency: currency);

/// Status chip shown in the dialog header.
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final QrRequestStatus status;

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg) = switch (status) {
      QrRequestStatus.pending => (
          Theme.of(context).colorScheme.tertiaryContainer,
          Theme.of(context).colorScheme.onTertiaryContainer,
        ),
      QrRequestStatus.approved => (
          const Color(0xFF16A34A),
          Colors.white,
        ),
      QrRequestStatus.rejected => (
          Theme.of(context).colorScheme.errorContainer,
          Theme.of(context).colorScheme.onErrorContainer,
        ),
      QrRequestStatus.cancelled => (
          Theme.of(context).colorScheme.surfaceContainerHighest,
          Theme.of(context).colorScheme.onSurfaceVariant,
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: fg,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// A card that groups a section with an icon + title header.
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.children,
    this.borderColor,
  });
  final IconData icon;
  final String title;
  final List<Widget> children;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: borderColor ?? colors.outlineVariant,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: colors.primary),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// A label-value row with an icon, used inside _SectionCard.
class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label, value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: Theme.of(context).colorScheme.outline),
        const SizedBox(width: 6),
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    ),
  );
}

/// An item tile used inside the items section card.
class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.line, required this.currency});
  final QrRequestLine line;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Quantity badge
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.secondaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${line.quantity}',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: colors.onSecondaryContainer,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${line.name} (${line.unit})',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  '${_money(line.unitPrice.minorUnits, currency)} × ${line.quantity} = ${_money(line.total.minorUnits, currency)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                if (line.note?.isNotEmpty == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      children: [
                        Icon(Icons.sticky_note_2_outlined,
                            size: 13, color: colors.outline),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            line.note!,
                            style: TextStyle(
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
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

/// A colored banner for warnings and errors.
class _WarningBanner extends StatelessWidget {
  const _WarningBanner({
    required this.icon,
    required this.message,
    this.isError = false,
  });
  final IconData icon;
  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final bg =
        isError ? colors.errorContainer : colors.tertiaryContainer;
    final fg = isError
        ? colors.onErrorContainer
        : colors.onTertiaryContainer;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 13, color: fg),
            ),
          ),
        ],
      ),
    );
  }
}

String qrReviewReason(String? code) =>
    qrRequestMessage(code) ??
    switch (code) {
      'ORDER_HAS_FINANCIAL_OBLIGATIONS' =>
        'Bàn đang thanh toán hoặc đã có nghĩa vụ thanh toán; không nhận thêm món.',
      _ =>
        code == null
            ? 'Yêu cầu hiện chưa đủ điều kiện duyệt.'
            : 'Chưa thể xử lý yêu cầu ($code).',
    };
