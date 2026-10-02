import '../../domain/entities/paginated_staff_result.dart';
import 'staff_member_dto.dart';

class PaginatedStaffDto {
  const PaginatedStaffDto({
    required this.content,
    required this.page,
    required this.size,
    required this.totalElements,
    required this.totalPages,
  });

  final List<StaffMemberDto> content;
  final int page;
  final int size;
  final int totalElements;
  final int totalPages;

  factory PaginatedStaffDto.fromJson(Map<String, dynamic> json) {
    final rawContent = json['content'] as List<dynamic>? ?? [];
    return PaginatedStaffDto(
      content: rawContent
          .map((item) => StaffMemberDto.fromJson(item as Map<String, dynamic>))
          .toList(),
      page: json['page'] as int? ?? 0,
      size: json['size'] as int? ?? 20,
      totalElements: json['totalElements'] as int? ?? 0,
      totalPages: json['totalPages'] as int? ?? 0,
    );
  }

  PaginatedStaffResult toEntity() {
    return PaginatedStaffResult(
      content: content.map((dto) => dto.toEntity()).toList(),
      page: page,
      size: size,
      totalElements: totalElements,
      totalPages: totalPages,
    );
  }
}
