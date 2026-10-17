import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/providers.dart' show authControllerProvider;
import '../../../../app/router/app_routes.dart';
import '../../../../core/auth/access_policy.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../../../core/ui/widgets/responsive_dialog.dart';
import '../../domain/entities/menu_group.dart';
import '../../domain/entities/menu_item.dart';
import '../providers/menu_providers.dart';
import 'menu_dialogs.dart';

/// Displays a menu item image with consistent aspect ratio and placeholder.
///
/// Supports both square (legacy) and aspect-ratio modes. Uses [BoxFit.cover]
/// to fill the area without distortion, and shows a themed placeholder during
/// loading, on error, or when no URL is available.
class MenuImage extends StatelessWidget {
  const MenuImage({
    super.key,
    required this.url,
    this.size,
    this.aspectRatio = 4 / 3,
    this.borderRadius = 12.0,
    this.onTap,
  });

  final String? url;

  /// When non-null, creates a square image of this dimension (legacy mode).
  /// When null, uses [aspectRatio] to determine height from available width.
  final double? size;

  /// Width / height ratio used when [size] is null. Defaults to 4:3.
  final double aspectRatio;

  /// Corner radius for the image container.
  final double borderRadius;

  /// Called when the user taps the image. Used for zoom/preview.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final iconSize = size != null ? size! / 2 : 36.0;
    final placeholder = Container(
      color: colors.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.restaurant_outlined,
          size: iconSize,
          color: colors.onSurfaceVariant.withValues(alpha: 0.5),
        ),
      ),
    );

    final hasUrl = url != null && url!.isNotEmpty;

    Widget image;
    if (size != null) {
      // Legacy square mode
      image = SizedBox.square(
        dimension: size,
        child: hasUrl
            ? Image.network(
                url!,
                fit: BoxFit.cover,
                loadingBuilder: (_, child, progress) =>
                    progress == null ? child : placeholder,
                errorBuilder: (_, __, ___) => placeholder,
              )
            : placeholder,
      );
    } else {
      // Aspect ratio mode
      image = AspectRatio(
        aspectRatio: aspectRatio,
        child: hasUrl
            ? Image.network(
                url!,
                fit: BoxFit.cover,
                loadingBuilder: (_, child, progress) =>
                    progress == null ? child : placeholder,
                errorBuilder: (_, __, ___) => placeholder,
              )
            : placeholder,
      );
    }

    final clipped = ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: image,
    );

    if (onTap != null) {
      return GestureDetector(onTap: onTap, child: clipped);
    }
    return clipped;
  }
}

/// Full-screen image preview dialog (tap image to zoom).
class MenuImagePreview extends StatelessWidget {
  const MenuImagePreview({super.key, required this.url});
  final String url;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => Navigator.of(context).pop(),
    child: Scaffold(
      backgroundColor: Colors.black87,
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: Image.network(
            url,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Icon(
              Icons.broken_image_outlined,
              color: Colors.white54,
              size: 64,
            ),
          ),
        ),
      ),
    ),
  );
}

class MenuItemBadges extends StatelessWidget {
  const MenuItemBadges({super.key, required this.item});
  final MenuItem item;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 6,
    runSpacing: 6,
    children: [
      MenuBadge(
        label: item.active ? 'Đang kinh doanh' : 'Ngừng kinh doanh',
        positive: item.active,
        icon: item.active ? Icons.storefront : Icons.store_outlined,
      ),
      MenuBadge(
        label: item.availabilityStatus == AvailabilityStatus.available
            ? 'Còn hàng'
            : 'Hết hàng',
        positive: item.availabilityStatus == AvailabilityStatus.available,
        icon: item.availabilityStatus == AvailabilityStatus.available
            ? Icons.inventory_2_outlined
            : Icons.remove_shopping_cart_outlined,
      ),
      MenuBadge(
        label: item.sellable ? 'Có thể bán' : 'Chưa thể bán',
        positive: item.sellable,
        icon: item.sellable ? Icons.check_circle_outline : Icons.block_outlined,
      ),
    ],
  );
}

class MenuBadge extends StatelessWidget {
  const MenuBadge({
    super.key,
    required this.label,
    required this.positive,
    this.icon,
  });
  final String label;
  final bool positive;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final bgColor = positive
        ? colors.secondaryContainer
        : colors.surfaceContainerHighest;
    final fgColor = positive
        ? colors.onSecondaryContainer
        : colors.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: fgColor),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: fgColor),
          ),
        ],
      ),
    );
  }
}

class MenuItemDetails extends ConsumerStatefulWidget {
  const MenuItemDetails({super.key, required this.initial});
  final MenuItem initial;
  @override
  ConsumerState<MenuItemDetails> createState() => _MenuItemDetailsState();
}

class _MenuItemDetailsState extends ConsumerState<MenuItemDetails> {
  late MenuItem _item = widget.initial;
  bool _loading = false;
  Failure? _failure;
  int _request = 0;
  Future<void> _reload() async {
    final request = ++_request;
    setState(() => _loading = true);
    final result = await ref.read(menuItemControllerProvider).detail(_item.id);
    if (!mounted || request != _request) return;
    setState(() {
      _loading = false;
      switch (result) {
        case Success(value: final item):
          _item = item;
          _failure = null;
        case Error(failure: final failure):
          _failure = failure;
      }
    });
  }

  void _openImagePreview() {
    final url = _item.imageUrl;
    if (url == null || url.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => MenuImagePreview(url: url),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    ref.listen(
      menuCatalogEventsProvider.select(
        (events) => (events.groupRevision, events.itemRevision),
      ),
      (_, next) => unawaited(_reload()),
    );
    return ResponsiveDialog(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Chi tiết món',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Đóng',
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            if (_loading) const LinearProgressIndicator(),
            MenuFailurePanel(failure: _failure, onReload: _reload),
            if (_failure == null) ...[
              const SizedBox(height: 12),
              // Hero image — larger than list card
              MenuImage(
                url: _item.imageUrl,
                aspectRatio: 16 / 9,
                borderRadius: 12,
                onTap: _openImagePreview,
              ),
              const SizedBox(height: 16),
              // Name
              Text(_item.name, style: theme.textTheme.headlineSmall),
              if (AccessPolicy.canRecipe(
                ref.watch(authControllerProvider).state.session,
                'RECIPE_VIEW',
              )) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.menu_book_outlined),
                    label: const Text('Công thức'),
                    onPressed: () {
                      final router = GoRouter.of(context);
                      final item = _item;
                      Navigator.of(context).pop();
                      router.push(AppRoutes.recipeFor(item.id));
                    },
                  ),
                ),
              ],
              const SizedBox(height: 12),
              // Price section
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.primaryContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.sell_outlined,
                          size: 18,
                          color: colors.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${_item.salePrice}',
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: colors.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '/ ${_item.baseUnit}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    if (_item.costPrice != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Giá vốn: ${_item.costPrice} / ${_item.baseUnit}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Badges
              MenuItemBadges(item: _item),
              const SizedBox(height: 16),
              // Details section
              _infoRow(
                context,
                Icons.qr_code,
                'SKU: ${_item.sku ?? "Chưa có"}',
              ),
              _infoRow(
                context,
                Icons.folder_outlined,
                'Nhóm: ${_item.group?.name ?? "Chưa phân nhóm"}${_item.group?.active == false ? " (ngừng hoạt động)" : ""}',
              ),
              if (_item.description?.isNotEmpty == true) ...[
                const SizedBox(height: 12),
                Text(
                  'Mô tả',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(_item.description!),
              ],
              const Divider(height: 24),
              Text(
                'Tạo: ${menuDate(_item.createdAt)} · Cập nhật: ${menuDate(_item.updatedAt)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.outline,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _loading ? null : _reload,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Làm mới'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(BuildContext context, IconData icon, String text) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class MenuGroupDetails extends StatelessWidget {
  const MenuGroupDetails({super.key, required this.group});
  final MenuGroup group;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return ResponsiveDialog(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(group.name, style: theme.textTheme.titleLarge),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Đóng',
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 12),
            MenuBadge(
              label: group.active ? 'Đang hoạt động' : 'Ngừng hoạt động',
              positive: group.active,
              icon: group.active
                  ? Icons.check_circle_outline
                  : Icons.pause_circle_outline,
            ),
            const SizedBox(height: 12),
            _detailRow(
              context,
              Icons.reorder,
              'Thứ tự hiển thị',
              '${group.displayOrder}',
            ),
            const Divider(height: 24),
            Text(
              'Tạo: ${menuDate(group.createdAt)}\nCập nhật: ${menuDate(group.updatedAt)}',
              style: theme.textTheme.bodySmall?.copyWith(color: colors.outline),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
