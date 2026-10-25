import 'package:flutter/foundation.dart';

import '../../../../core/auth/app_session.dart';
import '../../../../core/auth/session_events.dart';
import '../../../../core/config/device_info_service.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../../subscription/domain/entities/entitlement.dart';
import '../../../subscription/domain/use_cases/get_current_entitlements.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/entities/login_credentials.dart';
import '../../domain/entities/user_role.dart';
import '../../domain/use_cases/login_use_case.dart';
import '../../domain/use_cases/logout.dart';
import '../../domain/use_cases/restore_session.dart';
import 'auth_state.dart';

class AuthController extends ChangeNotifier {
  AuthController({
    required LoginUseCase login,
    required RestoreSession restoreSession,
    required Logout logout,
    required GetCurrentEntitlements getEntitlements,
    required SessionEvents sessionEvents,
    Future<String?> Function()? deviceInfoLoader,
  }) : _login = login,
       _restoreSession = restoreSession,
       _logout = logout,
       _getEntitlements = getEntitlements,
       _sessionEvents = sessionEvents,
       _deviceInfoLoader =
           deviceInfoLoader ?? DeviceInfoService().getDescription {
    _sessionEvents.addListener(_handleSessionEvent);
  }

  final LoginUseCase _login;
  final RestoreSession _restoreSession;
  final Logout _logout;
  final GetCurrentEntitlements _getEntitlements;
  final SessionEvents _sessionEvents;
  final Future<String?> Function() _deviceInfoLoader;

  AuthState _state = const AuthState();
  AuthState get state => _state;
  int _generation = 0;
  Future<void>? _accessCheck;

  Future<void> restore() async {
    if (_state.status == AuthStatus.restoring) return;
    final generation = ++_generation;
    _emit(const AuthState(status: AuthStatus.restoring));
    final result = await _restoreSession();
    if (generation != _generation) return;
    switch (result) {
      case Success(value: final authSession):
        if (authSession == null) {
          _emit(const AuthState(status: AuthStatus.unauthenticated));
        } else {
          await _bootstrap(authSession, generation);
        }
      case Error(failure: final failure):
        if (failure.type == FailureType.invalidRefreshToken) {
          _emit(
            AuthState(
              status: AuthStatus.unauthenticated,
              message: failure.message,
            ),
          );
        } else {
          _emit(
            AuthState(
              status: AuthStatus.failure,
              message: failure.message,
              failureStage: AuthFailureStage.restore,
            ),
          );
        }
    }
  }

  Future<void> login(LoginCredentials credentials) async {
    if (_state.isBusy) return;
    final validationErrors = _validate(credentials);
    if (validationErrors.isNotEmpty) {
      _emit(
        AuthState(
          status: AuthStatus.unauthenticated,
          fieldErrors: validationErrors,
          failureStage: AuthFailureStage.login,
        ),
      );
      return;
    }

    final generation = ++_generation;
    _sessionEvents.beginScope();
    _emit(const AuthState(status: AuthStatus.authenticating));
    final deviceInfo = await _deviceInfoLoader();
    if (generation != _generation) return;
    final result = await _login(credentials, deviceInfo: deviceInfo);
    if (generation != _generation) return;
    switch (result) {
      case Success(value: final authSession):
        await _bootstrap(authSession, generation);
      case Error(failure: final failure):
        _emit(
          AuthState(
            status: AuthStatus.failure,
            message: failure.message,
            fieldErrors: failure.fieldErrors,
            failureStage: AuthFailureStage.login,
          ),
        );
    }
  }

  Future<void> retry() async {
    switch (_state.failureStage) {
      case AuthFailureStage.restore:
        await restore();
      case AuthFailureStage.entitlement:
        final session = _state.session;
        if (session != null) {
          await _bootstrap(
            AuthSession(
              user: session.authenticatedUser,
              tokens: session.tokens,
            ),
            ++_generation,
          );
        }
      case AuthFailureStage.login:
      case null:
        return;
    }
  }

  Future<void> logout() async {
    ++_generation;
    _sessionEvents.beginScope();
    final logout = _logout();
    _emit(const AuthState(status: AuthStatus.unauthenticated));
    await logout;
  }

  /// Rechecks effective grants without briefly dropping the tenant scope.
  /// Identical denied grants remain blocked by the realtime channel owner.
  Future<void> revalidateAccess() {
    final active = _accessCheck;
    if (active != null) return active;
    late final Future<void> task;
    task = _revalidateAccess().whenComplete(() {
      if (identical(_accessCheck, task)) _accessCheck = null;
    });
    _accessCheck = task;
    return task;
  }

  Future<void> _revalidateAccess() async {
    if (_state.status != AuthStatus.authenticated) return;
    final generation = _generation;
    final result = await _restoreSession();
    if (generation != _generation) return;
    if (result case Success(value: final session)) {
      if (session == null) {
        _sessionEvents.invalidate();
      } else {
        await _bootstrap(session, generation, preserveCurrent: true);
      }
    } else if (result case Error(failure: final failure)) {
      if (failure.type == FailureType.invalidRefreshToken) {
        _sessionEvents.invalidate();
      } else if (failure.type == FailureType.restaurantInactive ||
          failure.code == 'ACCOUNT_INACTIVE') {
        _emit(
          AuthState(
            status: AuthStatus.failure,
            failureStage: AuthFailureStage.restore,
            message: failure.message,
          ),
        );
      }
    }
  }

  Future<void> _bootstrap(
    AuthSession authSession,
    int generation, {
    bool preserveCurrent = false,
  }) async {
    if (generation != _generation) return;
    final user = authSession.user;
    if (user.role == UserRole.superAdmin ||
        user.role == UserRole.unsupported ||
        user.restaurantId == null) {
      _emit(
        AuthState(
          status: AuthStatus.authenticated,
          session: AppSession.withoutEntitlement(
            user: user,
            tokens: authSession.tokens,
          ),
        ),
      );
      return;
    }

    final partialSession = AppSession.withoutEntitlement(
      user: user,
      tokens: authSession.tokens,
    );
    if (!preserveCurrent) {
      _emit(
        AuthState(status: AuthStatus.bootstrapping, session: partialSession),
      );
    }
    final result = await _getEntitlements();
    if (generation != _generation) return;
    final refreshed = _sessionEvents.refreshedSession;
    final latestAuth =
        refreshed?.user.id == user.id &&
            refreshed?.user.restaurantId == user.restaurantId
        ? refreshed!
        : authSession;
    final tokens = latestAuth.tokens;
    switch (result) {
      case Success(value: final entitlement):
        _emit(
          AuthState(
            status: AuthStatus.authenticated,
            session: AppSession.fromEntitlement(
              user: latestAuth.user,
              tokens: tokens,
              entitlement: entitlement,
            ),
          ),
        );
      case Error(failure: final failure):
        if (preserveCurrent &&
            (failure.isNetwork || failure.type == FailureType.internal)) {
          return;
        }
        if (failure.type == FailureType.subscriptionNotActive) {
          _emit(
            AuthState(
              status: AuthStatus.authenticated,
              session: AppSession.fromEntitlement(
                user: latestAuth.user,
                tokens: tokens,
                entitlement: const Entitlement(
                  subscriptionId: null,
                  packageCode: null,
                  status: SubscriptionStatus.missing,
                  features: [],
                ),
              ),
            ),
          );
        } else {
          _emit(
            AuthState(
              status: AuthStatus.failure,
              session: partialSession,
              message: failure.message,
              failureStage: AuthFailureStage.entitlement,
            ),
          );
        }
    }
  }

  Map<String, String> _validate(LoginCredentials credentials) {
    final errors = <String, String>{};
    final email = credentials.email.trim();
    if (email.isEmpty) {
      errors['email'] = 'Vui lòng nhập email.';
    } else if (email.length > 254 ||
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      errors['email'] = 'Email không đúng định dạng.';
    }
    if (credentials.password.isEmpty) {
      errors['password'] = 'Vui lòng nhập mật khẩu.';
    }
    return errors;
  }

  void _handleSessionEvent() {
    if (_sessionEvents.invalidated) {
      ++_generation;
      _emit(
        const AuthState(
          status: AuthStatus.unauthenticated,
          message: 'Phiên đăng nhập đã hết hạn',
        ),
      );
      return;
    }

    final refreshed = _sessionEvents.refreshedSession;
    final current = _state.session;
    if (refreshed != null && current != null) {
      if (refreshed.user.id != current.authenticatedUser.id ||
          refreshed.user.restaurantId !=
              current.authenticatedUser.restaurantId) {
        _bootstrap(refreshed, ++_generation);
        return;
      }
      _emit(
        AuthState(
          status: AuthStatus.authenticated,
          session: current.copyWithAuth(
            user: refreshed.user,
            tokens: refreshed.tokens,
          ),
        ),
      );
    }
  }

  void _emit(AuthState state) {
    _state = state;
    notifyListeners();
  }

  @override
  void dispose() {
    ++_generation;
    _sessionEvents.removeListener(_handleSessionEvent);
    super.dispose();
  }
}
