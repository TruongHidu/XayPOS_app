import 'package:go_router/go_router.dart';

import '../../core/auth/access_policy.dart';
import '../../features/auth/presentation/controllers/auth_controller.dart';
import '../../features/auth/presentation/controllers/auth_state.dart';
import 'app_routes.dart';

class RouteGuard {
  RouteGuard(this._authController);

  final AuthController _authController;
  String? _pendingDeepLink;

  String? redirect(GoRouterState routerState) {
    final auth = _authController.state;
    final location = routerState.matchedLocation;
    final isLogin = location == AppRoutes.login;
    final isSplash = location == AppRoutes.splash;
    final isSessionError = location == AppRoutes.sessionError;

    if (auth.status == AuthStatus.initial ||
        auth.status == AuthStatus.restoring ||
        auth.status == AuthStatus.bootstrapping) {
      if (!isSplash && !isLogin && !isSessionError) {
        _pendingDeepLink = location;
      }
      return isSplash ? null : AppRoutes.splash;
    }

    if (auth.status == AuthStatus.authenticating) {
      return isLogin ? null : AppRoutes.login;
    }

    if (auth.status == AuthStatus.unauthenticated) {
      _pendingDeepLink = null;
      return isLogin ? null : AppRoutes.login;
    }

    if (auth.status == AuthStatus.failure) {
      if (auth.failureStage == AuthFailureStage.login) {
        return isLogin ? null : AppRoutes.login;
      }
      return isSessionError ? null : AppRoutes.sessionError;
    }

    final session = auth.session;
    if (auth.status != AuthStatus.authenticated || session == null) {
      return isSplash ? null : AppRoutes.splash;
    }

    final initialRoute = AccessPolicy.initialRouteFor(session);
    final pending = _pendingDeepLink;
    _pendingDeepLink = null;
    if (pending != null && AccessPolicy.canOpenRoute(session, pending)) {
      return pending == location ? null : pending;
    }

    if (isLogin || isSplash || isSessionError) return initialRoute;
    if (location == initialRoute) return null;
    if (AccessPolicy.canOpenRoute(session, location)) return null;
    return initialRoute;
  }
}
