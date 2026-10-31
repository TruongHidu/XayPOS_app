import 'package:flutter/material.dart';

/// End of a list that grows as the user scrolls: spinner while rows remain,
/// retry after a failed page, otherwise the closing [endLabel].
///
/// Place it after the rows, inside the vertical scroll view. It asks for the
/// next page whenever the end of that scroll view is near, including when the
/// rows do not fill the screen. [onLoadMore] must ignore overlapping calls.
class EndlessListFooter extends StatefulWidget {
  const EndlessListFooter({
    super.key,
    required this.hasMore,
    required this.endLabel,
    required this.onLoadMore,
    this.failureMessage,
  });

  final bool hasMore;
  final String endLabel;
  final VoidCallback onLoadMore;
  final String? failureMessage;

  @override
  State<EndlessListFooter> createState() => _EndlessListFooterState();
}

class _EndlessListFooterState extends State<EndlessListFooter> {
  static const _preload = 320.0;

  ScrollPosition? _position;
  bool _checkScheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = Scrollable.maybeOf(context, axis: Axis.vertical)?.position;
    if (position != _position) {
      _position?.removeListener(_scheduleCheck);
      _position = position?..addListener(_scheduleCheck);
    }
    _scheduleCheck();
  }

  @override
  void didUpdateWidget(EndlessListFooter oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleCheck();
  }

  @override
  void dispose() {
    _position?.removeListener(_scheduleCheck);
    super.dispose();
  }

  // Positions also notify during layout, when controllers must not rebuild.
  void _scheduleCheck() {
    if (_checkScheduled) return;
    _checkScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkScheduled = false;
      final position = _position;
      if (mounted &&
          widget.hasMore &&
          widget.failureMessage == null &&
          position != null &&
          position.hasContentDimensions &&
          position.extentAfter <= _preload) {
        widget.onLoadMore();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final failure = widget.failureMessage;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: failure != null
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(failure, textAlign: TextAlign.center, style: muted),
                const SizedBox(height: 4),
                TextButton.icon(
                  onPressed: widget.onLoadMore,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Thử lại'),
                ),
              ],
            )
          : !widget.hasMore
          ? Text(widget.endLabel, textAlign: TextAlign.center, style: muted)
          : _position == null
          ? Center(
              child: TextButton(
                onPressed: widget.onLoadMore,
                child: const Text('Tải thêm'),
              ),
            )
          : const Center(
              child: SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            ),
    );
  }
}
