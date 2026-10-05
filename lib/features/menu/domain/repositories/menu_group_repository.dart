import '../../../../core/result/result.dart';
import '../entities/menu_group.dart';
import '../entities/menu_inputs.dart';
import '../entities/menu_page.dart';
import '../entities/menu_query.dart';

abstract interface class MenuGroupRepository {
  Future<Result<MenuPage<MenuGroup>>> list(MenuQuery query);
  Future<Result<MenuGroup>> detail(String id);
  Future<Result<MenuGroup>> create(CreateMenuGroupInput input);
  Future<Result<MenuGroup>> update(String id, UpdateMenuGroupInput input);
  Future<Result<MenuGroup>> setStatus(
    String id,
    bool active,
    int expectedVersion,
  );
  Future<Result<void>> delete(String id, int expectedVersion);
}
