import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/config/environment.dart';
import '../../../core/platform/external_link_opener.dart';
import '../../auth/domain/entities/user_role.dart';
import '../../subscription/domain/entities/entitlement.dart';

class AccessMessageScreen extends ConsumerStatefulWidget {
  const AccessMessageScreen({
    super.key,
    required this.title,
    required this.ownerMessage,
    this.staffMessage,
    this.offerSubscription = false,
  });

  final String title;
  final String ownerMessage;
  final String? staffMessage;

  /// Lets the owner buy or renew a package on the web, then re-check here.
  /// Only the owner can buy (the web page is owner-only), and the offer is
  /// left out on iOS, where App Store rules forbid sending users outside the
  /// app to pay for a digital service.
  final bool offerSubscription;

  @override
  ConsumerState<AccessMessageScreen> createState() =>
      _AccessMessageScreenState();
}

class _AccessMessageScreenState extends ConsumerState<AccessMessageScreen> {
  bool _checking = false;

  Future<void> _openSubscription() async {
    final uri = Uri.tryParse(Environment.subscribeUrl);
    var opened = false;
    if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http')) {
      try {
        opened = await ref.read(externalLinkOpenerProvider)(uri);
      } on Object {
        opened = false;
      }
    }
    if (!opened && mounted) {
      _notice('Không mở được trang đăng ký gói. Vui lòng thử lại.');
    }
  }

  /// After paying on the web: reload the package; the router moves on once
  /// it is active.
  Future<void> _recheck() async {
    setState(() => _checking = true);
    try {
      await ref.read(authControllerProvider).revalidateAccess();
    } finally {
      if (mounted) setState(() => _checking = false);
    }
    if (!mounted) return;
    final status = ref
        .read(authControllerProvider)
        .state
        .session
        ?.subscriptionStatus;
    if (status != SubscriptionStatus.active) {
      _notice('Gói chưa hoạt động. Nếu vừa thanh toán, vui lòng đợi ít phút.');
    }
  }

  void _notice(String message) => ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(authControllerProvider);
    final session = controller.state.session;
    final isOwner = session?.authenticatedUser.role == UserRole.owner;
    final message = isOwner
        ? widget.ownerMessage
        : widget.staffMessage ?? widget.ownerMessage;
    final offer =
        widget.offerSubscription &&
        isOwner &&
        defaultTargetPlatform != TargetPlatform.iOS;
    final renewing = session?.subscriptionStatus == SubscriptionStatus.inactive;
    return Scaffold(
      appBar: AppBar(title: const Text('Xây POS')),
      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    offer
                        ? Icons.workspace_premium_outlined
                        : Icons.info_outline,
                    size: 56,
                    color: offer ? AppColors.primary : null,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    widget.title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    offer && renewing
                        ? 'Gói dịch vụ đã hết hạn hoặc tạm ngưng. Gia hạn để tiếp tục bán hàng.'
                        : message,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  if (offer) ...[
                    SizedBox(
                      height: 48,
                      child: FilledButton.icon(
                        key: const ValueKey('subscribe-button'),
                        onPressed: _checking ? null : _openSubscription,
                        icon: const Icon(Icons.open_in_new),
                        label: Text(renewing ? 'Gia hạn gói' : 'Đăng ký gói'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Mở trang Xây POS trên trình duyệt. Thanh toán xong, quay lại đây và nhấn "Tôi đã đăng ký xong".',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: AppColors.grey600),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      key: const ValueKey('subscription-recheck'),
                      onPressed: _checking ? null : _recheck,
                      icon: _checking
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh),
                      label: const Text('Tôi đã đăng ký xong'),
                    ),
                    const SizedBox(height: 8),
                  ],
                  TextButton.icon(
                    onPressed: controller.logout,
                    icon: const Icon(Icons.logout),
                    label: const Text('Đăng xuất'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
