import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../../app/providers.dart';
import '../../../../core/config/environment.dart';
import '../../../../core/network/binary_download.dart';
import '../../../../core/result/result.dart';
import '../../../../core/ui/widgets/qr_preview.dart';
import '../../../subscription/domain/entities/entitlement.dart';
import '../../data/settings_remote_data_source.dart';
import '../../data/settings_repository_impl.dart';
import '../../domain/entities/public_menu_link.dart';
import '../../domain/entities/restaurant_profile.dart';
import '../../domain/repositories/settings_repository.dart';

export '../../../../core/platform/external_link_opener.dart';

/// Cài đặt reloads when the signed-in account or restaurant changes.
final settingsScopeProvider = authControllerProvider.select((auth) {
  final user = auth.state.session?.authenticatedUser;
  return (user?.id, user?.restaurantId);
});

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepositoryImpl(
    SettingsRemoteDataSource(ref.watch(apiClientsProvider).authenticated),
  ),
);

// Each section shows its own error with a retry button instead.
Duration? _noRetry(int _, Object _) => null;

T _value<T>(Result<T> result) => switch (result) {
  Success(:final value) => value,
  Error(:final failure) => throw failure,
};

final restaurantProfileProvider = FutureProvider.autoDispose<RestaurantProfile>(
  (ref) async {
    ref.watch(settingsScopeProvider);
    return _value(await ref.watch(settingsRepositoryProvider).getRestaurant());
  },
  retry: _noRetry,
);

/// The takeaway menu link; null until the restaurant creates it.
final menuLinkProvider = FutureProvider.autoDispose<PublicMenuLink?>((
  ref,
) async {
  ref.watch(settingsScopeProvider);
  return _value(await ref.watch(settingsRepositoryProvider).getMenuLink());
}, retry: _noRetry);

/// QR picture of the menu link, keyed by token so a rotated link reloads.
typedef MenuLinkFileKey = ({String token, QrPicture picture});
final menuLinkFileProvider = FutureProvider.autoDispose
    .family<DownloadedFile, MenuLinkFileKey>((ref, key) async {
      ref.watch(settingsScopeProvider);
      final repository = ref.watch(settingsRepositoryProvider);
      return _value(
        key.picture == QrPicture.card
            ? await repository.menuLinkQrCard()
            : await repository.menuLinkQrImage(),
      );
    }, retry: _noRetry);

/// Read fresh so dates and the remaining days are current.
final currentEntitlementProvider = FutureProvider.autoDispose<Entitlement>((
  ref,
) async {
  ref.watch(settingsScopeProvider);
  return _value(
    await ref.watch(entitlementRepositoryProvider).getCurrentEntitlements(),
  );
}, retry: _noRetry);

final appVersionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return info.buildNumber.isEmpty
      ? info.version
      : '${info.version} (${info.buildNumber})';
}, retry: _noRetry);

final legalLinksProvider = Provider<({String privacy, String terms})>(
  (ref) => (privacy: Environment.privacyPolicyUrl, terms: Environment.termsUrl),
);
