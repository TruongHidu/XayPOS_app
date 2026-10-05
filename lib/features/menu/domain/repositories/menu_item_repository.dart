import '../../../../core/result/result.dart';
import '../entities/menu_item.dart';
import '../entities/menu_inputs.dart';
import '../entities/menu_page.dart';
import '../entities/menu_query.dart';

abstract interface class MenuItemRepository {
  Future<Result<MenuPage<MenuItem>>> list(MenuQuery query);
  Future<Result<MenuItem>> detail(String id);
  Future<Result<MenuItem>> create(CreateMenuItemInput input);
  Future<Result<MenuItem>> update(String id, UpdateMenuItemInput input);
  Future<Result<MenuItem>> setStatus(
    String id,
    bool active,
    int expectedVersion,
  );
  Future<Result<MenuItem>> setAvailability(
    String id,
    AvailabilityStatus status,
    int expectedVersion,
  );
  Future<Result<MenuItem>> setGroup(
    String id,
    String? groupId,
    int expectedVersion,
  );
  Future<Result<void>> delete(String id, int expectedVersion);
}
