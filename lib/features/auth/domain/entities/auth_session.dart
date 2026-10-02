import 'auth_tokens.dart';
import 'authenticated_user.dart';

class AuthSession {
  const AuthSession({required this.user, required this.tokens});

  final AuthenticatedUser user;
  final AuthTokens tokens;
}
