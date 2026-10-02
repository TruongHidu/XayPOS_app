import '../../domain/entities/authenticated_user.dart';
import '../../domain/entities/user_role.dart';

class UserDto {
  const UserDto({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.permissions,
    this.restaurantId,
    this.restaurantCode,
    this.restaurantName,
    this.phone,
  });

  factory UserDto.fromJson(Map<String, dynamic> json) {
    final permissions = json['permissions'];
    return UserDto(
      id: json['id'] as String? ?? '',
      restaurantId: json['restaurantId'] as String?,
      restaurantCode: json['restaurantCode'] as String?,
      restaurantName: json['restaurantName'] as String?,
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      phone: json['phone'] as String?,
      role: json['role'] as String?,
      permissions: permissions is List
          ? permissions.map((item) => item.toString()).toList()
          : const [],
    );
  }

  final String id;
  final String? restaurantId;
  final String? restaurantCode;
  final String? restaurantName;
  final String name;
  final String email;
  final String? phone;
  final String? role;
  final List<String> permissions;

  AuthenticatedUser toDomain() => AuthenticatedUser(
    id: id,
    restaurantId: restaurantId,
    restaurantCode: restaurantCode,
    restaurantName: restaurantName,
    name: name,
    email: email,
    phone: phone,
    role: UserRole.fromJson(role),
    permissions: permissions.toSet(),
  );
}
