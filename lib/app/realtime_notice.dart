import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../core/auth/access_policy.dart';
import 'providers.dart';

class StaffRealtimeNoticeController extends ChangeNotifier {
  String? message;
  Timer? _timer;
  void show(String value) {
    _timer?.cancel();
    message = value;
    notifyListeners();
    _timer = Timer(const Duration(seconds: 5), dismiss);
  }

  void dismiss() {
    _timer?.cancel();
    _timer = null;
    message = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final staffRealtimeNoticeProvider = ChangeNotifierProvider((ref) {
  ref.watch(
    authControllerProvider.select(
      (auth) => AccessPolicy.orderScope(auth.state.session),
    ),
  );
  final controller = StaffRealtimeNoticeController();
  ref.listen(realtimeForegroundProvider, (_, value) {
    if (!value) controller.dismiss();
  });
  ref.listen(realtimeSettingsProvider.select((s) => s.effectiveEnabled), (
    _,
    value,
  ) {
    if (!value) controller.dismiss();
  });
  return controller;
});
