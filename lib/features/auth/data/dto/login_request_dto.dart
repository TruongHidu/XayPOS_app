import '../../domain/entities/login_credentials.dart';

class LoginRequestDto {
  const LoginRequestDto({
    required this.email,
    required this.password,
    this.deviceInfo,
  });

  factory LoginRequestDto.fromDomain(
    LoginCredentials credentials, {
    String? deviceInfo,
  }) {
    return LoginRequestDto(
      email: credentials.email,
      password: credentials.password,
      deviceInfo: deviceInfo,
    );
  }

  final String email;
  final String password;
  final String? deviceInfo;

  Map<String, dynamic> toJson() => {
    'email': email,
    'password': password,
    if (deviceInfo != null) 'deviceInfo': deviceInfo,
  };
}
