import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../controllers/auth_state.dart';
import '../widgets/brand_logo.dart';

class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(authControllerProvider).state;
    final message = state.status == AuthStatus.bootstrapping
        ? 'Đang tải quyền truy cập...'
        : 'Đang khôi phục phiên đăng nhập...';
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const XayPosWordmark(),
            const SizedBox(height: 28),
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(message),
          ],
        ),
      ),
    );
  }
}
