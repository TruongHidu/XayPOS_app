import 'staff_member.dart';

class PaginatedStaffResult {
  const PaginatedStaffResult({
    required this.content,
    required this.page,
    required this.size,
    required this.totalElements,
    required this.totalPages,
  });

  final List<StaffMember> content;
  final int page;
  final int size;
  final int totalElements;
  final int totalPages;
}
