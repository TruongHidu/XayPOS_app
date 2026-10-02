import 'package:flutter/foundation.dart';

import '../../features/auth/domain/entities/auth_session.dart';

class SessionEvents extends ChangeNotifier {
  AuthSession? _refreshedSession;
  bool _invalidated = false;

  AuthSession? get refreshedSession => _refreshedSession;
  bool get invalidated => _invalidated;

  void refreshed(AuthSession session) {
    _refreshedSession = session;
    _invalidated = false;
    notifyListeners();
  }

  void invalidate() {
    _refreshedSession = null;
    _invalidated = true;
    notifyListeners();
  }
}
