import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router/app_router.dart';
import 'providers.dart';
import 'theme/app_theme.dart';
import '../features/inventory/presentation/widgets/inventory_alert_notice_overlay.dart';

class App extends ConsumerStatefulWidget {
  const App({super.key});

  @override
  ConsumerState<App> createState() => _AppState();
}

class _AppState extends ConsumerState<App> with WidgetsBindingObserver {
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    if (state != null) {
      Future.microtask(() {
        if (mounted) didChangeAppLifecycleState(state);
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    ref.read(realtimeForegroundProvider.notifier).state =
        state == AppLifecycleState.resumed;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(realtimeBootstrapProvider);
    ref.listen<String?>(staffNoticeProvider, (previous, message) {
      if (message == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _messengerKey.currentState?.showSnackBar(
          SnackBar(content: Text(message)),
        );
        if (ref.read(staffNoticeProvider) == message) {
          ref.read(staffNoticeProvider.notifier).state = null;
        }
      });
    });
    final router = ref.watch(appRouterProvider);
    ref.listen<String?>(orderNoticeProvider, (previous, message) {
      if (message == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _messengerKey.currentState?.showSnackBar(
          SnackBar(content: Text(message)),
        );
        if (ref.read(orderNoticeProvider) == message) {
          ref.read(orderNoticeProvider.notifier).state = null;
        }
      });
    });
    ref.listen<String?>(tableNoticeProvider, (previous, message) {
      if (message == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _messengerKey.currentState?.showSnackBar(
          SnackBar(content: Text(message)),
        );
        if (ref.read(tableNoticeProvider) == message) {
          ref.read(tableNoticeProvider.notifier).state = null;
        }
      });
    });
    ref.listen<String?>(menuNoticeProvider, (previous, message) {
      if (message == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _messengerKey.currentState?.showSnackBar(
          SnackBar(content: Text(message)),
        );
        if (ref.read(menuNoticeProvider) == message) {
          ref.read(menuNoticeProvider.notifier).state = null;
        }
      });
    });
    return MaterialApp.router(
      scaffoldMessengerKey: _messengerKey,
      title: 'Xây POS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: router,
      builder: (context, child) => Stack(
        fit: StackFit.expand,
        children: [
          if (child != null) child,
          const InventoryAlertNoticeOverlay(),
        ],
      ),
    );
  }
}
