import 'package:flutter/material.dart';
import 'anchored_overlay.dart';

/// The filter button shown beside a search box, with a count of active
/// filters. It opens the same floating panel as the app bar filter actions.
///
/// The panel outlives the build that opened it, so [filters] and [activeCount]
/// must read current values; they run again whenever [listenable] notifies.
class FilterPanelButton extends StatefulWidget {
  const FilterPanelButton({
    super.key,
    required this.listenable,
    required this.title,
    required this.activeCount,
    required this.filters,
    this.onClear,
    this.onRefresh,
  });

  final Listenable listenable;
  final String title;
  final int Function() activeCount;
  final List<Widget> Function() filters;
  final VoidCallback? onClear;
  final VoidCallback? onRefresh;

  @override
  State<FilterPanelButton> createState() => _FilterPanelButtonState();
}

class _FilterPanelButtonState extends State<FilterPanelButton> {
  ModalRoute<void>? _panel;

  /// A screen that lost its permission or scope takes its panel with it, so
  /// nothing keeps writing to a disposed controller.
  @override
  void dispose() {
    final panel = _panel;
    if (panel != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (panel.isActive) panel.navigator?.removeRoute(panel);
      });
    }
    super.dispose();
  }

  Future<void> _open() async {
    await showAnchoredPanel<void>(
      anchorContext: context,
      barrierLabel: 'Đóng bộ lọc',
      child: OverlayPanel(
        title: widget.title,
        onRefresh: widget.onRefresh,
        child: ListenableBuilder(
          listenable: widget.listenable,
          builder: (context, _) {
            _panel = ModalRoute.of<void>(context);
            final children = widget.filters();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (index, child) in children.indexed) ...[
                  if (index > 0) const SizedBox(height: 12),
                  child,
                ],
                if (widget.onClear != null && widget.activeCount() > 0) ...[
                  const SizedBox(height: 4),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton(
                      onPressed: widget.onClear,
                      child: const Text('Xóa bộ lọc'),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
    _panel = null;
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.activeCount();
    return IconButton.outlined(
      tooltip: 'Bộ lọc',
      onPressed: _open,
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text('$count'),
        child: const Icon(Icons.filter_alt_outlined),
      ),
    );
  }
}

/// A search box with its [FilterPanelButton].
class SearchFilterRow extends StatelessWidget {
  const SearchFilterRow({
    super.key,
    required this.search,
    required this.filter,
  });

  final Widget search;
  final Widget filter;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: search),
      const SizedBox(width: 8),
      filter,
    ],
  );
}
