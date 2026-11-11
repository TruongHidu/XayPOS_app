import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/auth/access_policy.dart';
import '../../../../core/auth/app_session.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../../../core/ui/widgets/qr_preview.dart';
import '../../../subscription/domain/entities/entitlement.dart';
import '../../domain/entities/restaurant_profile.dart';
import '../providers/settings_providers.dart';
import '../widgets/package_feature_labels.dart';
import '../widgets/restaurant_profile_dialog.dart';

/// Restaurant, package, account and app settings. Each section shows only
/// what the signed-in account may see; Tài khoản and Ứng dụng are for everyone.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authControllerProvider).state.session;
    if (session == null) return const SizedBox.shrink();
    final canViewRestaurant = AccessPolicy.hasPermission(
      session,
      'RESTAURANT_PROFILE_VIEW',
    );
    final canManageMenuLink = AccessPolicy.hasPermission(
      session,
      'RESTAURANT_PROFILE_UPDATE',
    );
    final canViewPackage = AccessPolicy.hasPermission(
      session,
      'SUBSCRIPTION_VIEW',
    );
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            if (canViewRestaurant) ...[
              _RestaurantSection(canEdit: canManageMenuLink),
              const SizedBox(height: 16),
            ],
            if (canManageMenuLink) ...[
              const _MenuLinkSection(),
              const SizedBox(height: 16),
            ],
            if (canViewPackage) ...[
              const _PackageSection(),
              const SizedBox(height: 16),
            ],
            _AccountSection(session: session),
            const SizedBox(height: 16),
            const _AppSection(),
          ],
        ),
      ),
    );
  }
}

String _date(DateTime value) {
  final date = value.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(date.day)}/${two(date.month)}/${date.year}';
}

String _message(Object error) =>
    error is Failure ? error.message : 'Đã xảy ra lỗi. Vui lòng thử lại.';

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.children,
    this.action,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
              child: Row(
                children: [
                  Icon(icon, color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  ?action,
                ],
              ),
            ),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// A label and its value; empty values show as a dash.
class _Field extends StatelessWidget {
  const _Field(this.label, this.value);

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = value == null || value!.trim().isEmpty ? '—' : value!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: SelectableText(text)),
        ],
      ),
    );
  }
}

class _Failed extends StatelessWidget {
  const _Failed({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _message(error),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Thử lại')),
        ],
      ),
    );
  }
}

const _loading = Padding(
  padding: EdgeInsets.all(16),
  child: Center(child: CircularProgressIndicator()),
);

class _RestaurantSection extends ConsumerWidget {
  const _RestaurantSection({required this.canEdit});

  final bool canEdit;

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    RestaurantProfile profile,
  ) async {
    final saved = await showDialog<RestaurantProfile>(
      context: context,
      builder: (_) => RestaurantProfileDialog(profile: profile),
    );
    if (saved == null || !context.mounted) return;
    ref.invalidate(restaurantProfileProvider);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Đã lưu thông tin nhà hàng.')));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(restaurantProfileProvider);
    final value = profile.value;
    return _Section(
      title: 'Nhà hàng',
      icon: Icons.storefront_outlined,
      action: canEdit && value != null
          ? IconButton(
              tooltip: 'Sửa thông tin nhà hàng',
              onPressed: () => _edit(context, ref, value),
              icon: const Icon(Icons.edit_outlined),
            )
          : null,
      children: [
        if (profile.isLoading && value == null)
          _loading
        else if (profile.hasError && value == null)
          _Failed(
            error: profile.error!,
            onRetry: () => ref.invalidate(restaurantProfileProvider),
          )
        else if (value != null) ...[
          _Field('Tên nhà hàng', value.name),
          _Field('Mã nhà hàng', value.code),
          _Field('Tên pháp lý', value.legalName),
          _Field('Số điện thoại', value.phone),
          _Field('Địa chỉ', value.address),
          _Field('Múi giờ', value.timezone),
          _Field('Tiền tệ', value.currencyCode),
          _Field('Trạng thái', switch (value.status) {
            'ACTIVE' => 'Đang hoạt động',
            'SUSPENDED' => 'Tạm ngừng',
            'INACTIVE' => 'Ngừng hoạt động',
            final other => other,
          }),
        ],
      ],
    );
  }
}

/// QR for the restaurant-wide menu (takeaway): create, print, rotate.
class _MenuLinkSection extends ConsumerStatefulWidget {
  const _MenuLinkSection();

  @override
  ConsumerState<_MenuLinkSection> createState() => _MenuLinkSectionState();
}

class _MenuLinkSectionState extends ConsumerState<_MenuLinkSection> {
  bool _busy = false;

  Future<void> _create() => _run(
    () => ref.read(settingsRepositoryProvider).createMenuLink(),
    'Đã tạo link menu.',
  );

  Future<void> _rotate() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Đổi link menu?'),
        content: const Text(
          'Link và mã QR cũ sẽ ngừng hoạt động. Các thẻ đã in theo mã cũ sẽ không quét được nữa và cần in lại.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Đổi link'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(
      () => ref.read(settingsRepositoryProvider).rotateMenuLink(),
      'Đã đổi link menu. Hãy in lại thẻ QR.',
    );
  }

  Future<void> _run(
    Future<Result<Object?>> Function() action,
    String done,
  ) async {
    setState(() => _busy = true);
    final result = await action();
    if (!mounted) return;
    setState(() => _busy = false);
    ref.invalidate(menuLinkProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(switch (result) {
          Success() => done,
          Error(:final failure) => failure.message,
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final link = ref.watch(menuLinkProvider);
    final value = link.value;
    MenuLinkFileKey key(QrPicture picture) =>
        (token: value!.menuToken, picture: picture);
    return _Section(
      title: 'QR menu mang đi',
      icon: Icons.qr_code_2,
      action: value != null
          ? IconButton(
              tooltip: 'Đổi link menu',
              onPressed: _busy ? null : _rotate,
              icon: const Icon(Icons.autorenew),
            )
          : null,
      children: [
        if (_busy) const LinearProgressIndicator(),
        if (link.isLoading && !link.hasValue)
          _loading
        else if (link.hasError && !link.hasValue)
          _Failed(
            error: link.error!,
            onRetry: () => ref.invalidate(menuLinkProvider),
          )
        else if (value == null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Chưa tạo link menu cho khách mang đi. Tạo link để in thẻ QR đặt ở quầy, khách quét mã để xem menu và đặt món mang đi.',
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _busy ? null : _create,
                  icon: const Icon(Icons.add_link),
                  label: const Text('Tạo link menu'),
                ),
              ],
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: QrPreview(
              source: (picture) => menuLinkFileProvider(key(picture)),
              onRetry: (picture) =>
                  ref.invalidate(menuLinkFileProvider(key(picture))),
              menuUrl: value.menuUrl,
              maxCardHeight: 320,
            ),
          ),
      ],
    );
  }
}

class _PackageSection extends ConsumerWidget {
  const _PackageSection();

  static int? _daysLeft(Entitlement value) {
    if (value.daysRemaining != null) return value.daysRemaining;
    final end = value.endAt;
    if (end == null) return null;
    final seconds = end.difference(DateTime.now()).inSeconds;
    return seconds <= 0 ? 0 : (seconds / Duration.secondsPerDay).ceil();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entitlement = ref.watch(currentEntitlementProvider);
    final value = entitlement.value;
    final theme = Theme.of(context);
    final days = value == null ? null : _daysLeft(value);
    return _Section(
      title: 'Gói dịch vụ',
      icon: Icons.workspace_premium_outlined,
      children: [
        if (entitlement.isLoading && value == null)
          _loading
        else if (entitlement.hasError && value == null)
          _Failed(
            error: entitlement.error!,
            onRetry: () => ref.invalidate(currentEntitlementProvider),
          )
        else if (value != null) ...[
          _Field('Gói', value.packageName ?? value.packageCode),
          _Field(
            'Trạng thái',
            value.status == SubscriptionStatus.active
                ? 'Đang hoạt động'
                : 'Chưa hoạt động',
          ),
          _Field(
            'Bắt đầu',
            value.startAt == null ? null : _date(value.startAt!),
          ),
          _Field('Hết hạn', value.endAt == null ? null : _date(value.endAt!)),
          if (days != null)
            _Field('Còn lại', days == 0 ? 'Đã hết hạn' : '$days ngày'),
          _Field(
            'Số nhân viên tối đa',
            value.maxStaff == null ? 'Không giới hạn' : '${value.maxStaff}',
          ),
          if (value.features.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final feature in value.features)
                    Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text(packageFeatureLabel(feature.code)),
                    ),
                ],
              ),
            ),
          // Changing the package happens outside the app.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              'Liên hệ quản trị viên Xây POS để thay đổi hoặc gia hạn gói.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _AccountSection extends ConsumerWidget {
  const _AccountSection({required this.session});

  final AppSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = session.authenticatedUser;
    return _Section(
      title: 'Tài khoản của tôi',
      icon: Icons.person_outline,
      children: [
        _Field('Họ tên', user.name),
        _Field('Email', user.email),
        _Field('Số điện thoại', user.phone),
        _Field('Vai trò', user.role.label),
        const Divider(height: 24),
        ListTile(
          leading: const Icon(Icons.logout),
          title: const Text('Đăng xuất'),
          onTap: ref.read(authControllerProvider).logout,
        ),
      ],
    );
  }
}

class _AppSection extends ConsumerWidget {
  const _AppSection();

  Future<void> _open(BuildContext context, WidgetRef ref, String url) async {
    final uri = Uri.tryParse(url);
    final opened =
        uri != null && await ref.read(externalLinkOpenerProvider)(uri);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Không mở được liên kết.')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final realtime = ref.watch(realtimeSettingsProvider);
    final links = ref.watch(legalLinksProvider);
    final version = ref.watch(appVersionProvider).value;
    return _Section(
      title: 'Ứng dụng',
      icon: Icons.phone_android_outlined,
      children: [
        SwitchListTile.adaptive(
          value: realtime.enabled,
          onChanged: realtime.loaded && !realtime.saving
              ? realtime.setEnabled
              : null,
          secondary: const Icon(Icons.sync),
          title: const Text('Cập nhật tự động'),
          subtitle: Text(
            realtime.error ??
                'Tự nhận đơn, món và cảnh báo mới mà không cần tải lại.',
          ),
        ),
        if (links.privacy.isNotEmpty)
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Chính sách quyền riêng tư'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => _open(context, ref, links.privacy),
          ),
        if (links.terms.isNotEmpty)
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('Điều khoản sử dụng'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => _open(context, ref, links.terms),
          ),
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: const Text('Phiên bản'),
          trailing: Text(version ?? '—'),
        ),
      ],
    );
  }
}
