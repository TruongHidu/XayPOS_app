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
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'QR · ${widget.tableName}',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
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
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    if (row != null) ...[
                      Text(
                        row.status.label,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Yêu cầu ${shortQrId(row.id)} · ${qrRequestTime(row.createdAt)}',
                      ),
                      Text('Hạn duyệt: ${qrRequestTime(row.expiresAt)}'),
                      if (row.customerName?.isNotEmpty == true)
                        Text('Khách: ${row.customerName}'),
                      if (row.customerPhone?.isNotEmpty == true)
                        Text('Điện thoại: ${row.customerPhone}'),
                      if (row.note?.isNotEmpty == true)
                        Text('Ghi chú: ${row.note}'),
                      const SizedBox(height: 16),
                      const Text(
                        'Món khách yêu cầu',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      for (final line in row.items)
                        _Line(line: line, currency: row.currency),
                      Text(
                        'Giá lúc gửi: ${_money(row.estimatedAmount.minorUnits, row.currency)}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      if (review!.quote != null) ...[
                        const Divider(height: 24),
                        const Text(
                          'Giá hiện tại khi duyệt',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        for (final line in review.quote!.lines)
                          _Line(line: line, currency: review.quote!.currency),
                        Text(
                          'Tổng duyệt: ${_money(review.quote!.amount.minorUnits, review.quote!.currency)}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        if (review.quoteChanged)
                          const Text(
                            'Giá đã thay đổi so với lúc khách gửi. Hãy đối chiếu với khách trước khi duyệt.',
                          ),
                      ],
                      if (row.status == QrRequestStatus.pending) ...[
                        const Divider(height: 24),
                        Text(
                          review.context?.sessionId == null
                              ? 'Duyệt yêu cầu sẽ mở phiên bàn và tạo đơn mới.'
                              : review.context?.order == null
                              ? 'Duyệt yêu cầu sẽ tạo đơn cho phiên bàn hiện tại.'
                              : 'Duyệt yêu cầu sẽ thêm món vào đơn hiện tại; các món cũ được giữ nguyên.',
                        ),
                        if (review.context?.sessionId != null)
                          Text(
                            'Phiên đang phục vụ tại ${widget.tableName}${review.context!.guestCount == null ? '' : ' · ${review.context!.guestCount} khách'}',
                          ),
                        if (review.context?.order != null)
                          Text(
                            'Đơn hiện tại: ${review.context!.order!.status.label} · ${_money(review.context!.order!.total.minorUnits, review.context!.order!.currency)}',
                          ),
                        if (row.observedSessionId == null &&
                            review.context?.sessionId != null)
                          const Text(
                            'Khi khách gửi chưa có phiên bàn. Cần xác nhận yêu cầu này thuộc đúng lượt khách hiện tại.',
                          ),
                        if (!c.pending)
                          const Text('Yêu cầu đã hết hạn, không thể duyệt.'),
                        if (!review.canApprove || review.reasonCode != null)
                          Text(qrReviewReason(review.reasonCode)),
                        if (c.localBlocked)
                          const Text(
                            'Đơn hoặc phiên bàn đang có thao tác khác cần xử lý. Hãy kiểm tra lại sau.',
                          ),
                        if (!c.canApprove &&
                            review.canApprove &&
                            !c.busy &&
                            !c.loading &&
                            !c.needsReload &&
                            c.pending &&
                            !c.localBlocked)
                          const Text(
                            'Bạn chưa có đủ quyền hoặc tính năng để duyệt yêu cầu này.',
                          ),
                        if (!_rejecting)
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            value: _confirmed,
                            onChanged: c.canApprove
                                ? (v) => setState(() => _confirmed = v ?? false)
                                : null,
                            title: Text(
                              review.context?.sessionId == null
                                  ? 'Tôi đã kiểm tra món, giá và đúng khách tại bàn; đồng ý mở phiên để nhận yêu cầu.'
                                  : 'Tôi đã kiểm tra món, giá và chọn đúng phiên bàn ở trên để nhận yêu cầu này.',
                            ),
                          ),
                        if (_rejecting)
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
                      if (row.rejectionReason != null)
                        Text('Lý do từ chối: ${row.rejectionReason}'),
                      if (row.cancellationReason != null)
                        Text(
                          'Lý do hủy: ${qrReviewReason(row.cancellationReason)}',
                        ),
                    ],
                    if (c.uncertain)
                      const Text(
                        'Chưa xác định kết quả. Tải lại đúng yêu cầu này để kiểm tra; không gửi lại hoặc tạo đơn thay thế.',
                      ),
                    if (c.needsReload && !c.uncertain)
                      const Text(
                        'Hãy tải lại yêu cầu, kiểm tra thay đổi rồi xác nhận lại trước khi gửi.',
                      ),
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
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (_rejecting)
                      TextButton(
                        onPressed: c.busy
                            ? null
                            : () => setState(() => _rejecting = false),
                        child: const Text('Quay lại'),
                      ),
                    if (row?.status == QrRequestStatus.pending)
                      OutlinedButton(
                        onPressed: !c.canReject
                            ? null
                            : () async {
                                if (!_rejecting) {
                                  setState(() => _rejecting = true);
                                  return;
                                }
                                final success = await c.reject(
                                  review!,
                                  _reason.text,
                                );
                                if (success && context.mounted && c.current) {
                                  Navigator.of(context).pop();
                                }
                              },
                        child: Text(
                          _rejecting ? 'Xác nhận từ chối' : 'Từ chối',
                        ),
                      ),
                    if (!_rejecting && row?.status == QrRequestStatus.pending)
                      FilledButton(
                        onPressed: !c.canApprove || !_confirmed
                            ? null
                            : () async {
                                final success = await c.approve(
                                  review!,
                                  confirmed: _confirmed,
                                );
                                if (success && context.mounted && c.current) {
                                  Navigator.of(context).pop();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Đã duyệt yêu cầu QR và cập nhật đơn.',
                                      ),
                                    ),
                                  );
                                }
                              },
                        child: const Text('Duyệt yêu cầu'),
                      ),
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

String _money(int minor, String currency) =>
    orderMoney(BigInt.from(minor), currency: currency);

class _Line extends StatelessWidget {
  const _Line({required this.line, required this.currency});
  final QrRequestLine line;
  final String currency;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${line.quantity} ${line.unit} · ${line.name}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        Text(
          'Đơn giá ${_money(line.unitPrice.minorUnits, currency)} · Thành tiền ${_money(line.total.minorUnits, currency)}',
        ),
        if (line.note?.isNotEmpty == true) Text('Ghi chú món: ${line.note}'),
      ],
    ),
  );
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
