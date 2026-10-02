import '../../../../core/auth/app_session.dart';

enum AuthStatus {
  initial,
  restoring,
  unauthenticated,
  authenticating,
  bootstrapping,
  authenticated,
  failure,
}

enum AuthFailureStage { login, restore, entitlement }

class AuthState {
  const AuthState({
    this.status = AuthStatus.initial,
    this.session,
    this.message,
    this.fieldErrors = const {},
    this.failureStage,
  });

  final AuthStatus status;
  final AppSession? session;
  final String? message;
  final Map<String, String> fieldErrors;
  final AuthFailureStage? failureStage;

  bool get isBusy =>
      status == AuthStatus.authenticating || status == AuthStatus.bootstrapping;
}
