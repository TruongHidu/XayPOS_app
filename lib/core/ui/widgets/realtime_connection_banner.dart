import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/realtime_providers.dart';
import '../../../app/theme/app_colors.dart';
import '../../realtime/realtime_config.dart';
import '../../realtime/realtime_connection_service.dart';

enum _Trouble { reconnecting, halted }

/// Tells staff when live updates stop, so a quiet kitchen or table screen is
/// never mistaken for "no new orders". Short blips stay hidden: the strip only
/// appears once the connection has been down for [grace], and briefly says so
/// when it comes back.
class RealtimeConnectionBanner extends ConsumerStatefulWidget {
  const RealtimeConnectionBanner({
    super.key,
    this.grace = const Duration(seconds: 5),
    this.recoveredFor = const Duration(seconds: 2),
  });

  final Duration grace, recoveredFor;

  @override
  ConsumerState<RealtimeConnectionBanner> createState() =>
      _RealtimeConnectionBannerState();
}

class _RealtimeConnectionBannerState
    extends ConsumerState<RealtimeConnectionBanner> {
  Timer? _grace, _recovered;
  bool _visible = false, _showRecovered = false;

  @override
  void dispose() {
    _grace?.cancel();
    _recovered?.cancel();
    super.dispose();
  }

  _Trouble? _trouble(RealtimeConnectionService connection, bool websocket) {
    if (!websocket) return null;
    if (connection.halted) return _Trouble.halted;
    return connection.wantsConnection &&
            connection.state != RealtimeConnectionState.connected
        ? _Trouble.reconnecting
        : null;
  }

  /// Runs on every rebuild, so each change of connection state lands here.
  void _track(_Trouble? trouble, bool connected) {
    if (trouble == null) {
      _grace?.cancel();
      _grace = null;
      if (_visible) {
        _visible = false;
        _showRecovered = connected;
        _recovered?.cancel();
        if (connected) {
          _recovered = Timer(widget.recoveredFor, () {
            if (mounted) setState(() => _showRecovered = false);
          });
        }
      }
      return;
    }
    _recovered?.cancel();
    _showRecovered = false;
    if (_visible || _grace != null) return;
    _grace = Timer(widget.grace, () {
      if (!mounted) return;
      // Re-read: a block may have been set without a state change.
      setState(() {
        _grace = null;
        _visible = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final connection = ref.watch(realtimeConnectionProvider);
    final websocket = ref.watch(
      realtimeConfigProvider.select(
        (config) => config.mode == RealtimeTransportMode.websocket,
      ),
    );
    final trouble = _trouble(connection, websocket);
    _track(trouble, connection.state == RealtimeConnectionState.connected);

    final Widget child;
    if (_visible && trouble != null) {
      final halted = trouble == _Trouble.halted;
      child = _Strip(
        key: const ValueKey('realtime-banner-offline'),
        icon: halted ? Icons.sync_disabled : Icons.wifi_off_rounded,
        background: AppColors.warningSoft,
        foreground: AppColors.warning,
        message: halted
            ? 'Cập nhật tự động đang dừng. Dữ liệu chỉ mới khi bạn tải lại màn hình.'
            : 'Mất kết nối cập nhật tức thời. Đang thử kết nối lại…',
        action: halted
            ? null
            : TextButton(
                key: const ValueKey('realtime-banner-retry'),
                onPressed: connection.retry,
                style: TextButton.styleFrom(foregroundColor: AppColors.warning),
                child: const Text('Thử lại'),
              ),
      );
    } else if (_showRecovered) {
      child = const _Strip(
        key: ValueKey('realtime-banner-recovered'),
        icon: Icons.wifi_rounded,
        background: AppColors.successSoft,
        foreground: AppColors.success,
        message: 'Đã kết nối lại.',
      );
    } else {
      child = const SizedBox(width: double.infinity);
    }
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      alignment: Alignment.topCenter,
      child: child,
    );
  }
}

class _Strip extends StatelessWidget {
  const _Strip({
    super.key,
    required this.icon,
    required this.background,
    required this.foreground,
    required this.message,
    this.action,
  });
  final IconData icon;
  final Color background, foreground;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Material(
      color: background,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
        child: Row(
          children: [
            Icon(icon, size: 20, color: foreground),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  message,
                  style: TextStyle(
                    color: foreground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            ?action,
          ],
        ),
      ),
    ),
  );
}
