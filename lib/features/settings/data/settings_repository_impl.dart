import '../../../core/network/api_error_mapper.dart';
import '../../../core/result/result.dart';
import '../domain/entities/restaurant_profile.dart';
import '../domain/repositories/settings_repository.dart';
import 'settings_remote_data_source.dart';

class SettingsRepositoryImpl implements SettingsRepository {
  const SettingsRepositoryImpl(this._remote);

  final SettingsRemoteDataSource _remote;

  @override
  Future<Result<RestaurantProfile>> getRestaurant() =>
      _guard(_remote.getRestaurant);

  @override
  Future<Result<RestaurantProfile>> updateRestaurant(
    RestaurantProfileUpdate update,
  ) => _guard(() => _remote.updateRestaurant(update));

  static Future<Result<T>> _guard<T>(Future<T> Function() call) async {
    try {
      return Success(await call());
    } on Object catch (error) {
      return Error(ApiErrorMapper.fromException(error));
    }
  }
}
