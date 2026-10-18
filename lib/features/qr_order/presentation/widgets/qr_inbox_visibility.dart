import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../controllers/qr_inbox_controller.dart';
import '../providers/qr_request_providers.dart';

/// Each visible route owns its subscription, so closing a dialog cannot stop
/// polling for the workspace that becomes visible underneath it.
class QrInboxVisibility extends ConsumerStatefulWidget {
  const QrInboxVisibility({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<QrInboxVisibility> createState() => _QrInboxVisibilityState();
}

class _QrInboxVisibilityState extends ConsumerState<QrInboxVisibility>
    with WidgetsBindingObserver, RouteAware {
  QrInboxController? _inbox;
  ModalRoute<void>? _route;
  RouteObserver<ModalRoute<void>>? _observer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of<void>(context);
    if (_route == route) return;
    _observer?.unsubscribe(this);
    _route = route;
    _observer = ref.read(qrRequestsRouteObserverProvider);
    if (route != null) _observer!.subscribe(this, route);
  }

  @override
  void didPushNext() => _inbox?.setVisible(this, false);
  @override
  void didPopNext() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && (_route?.isCurrent ?? false)) {
        _inbox?.setVisible(this, true);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _inbox?.setForeground(state == AppLifecycleState.resumed);
  @override
  Widget build(BuildContext context) {
    final inbox = ref.watch(qrInboxProvider);
    if (!identical(_inbox, inbox)) {
      _inbox?.setVisible(this, false);
      _inbox = inbox;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !identical(_inbox, inbox)) return;
        inbox.setForeground(
          WidgetsBinding.instance.lifecycleState == null ||
              WidgetsBinding.instance.lifecycleState ==
                  AppLifecycleState.resumed,
        );
        inbox.setVisible(this, _route?.isCurrent ?? true);
      });
    }
    return widget.child;
  }

  @override
  void dispose() {
    _observer?.unsubscribe(this);
    _inbox?.setVisible(this, false);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
