import '../../../core/network/api_error_mapper.dart';
import '../../../core/network/binary_download.dart';
import '../../../core/result/result.dart';
import '../domain/entities/public_menu_link.dart';
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

  @override
  Future<Result<PublicMenuLink?>> getMenuLink() async {
    final result = await _guard<PublicMenuLink?>(_remote.getMenuLink);
    if (result case Error(
      :final failure,
    ) when failure.code == 'PUBLIC_MENU_LINK_NOT_INITIALIZED') {
      return const Success(null);
    }
    return result;
  }

  @override
  Future<Result<PublicMenuLink>> createMenuLink() =>
      _guard(_remote.createMenuLink);

  @override
  Future<Result<PublicMenuLink>> rotateMenuLink() =>
      _guard(_remote.rotateMenuLink);

  @override
  Future<Result<DownloadedFile>> menuLinkQrImage() => _remote.menuLinkQrImage();

  @override
  Future<Result<DownloadedFile>> menuLinkQrCard() => _remote.menuLinkQrCard();

  static Future<Result<T>> _guard<T>(Future<T> Function() call) async {
    try {
      return Success(await call());
    } on Object catch (error) {
      return Error(ApiErrorMapper.fromException(error));
    }
  }
}
