import '../../domain/entities/authenticated_user.dart';
import 'user_dto.dart';

class MeResponseDto {
  const MeResponseDto(this.user);

  factory MeResponseDto.fromJson(Map<String, dynamic> json) {
    return MeResponseDto(UserDto.fromJson(json));
  }

  final UserDto user;

  AuthenticatedUser toDomain() => user.toDomain();
}
