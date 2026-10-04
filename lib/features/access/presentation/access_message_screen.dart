import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../auth/domain/entities/user_role.dart';

class AccessMessageScreen extends ConsumerWidget {
  const AccessMessageScreen({
    super.key,
    required this.title,
    required this.ownerMessage,
    this.staffMessage,
  });

  final String title;
  final String ownerMessage;
  final String? staffMessage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(authControllerProvider);
    final role = controller.state.session?.authenticatedUser.role;
    final isOwner = role == UserRole.owner;
    final message = isOwner ? ownerMessage : staffMessage ?? ownerMessage;
    return Scaffold(
      appBar: AppBar(title: const Text('Xây POS')),
      body: Center(
        child: SizedBox(
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.info_outline, size: 56),
                const SizedBox(height: 16),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text(message, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: controller.logout,
                  icon: const Icon(Icons.logout),
                  label: const Text('Đăng xuất'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
