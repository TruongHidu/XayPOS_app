import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/providers.dart';
import '../../../../core/config/environment.dart';
import '../../../../core/result/result.dart';
import '../../../subscription/domain/entities/entitlement.dart';
import '../../data/settings_remote_data_source.dart';
import '../../data/settings_repository_impl.dart';
import '../../domain/entities/restaurant_profile.dart';
import '../../domain/repositories/settings_repository.dart';

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

/// Opens a page in the browser; returns false when nothing could open it.
final externalLinkOpenerProvider = Provider<Future<bool> Function(Uri)>(
  (ref) =>
      (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);
