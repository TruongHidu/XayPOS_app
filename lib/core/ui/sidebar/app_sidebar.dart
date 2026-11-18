import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme/app_status_colors.dart';
import '../../../app/theme/app_tokens.dart';
import '../../values/vietnamese_text.dart';
import '../widgets/app_search_field.dart';
import '../widgets/list_states.dart';
import '../widgets/status_badge.dart';
import 'sidebar_category.dart';
import 'sidebar_menu_item.dart';

/// The full menu: every section the user may open, the account, and logout.
///
/// * Phones ([panel] false): a bottom sheet that stops above the bottom tabs
///   ([bottomTabsHeight]), so the tabs stay visible and "Khác" stays lit.
/// * Tablets ([panel] true): a 360px panel over the rail and the content.
///
/// The parent owns [animation] (an [AnimationController]) to open and close
/// it; the content is built only while it is open.
class AppSidebar extends StatefulWidget {
  const AppSidebar({
    super.key,
    required this.animation,
    required this.categories,
    required this.selectedId,
    required this.onItemTap,
    required this.onLogout,
    required this.userName,
    required this.userRole,
    this.itemBadges = const {},
    this.restaurantName,
    this.packageCode,
    this.panel = false,
    this.bottomTabsHeight = 0,
  });

  /// Drives the open/close transition.
  final Animation<double> animation;

  /// Visible menu categories (already filtered by permission/feature).
  final List<SidebarCategory> categories;

  /// The [SidebarMenuItem.id] of the currently active item.
  final String? selectedId;

  /// Optional counts displayed beside visible menu items.
  final Map<String, int> itemBadges;

  /// Called when the user taps on a menu item.
  final ValueChanged<SidebarMenuItem> onItemTap;

  /// Called when the user taps "Đăng xuất".
  final VoidCallback onLogout;

  /// Display name of the authenticated user.
  final String userName;

  /// Human-readable role label.
  final String userRole;

  /// Optional restaurant name shown in the header.
  final String? restaurantName;

  /// Optional package code (BASIC / PRO / PREMIUM).
  final String? packageCode;

  /// A side panel (tablets) instead of a bottom sheet (phones).
  final bool panel;

  /// Height of the bottom tabs the sheet stays above, without the system
  /// inset under them; 0 when there are none.
  final double bottomTabsHeight;

  static const double panelWidth = 360;

  @override
  State<AppSidebar> createState() => _AppSidebarState();
}

class _AppSidebarState extends State<AppSidebar> {
  static final _sheetTween = Tween<Offset>(
    begin: const Offset(0, 1),
    end: Offset.zero,
  );
  static final _panelTween = Tween<Offset>(
    begin: const Offset(-1, 0),
    end: Offset.zero,
  );

  /// Gap between the status bar and the top of the sheet.
  static const double _sheetTopGap = 40;

  final Map<String, bool> _expanded = {};
  String _query = '';

  /// Whether the menu shows at all; flips only when it starts opening or
  /// finishes closing, so a slide never rebuilds the content.
  late bool _visible;

  // Built once per animation, not per frame: a curve made in build adds a
  // status listener to the controller on every frame and never removes it.
  late CurvedAnimation _slideCurve;
  late CurvedAnimation _fadeCurve;
  late Animation<Offset> _sheetSlide;
  late Animation<Offset> _panelSlide;

  @override
  void initState() {
    super.initState();
    _syncExpansion();
    _bindAnimation();
  }

  @override
  void didUpdateWidget(covariant AppSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncExpansion(selectionChanged: oldWidget.selectedId != widget.selectedId);
    if (oldWidget.animation != widget.animation) {
      _disposeAnimation();
      _bindAnimation();
    }
  }

  @override
  void dispose() {
    _disposeAnimation();
    super.dispose();
  }

  void _bindAnimation() {
    _slideCurve = CurvedAnimation(
      parent: widget.animation,
      curve: Curves.easeOutCubic,
    );
    _fadeCurve = CurvedAnimation(
      parent: widget.animation,
      curve: Curves.easeOut,
    );
    _sheetSlide = _sheetTween.animate(_slideCurve);
    _panelSlide = _panelTween.animate(_slideCurve);
    _visible = !widget.animation.isDismissed;
    widget.animation.addStatusListener(_onStatus);
  }

  void _disposeAnimation() {
    widget.animation.removeStatusListener(_onStatus);
    _slideCurve.dispose();
    _fadeCurve.dispose();
  }

  void _onStatus(AnimationStatus status) {
    final visible = !status.isDismissed;
    if (visible == _visible) return;
    setState(() {
      _visible = visible;
      // Opening again starts with an empty search.
      if (visible) _query = '';
    });
  }

  AnimationController? get _controller => switch (widget.animation) {
    final AnimationController controller => controller,
    _ => null,
  };

  void _close() => _controller?.reverse();

  void _dragUpdate(DragUpdateDetails details, double height) {
    final controller = _controller;
    if (controller == null || height <= 0) return;
    controller.value -= details.primaryDelta! / height;
  }

  void _dragEnd(DragEndDetails details) {
    final controller = _controller;
    if (controller == null) return;
    final flung = details.primaryVelocity! > 300;
    if (flung || controller.value < 0.6) {
      controller.reverse();
    } else {
      controller.forward();
    }
  }

  void _syncExpansion({bool selectionChanged = false}) {
    final categories = widget.categories.where(
      (category) => category.collapsible,
    );
    final titles = categories.map((category) => category.title).toSet();
    _expanded.removeWhere((title, _) => !titles.contains(title));
    for (final category in categories) {
      final containsSelection = category.items.any(
        (item) => item.id == widget.selectedId,
      );
      _expanded.putIfAbsent(category.title, () => containsSelection);
      if (selectionChanged && containsSelection) {
        _expanded[category.title] = true;
      }
    }
  }

  /// Whether to show category headers (hidden when there is only one).
  bool get _showHeaders => widget.categories.length > 1;

  @override
  Widget build(BuildContext context) {
    // Nothing is built, laid out or found by tests while it is closed.
    if (!_visible) return const SizedBox.shrink();
    return widget.panel ? _buildPanel(context) : _buildSheet(context);
  }

  Widget _scrim() => Positioned.fill(
    child: Semantics(
      label: 'Đóng menu',
      button: true,
      child: GestureDetector(
        onTap: _close,
        child: FadeTransition(
          opacity: _fadeCurve,
          child: ColoredBox(color: Colors.black.withValues(alpha: 0.32)),
        ),
      ),
    ),
  );

  Widget _buildSheet(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final tabs = widget.bottomTabsHeight > 0
        ? widget.bottomTabsHeight + padding.bottom
        : 0.0;
    final bottom = math.max(tabs, keyboard);
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final top = padding.top + _sheetTopGap;
          final height = math.max(0.0, constraints.maxHeight - top);
          return Stack(
            children: [
              _scrim(),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: height,
                child: ClipRect(
                  child: SlideTransition(
                    position: _sheetSlide,
                    child: Material(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(AppRadius.lg),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: MediaQuery.removePadding(
                        context: context,
                        removeTop: true,
                        removeBottom: true,
                        child: _content(
                          context,
                          handle: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onVerticalDragUpdate: (d) => _dragUpdate(d, height),
                            onVerticalDragEnd: _dragEnd,
                            child: const _DragHandle(),
                          ),
                          onHeaderDrag: (d) => _dragUpdate(d, height),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPanel(BuildContext context) {
    final width = math.min(
      AppSidebar.panelWidth,
      MediaQuery.sizeOf(context).width,
    );
    return Stack(
      children: [
        _scrim(),
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: width,
          child: SlideTransition(
            position: _panelSlide,
            child: Material(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: const BorderRadius.horizontal(
                right: Radius.circular(AppRadius.lg),
              ),
              clipBehavior: Clip.antiAlias,
              child: SafeArea(
                right: false,
                child: Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.md),
                  child: _content(context),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _content(
    BuildContext context, {
    Widget? handle,
    GestureDragUpdateCallback? onHeaderDrag,
  }) {
    final hasItems = widget.categories.any((c) => c.items.isNotEmpty);
    final header = _Header(
      userName: widget.userName,
      userRole: widget.userRole,
      restaurantName: widget.restaurantName,
      packageCode: widget.packageCode,
      onClose: _close,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ?handle,
        if (onHeaderDrag == null)
          header
        else
          GestureDetector(
            onVerticalDragUpdate: onHeaderDrag,
            onVerticalDragEnd: _dragEnd,
            child: header,
          ),
        if (hasItems)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: AppSearchField(
              key: const ValueKey('sidebar-search'),
              hintText: 'Tìm chức năng…',
              dense: false,
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
        Expanded(
          child: SingleChildScrollView(
            // Reopening keeps the place the user scrolled to.
            key: const PageStorageKey('sidebar-scroll'),
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm,
              0,
              AppSpacing.sm,
              AppSpacing.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!hasItems)
                  const EmptyState(
                    icon: Icons.lock_outline,
                    message: 'Chưa được cấp quyền',
                    hint:
                        'Tài khoản chưa có chức năng nào. Liên hệ chủ quán '
                        'để được phân quyền.',
                  )
                else if (_query.trim().isNotEmpty)
                  ..._buildResults(context)
                else
                  ..._buildCategories(context),
                const Divider(
                  height: AppSpacing.lg,
                  indent: AppSpacing.lg,
                  endIndent: AppSpacing.lg,
                ),
                _LogoutTile(onTap: widget.onLogout),
              ],
            ),
          ),
        ),
      ],
    );
  }

  _MenuTile _tile(SidebarMenuItem item, {String? group, Key? key}) => _MenuTile(
    key: key,
    item: item,
    group: group,
    badgeCount: widget.itemBadges[item.id],
    isSelected: item.id == widget.selectedId,
    onTap: () => widget.onItemTap(item),
  );

  List<Widget> _buildCategories(BuildContext context) => [
    for (final category in widget.categories)
      if (category.collapsible)
        _buildExpandableCategory(context, category)
      else ...[
        if (_showHeaders) _GroupTitle(category.title),
        for (final item in category.items) _tile(item),
      ],
  ];

  /// Matches labels without accents or case: "ton kho" finds "Tồn kho".
  List<Widget> _buildResults(BuildContext context) {
    String fold(String value) =>
        removeVietnameseDiacritics(value).toLowerCase().trim();
    final query = fold(_query);
    final matches = [
      for (final category in widget.categories)
        for (final item in category.items)
          if (fold(item.label).contains(query)) (category, item),
    ];
    if (matches.isEmpty) {
      return [
        EmptyState(
          icon: Icons.search_off,
          message: 'Không có chức năng “${_query.trim()}”',
          hint: 'Thử từ khác, ví dụ: đơn, kho, báo cáo.',
        ),
      ];
    }
    return [
      _GroupTitle('${matches.length} kết quả'),
      for (final (category, item) in matches)
        _tile(item, group: _sentenceCase(category.title)),
    ];
  }

  Widget _buildExpandableCategory(
    BuildContext context,
    SidebarCategory category,
  ) {
    final expanded = _expanded[category.title] ?? false;
    final active = category.items.any((item) => item.id == widget.selectedId);
    final colors = Theme.of(context).colorScheme;
    void toggle() => setState(() => _expanded[category.title] = !expanded);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm),
          child: Semantics(
            expanded: expanded,
            child: ListTile(
              key: ValueKey('sidebar-group-${category.title}'),
              minTileHeight: 56,
              contentPadding: const EdgeInsets.only(
                left: AppSpacing.lg,
                right: AppSpacing.xs,
              ),
              shape: const RoundedRectangleBorder(
                borderRadius: AppRadius.buttonAll,
              ),
              leading: Icon(
                category.icon ?? Icons.folder_outlined,
                color: active ? colors.primary : colors.onSurfaceVariant,
              ),
              title: Text(
                category.title,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: active ? colors.primary : colors.onSurface,
                ),
              ),
              trailing: IconButton(
                tooltip:
                    '${expanded ? 'Thu gọn' : 'Mở rộng'} ${category.title}',
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                onPressed: toggle,
                icon: Icon(expanded ? Icons.expand_less : Icons.expand_more),
              ),
              onTap: toggle,
            ),
          ),
        ),
        if (expanded)
          for (final item in category.items)
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.md),
              child: _tile(item, key: ValueKey('sidebar-item-${item.id}')),
            ),
      ],
    );
  }
}

/// "BÁN HÀNG & VẬN HÀNH" → "Bán hàng & vận hành", for search results.
String _sentenceCase(String title) {
  final lower = title.toLowerCase();
  return lower.isEmpty ? lower : lower[0].toUpperCase() + lower.substring(1);
}

// ──────────────────────────────────────────────────────────
// Private sub-widgets
// ──────────────────────────────────────────────────────────

class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) => SizedBox(
    height: AppSpacing.xl,
    child: Center(
      child: SizedBox(
        width: AppSpacing.xxxl,
        height: AppSpacing.xs,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.outlineVariant,
            borderRadius: AppRadius.pillAll,
          ),
        ),
      ),
    ),
  );
}

class _GroupTitle extends StatelessWidget {
  const _GroupTitle(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        6,
      ),
      child: Text(
        title,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

/// Who is signed in, in one compact block: initial, name, role and the
/// restaurant with its package.
class _Header extends StatelessWidget {
  const _Header({
    required this.userName,
    required this.userRole,
    required this.onClose,
    this.restaurantName,
    this.packageCode,
  });

  final String userName;
  final String userRole;
  final String? restaurantName;
  final String? packageCode;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = context.tone(AppTone.primary);
    final details = [
      ?restaurantName,
      if (packageCode != null) 'Gói $packageCode',
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.sm,
        AppSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: CircleAvatar(
              radius: 20,
              backgroundColor: primary.background,
              child: Text(
                userName.isNotEmpty ? userName[0].toUpperCase() : '?',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: primary.foreground,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(userName, style: theme.textTheme.titleSmall),
                      StatusBadge(label: userRole, tone: AppTone.primary),
                    ],
                  ),
                  if (details.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      details,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: 'Đóng menu',
            onPressed: onClose,
            icon: Icon(Icons.close, color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    super.key,
    required this.item,
    required this.isSelected,
    required this.onTap,
    this.badgeCount,
    this.group,
  });

  final SidebarMenuItem item;
  final bool isSelected;
  final VoidCallback onTap;
  final int? badgeCount;

  /// The section the item belongs to, under its label in search results.
  final String? group;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final primary = context.tone(AppTone.primary);
    final badgeCount = this.badgeCount ?? 0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: ListTile(
        selected: isSelected,
        minTileHeight: 48,
        selectedTileColor: primary.background,
        selectedColor: colorScheme.primary,
        iconColor: colorScheme.onSurfaceVariant,
        textColor: colorScheme.onSurface,
        contentPadding: const EdgeInsets.only(
          left: AppSpacing.lg,
          right: AppSpacing.md,
        ),
        horizontalTitleGap: AppSpacing.lg,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.buttonAll),
        leading: Icon(item.icon),
        title: Text(
          item.label,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            color: isSelected ? colorScheme.primary : colorScheme.onSurface,
          ),
        ),
        subtitle: group == null
            ? null
            : Text(
                group!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
        trailing: badgeCount > 0
            ? Semantics(
                key: ValueKey('sidebar-badge-${item.id}'),
                label: '$badgeCount mục',
                child: ExcludeSemantics(
                  child: Container(
                    constraints: const BoxConstraints(
                      minWidth: 22,
                      minHeight: 22,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.error,
                      borderRadius: AppRadius.lgAll,
                    ),
                    child: Text(
                      badgeCount > 99 ? '99+' : '$badgeCount',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onError,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              )
            : null,
        onTap: onTap,
      ),
    );
  }
}

class _LogoutTile extends StatelessWidget {
  const _LogoutTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = theme.colorScheme.error;
    return ListTile(
      minTileHeight: 48,
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      horizontalTitleGap: AppSpacing.lg,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.buttonAll),
      leading: Icon(Icons.logout, color: error),
      title: Text(
        'Đăng xuất',
        style: theme.textTheme.bodyLarge?.copyWith(
          fontWeight: FontWeight.w500,
          color: error,
        ),
      ),
      onTap: onTap,
    );
  }
}
