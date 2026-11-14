import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/values/vietnam_banks.dart';
import '../../domain/entities/order_transfer_qr.dart';
import '../providers/order_transfer_qr_providers.dart';
import 'order_widgets.dart';

/// The VietQR a customer scans to pay by transfer, with what it encodes.
/// Display only: confirming the money arrived stays a manual step.
class TransferQrPanel extends ConsumerWidget {
  const TransferQrPanel({
    super.key,
    required this.qrKey,
    required this.dueMinor,
  });

  final OrderTransferQrKey qrKey;

  /// What the dialog asks the cashier to collect; a code for another amount
  /// gets a warning.
  final BigInt dueMinor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final qr = ref.watch(orderTransferQrProvider(qrKey));
    final theme = Theme.of(context);
    return switch (qr) {
      AsyncValue(:final error?, hasValue: false) => _Notice(
        key: const ValueKey('transfer-qr-error'),
        icon: Icons.error_outline,
        color: theme.colorScheme.error,
        text: error is Failure
            ? error.message
            : 'Chưa tải được mã QR chuyển khoản.',
        action: TextButton(
          onPressed: () => ref.invalidate(orderTransferQrProvider(qrKey)),
          child: const Text('Thử lại'),
        ),
      ),
      AsyncValue(hasValue: true, value: null) => _Notice(
        key: const ValueKey('transfer-qr-not-configured'),
        icon: Icons.info_outline,
        color: theme.colorScheme.onSurfaceVariant,
        text:
            'Nhà hàng chưa cài tài khoản nhận chuyển khoản nên chưa có mã QR. '
            'Vẫn nhận chuyển khoản và ghi mã tham chiếu như bình thường.',
      ),
      AsyncValue(hasValue: true, value: final OrderTransferQrCode code) =>
        _QrContent(code: code, dueMinor: dueMinor),
      _ => const _Notice(
        key: ValueKey('transfer-qr-loading'),
        icon: null,
        text: 'Đang tạo mã QR chuyển khoản…',
      ),
    };
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    super.key,
    required this.icon,
    required this.text,
    this.color,
    this.action,
  });

  final IconData? icon;
  final String text;
  final Color? color;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (icon == null)
                const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(icon, size: 20, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(text, style: TextStyle(color: color)),
              ),
            ],
          ),
          if (action != null)
            Align(alignment: Alignment.centerRight, child: action),
        ],
      ),
    );
  }
}

class _QrContent extends StatelessWidget {
  const _QrContent({required this.code, required this.dueMinor});

  final OrderTransferQrCode code;
  final BigInt dueMinor;

  /// From this width the code sits beside its details instead of above.
  static const _sideBySide = 420.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final qr = code.details;
    final amount = orderMoney(
      BigInt.from(qr.amount.minorUnits),
      currency: qr.currencyCode,
    );
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _Line('Ngân hàng', bankLabel(qr.bankBin)),
        _Line('Số tài khoản', qr.accountNumber, copyable: true),
        _Line('Chủ tài khoản', qr.accountName),
        _Line('Số tiền', amount, strong: true),
        _Line('Nội dung', qr.transferContent, copyable: true, strong: true),
      ],
    );
    return Container(
      key: const ValueKey('transfer-qr'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.grey50,
        border: Border.all(color: AppColors.grey200),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= _sideBySide;
              final size = wide ? 176.0 : math.min(220.0, constraints.maxWidth);
              final picture = Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Semantics(
                    button: true,
                    label: 'Phóng to mã QR cho khách quét',
                    child: InkWell(
                      key: const ValueKey('transfer-qr-image'),
                      onTap: () => showTransferQrFullScreen(context, code),
                      borderRadius: BorderRadius.circular(10),
                      child: _QrPicture(png: code.png, size: size),
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: size,
                    child: Text(
                      'Chạm vào mã để phóng to cho khách quét.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.grey600,
                      ),
                    ),
                  ),
                ],
              );
              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    picture,
                    const SizedBox(width: 16),
                    Expanded(child: details),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(child: picture),
                  const SizedBox(height: 12),
                  details,
                ],
              );
            },
          ),
          if (BigInt.from(qr.amount.minorUnits) != dueMinor)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Số tiền trong mã QR khác số cần thu. Hãy tải lại đơn trước '
                'khi cho khách quét.',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
        ],
      ),
    );
  }
}

/// A QR needs a light quiet zone to scan, whatever the app theme.
class _QrPicture extends StatelessWidget {
  const _QrPicture({required this.png, required this.size});

  final Uint8List png;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Image.memory(
      png,
      fit: BoxFit.contain,
      gaplessPlayback: true,
      filterQuality: FilterQuality.none,
      semanticLabel: 'Mã VietQR chuyển khoản',
    ),
  );
}

/// One labelled detail; the label column stays aligned and the value wraps.
/// Values a customer may type by hand can be copied.
class _Line extends StatelessWidget {
  const _Line(
    this.label,
    this.value, {
    this.copyable = false,
    this.strong = false,
  });

  final String label;
  final String value;
  final bool copyable, strong;

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Đã sao chép $label.')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 104,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.grey600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: strong ? FontWeight.w700 : FontWeight.w600,
                color: strong ? AppColors.grey900 : AppColors.grey800,
              ),
            ),
          ),
          if (copyable)
            IconButton(
              tooltip: 'Sao chép $label',
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              onPressed: () => _copy(context),
              icon: const Icon(Icons.copy_rounded, color: AppColors.grey600),
            ),
        ],
      ),
    );
  }
}

/// Shows the code as large as the screen allows, turned towards the
/// customer. Tap anywhere or Đóng to go back.
Future<void> showTransferQrFullScreen(
  BuildContext context,
  OrderTransferQrCode code,
) => showDialog<void>(
  context: context,
  builder: (context) {
    final qr = code.details;
    const ink = TextStyle(color: AppColors.grey900);
    return Dialog.fullscreen(
      key: const ValueKey('transfer-qr-fullscreen'),
      backgroundColor: Colors.white,
      child: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(context).pop(),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) => Center(
                      child: _QrPicture(
                        png: code.png,
                        size: math.min(
                          constraints.maxWidth,
                          constraints.maxHeight,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  orderMoney(
                    BigInt.from(qr.amount.minorUnits),
                    currency: qr.currencyCode,
                  ),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: AppColors.grey900,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${bankLabel(qr.bankBin)} · ${qr.accountNumber} · '
                  '${qr.accountName}',
                  textAlign: TextAlign.center,
                  style: ink,
                ),
                Text(
                  'Nội dung: ${qr.transferContent}',
                  textAlign: TextAlign.center,
                  style: ink,
                ),
                const SizedBox(height: 8),
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Đóng'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  },
);
