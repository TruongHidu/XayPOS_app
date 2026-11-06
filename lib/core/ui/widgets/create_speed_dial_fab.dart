import 'package:flutter/material.dart';

/// One entry of [CreateSpeedDialFab].
class SpeedDialOption {
  const SpeedDialOption({
    required this.label,
    required this.icon,
    required this.onSelected,
  });
  final String label;
  final IconData icon;
  final Future<void> Function(BuildContext context) onSelected;
}

/// Floating add button that opens a speed-dial overlay of [options] above it.
/// With [directWhenSingle], a single option runs immediately instead.
class CreateSpeedDialFab extends StatelessWidget {
  const CreateSpeedDialFab({
    super.key,
    required this.options,
    this.tooltip = 'Thêm mới',
    this.directWhenSingle = true,
  });
  final List<SpeedDialOption> options;
  final String tooltip;
  final bool directWhenSingle;

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) return const SizedBox.shrink();
    return FloatingActionButton(
      tooltip: tooltip,
      onPressed: () async {
        if (directWhenSingle && options.length == 1) {
          await options.single.onSelected(context);
          return;
        }
        final chosen = await _showOptions(context);
        if (chosen != null && context.mounted) {
          await chosen.onSelected(context);
        }
      },
      child: const Icon(Icons.add),
    );
  }

  Future<SpeedDialOption?> _showOptions(BuildContext context) {
    final box = context.findRenderObject()! as RenderBox;
    final fabRect = box.localToGlobal(Offset.zero) & box.size;

    return showGeneralDialog<SpeedDialOption>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Đóng',
      barrierColor: Colors.black38,
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (dialogContext, _, _) {
        final screen = MediaQuery.sizeOf(dialogContext);
        return Stack(
          children: [
            Positioned(
              left: 16,
              right: screen.width - fabRect.right,
              bottom: screen.height - fabRect.top + 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final option in options)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: _OptionRow(
                        option: option,
                        width: fabRect.width,
                        onTap: () => Navigator.of(dialogContext).pop(option),
                      ),
                    ),
                ],
              ),
            ),
            Positioned.fromRect(
              rect: fabRect,
              child: FloatingActionButton(
                heroTag: null,
                tooltip: 'Đóng',
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Icon(Icons.close),
              ),
            ),
          ],
        );
      },
      transitionBuilder: (_, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0, 0.03),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.option,
    required this.width,
    required this.onTap,
  });

  final SpeedDialOption option;
  final double width;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Material(
            elevation: 3,
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                child: Text(option.label, style: theme.textTheme.labelLarge),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Centre the small button over the main FAB.
        SizedBox(
          width: width,
          child: Center(
            child: FloatingActionButton.small(
              heroTag: null,
              tooltip: option.label,
              onPressed: onTap,
              child: Icon(option.icon),
            ),
          ),
        ),
      ],
    );
  }
}
