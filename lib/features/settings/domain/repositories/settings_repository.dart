import '../../../../core/result/result.dart';
import '../entities/restaurant_profile.dart';

abstract interface class SettingsRepository {
  Future<Result<RestaurantProfile>> getRestaurant();

  Future<Result<RestaurantProfile>> updateRestaurant(
    RestaurantProfileUpdate update,
  );
}
