import '../../../../core/result/result.dart';
import '../../../../core/network/binary_download.dart';
import '../entities/public_menu_link.dart';
import '../entities/restaurant_profile.dart';

abstract interface class SettingsRepository {
  Future<Result<RestaurantProfile>> getRestaurant();

  Future<Result<RestaurantProfile>> updateRestaurant(
    RestaurantProfileUpdate update,
  );

  /// Null while the restaurant has not created its menu link yet.
  Future<Result<PublicMenuLink?>> getMenuLink();

  Future<Result<PublicMenuLink>> createMenuLink();

  Future<Result<PublicMenuLink>> rotateMenuLink();

  Future<Result<DownloadedFile>> menuLinkQrImage();

  Future<Result<DownloadedFile>> menuLinkQrCard();
}
