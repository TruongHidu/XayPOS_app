import '../../domain/entities/auth_session.dart';
import '../../domain/entities/auth_tokens.dart';
import 'user_dto.dart';

class AuthResponseDto {
  const AuthResponseDto({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
    required this.user,
  });

  factory AuthResponseDto.fromJson(Map<String, dynamic> json) {
    return AuthResponseDto(
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String,
      expiresIn: (json['expiresIn'] as num).toInt(),
      user: UserDto.fromJson(json['user'] as Map<String, dynamic>),
    );
  }

  final String accessToken;
  final String refreshToken;
  final int expiresIn;
  final UserDto user;

  AuthSession toDomain({DateTime? receivedAt}) {
    final now = receivedAt ?? DateTime.now();
    return AuthSession(
      user: user.toDomain(),
      tokens: AuthTokens(
        accessToken: accessToken,
        refreshToken: refreshToken,
        expiresAt: now.add(Duration(seconds: expiresIn)),
      ),
    );
  }
}
