import 'package:flutter/material.dart';

/// Shows [child] as a floating panel just below the widget owning
/// [anchorContext] (typically an app bar action). Right-aligned on wide
/// screens, full-width on phones; tapping the barrier dismisses it.
Future<T?> showAnchoredPanel<T>({
  required BuildContext anchorContext,
  required String barrierLabel,
  required Widget child,
  double maxWidth = 440,
}) {
  final box = anchorContext.findRenderObject() as RenderBox?;
  final anchorBottom = box == null
      ? MediaQuery.paddingOf(anchorContext).top + kToolbarHeight
      : box.localToGlobal(Offset(0, box.size.height)).dy;

  return showGeneralDialog<T>(
    context: anchorContext,
    barrierDismissible: true,
    barrierLabel: barrierLabel,
    barrierColor: Colors.black26,
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (dialogContext, _, _) {
      final width = MediaQuery.sizeOf(dialogContext).width;
      final narrow = width < 600;
      return Padding(
        padding: EdgeInsets.only(
          top: anchorBottom + 4,
          left: 12,
          right: 12,
          bottom: 12,
        ),
        child: Align(
          alignment: narrow ? Alignment.topCenter : Alignment.topRight,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: narrow ? width : maxWidth),
            child: child,
          ),
        ),
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
            begin: const Offset(0, -0.04),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// Card surface plus title row shared by the overlay filter panels.
class OverlayPanel extends StatelessWidget {
  const OverlayPanel({
    super.key,
    required this.title,
    required this.child,
    this.icon = Icons.filter_alt_outlined,
    this.onRefresh,
  });

  final String title;
  final IconData icon;
  final VoidCallback? onRefresh;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(16),
      color: theme.colorScheme.surface,
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 12, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (onRefresh != null)
                  IconButton(
                    tooltip: 'Tải lại',
                    icon: const Icon(Icons.refresh),
                    onPressed: onRefresh,
                  ),
                IconButton(
                  tooltip: 'Đóng',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8, right: 8),
              child: child,
            ),
          ],
        ),
      ),
    );
  }
}
