import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

import '../../errors/failure.dart';
import '../../network/binary_download.dart';
import '../../platform/external_link_opener.dart';
import '../../platform/file_exporter.dart';

/// Which QR picture the API renders: the printable A6 card or the bare code.
enum QrPicture { card, image }

/// Preview of a server-rendered QR (card or bare code) with save/share and
/// the customer-facing link. [source] picks the provider for each picture so
/// a new token (new provider key) reloads the picture by itself.
class QrPreview extends ConsumerStatefulWidget {
  const QrPreview({
    super.key,
    required this.source,
    required this.onRetry,
    this.menuUrl,
    this.maxCardHeight = 360,
  });

  final ProviderListenable<AsyncValue<DownloadedFile>> Function(QrPicture)
  source;
  final void Function(QrPicture) onRetry;
  final String? menuUrl;
  final double maxCardHeight;

  @override
  ConsumerState<QrPreview> createState() => _QrPreviewState();
}

class _QrPreviewState extends ConsumerState<QrPreview> {
  QrPicture _picture = QrPicture.card;
  bool _exporting = false;

  Future<void> _export(DownloadedFile file) async {
    final exporter = ref.read(fileExporterProvider);
    final box = context.findRenderObject() as RenderBox?;
    final origin = box != null && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    setState(() => _exporting = true);
    try {
      final done = await exporter.export(file, origin: origin);
      if (done && exporter.mode == FileExportMode.download && mounted) {
        _notice('Đã lưu ${file.fileName}.');
      }
    } on Object {
      if (mounted) _notice('Không lưu được tệp. Vui lòng thử lại.');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _copy(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (mounted) _notice('Đã sao chép đường dẫn.');
  }

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    var opened = false;
    if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http')) {
      try {
        opened = await ref.read(externalLinkOpenerProvider)(uri);
      } on Object {
        opened = false;
      }
    }
    if (!opened && mounted) _notice('Không mở được liên kết.');
  }

  void _notice(String message) => ScaffoldMessenger.maybeOf(
    context,
  )?.showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final file = ref.watch(widget.source(_picture));
    final card = _picture == QrPicture.card;
    final share = ref.watch(fileExporterProvider).mode == FileExportMode.share;
    final url = widget.menuUrl;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Center(
          child: SegmentedButton<QrPicture>(
            segments: const [
              ButtonSegment(
                value: QrPicture.card,
                icon: Icon(Icons.badge_outlined),
                label: Text('Thẻ in'),
              ),
              ButtonSegment(
                value: QrPicture.image,
                icon: Icon(Icons.qr_code_2),
                label: Text('Mã QR'),
              ),
            ],
            selected: {_picture},
            onSelectionChanged: (value) =>
                setState(() => _picture = value.single),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: card
                  ? widget.maxCardHeight
                  : widget.maxCardHeight * .7,
            ),
            child: AspectRatio(
              aspectRatio: card ? 1240 / 1748 : 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: switch (file) {
                    AsyncData(:final value) => Image.memory(
                      value.bytes,
                      key: ValueKey(value.fileName),
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                      semanticLabel: card ? 'Thẻ QR' : 'Mã QR',
                      errorBuilder: (_, _, _) => _Problem(
                        message: 'Không hiển thị được ảnh QR.',
                        onRetry: () => widget.onRetry(_picture),
                      ),
                    ),
                    AsyncError(:final error) => _Problem(
                      message: error is Failure
                          ? error.message
                          : 'Không tải được ảnh QR.',
                      onRetry: () => widget.onRetry(_picture),
                    ),
                    _ => const Center(child: CircularProgressIndicator()),
                  },
                ),
              ),
            ),
          ),
        ),
        if (url != null && url.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Đường dẫn khách quét', style: theme.textTheme.labelMedium),
          Row(
            children: [
              Expanded(child: SelectableText(url)),
              IconButton(
                tooltip: 'Sao chép',
                icon: const Icon(Icons.copy),
                onPressed: () => _copy(url),
              ),
              IconButton(
                tooltip: 'Mở',
                icon: const Icon(Icons.open_in_new),
                onPressed: () => _open(url),
              ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _exporting || file.value == null
              ? null
              : () => _export(file.value!),
          icon: _exporting
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(share ? Icons.share : Icons.download),
          label: Text(
            share
                ? (card ? 'Chia sẻ / lưu thẻ in' : 'Chia sẻ / lưu mã QR')
                : (card ? 'Tải thẻ in' : 'Tải mã QR'),
          ),
        ),
      ],
    );
  }
}

class _Problem extends StatelessWidget {
  const _Problem({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: onRetry, child: const Text('Thử lại')),
        ],
      ),
    ),
  );
}
