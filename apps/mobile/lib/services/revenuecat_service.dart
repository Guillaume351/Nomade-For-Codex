import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

class RevenueCatService {
  static const String _appleApiKey = String.fromEnvironment(
    'NOMADE_RC_APPLE_API_KEY',
    defaultValue: '',
  );
  static const String _googleApiKey = String.fromEnvironment(
    'NOMADE_RC_GOOGLE_API_KEY',
    defaultValue: '',
  );

  static String? _configuredAppUserId;
  static String? _configuredApiKey;

  static bool get isSupportedOnCurrentPlatform {
    if (kIsWeb) {
      return false;
    }
    return defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android;
  }

  static String get apiKeyForCurrentPlatform {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return _appleApiKey.trim();
      case TargetPlatform.android:
        return _googleApiKey.trim();
      default:
        return '';
    }
  }

  static bool get hasApiKeyForCurrentPlatform =>
      apiKeyForCurrentPlatform.isNotEmpty;

  static Future<void> configureForUser(String appUserId) async {
    if (!isSupportedOnCurrentPlatform) {
      throw StateError(
          'RevenueCat purchases are only enabled on iOS and Android.');
    }
    final normalizedUserId = appUserId.trim();
    if (normalizedUserId.isEmpty) {
      throw StateError('RevenueCat requires a non-empty app user ID.');
    }
    final apiKey = apiKeyForCurrentPlatform;
    if (apiKey.isEmpty) {
      throw StateError(
        'Missing RevenueCat public SDK key for this platform. '
        'Pass NOMADE_RC_APPLE_API_KEY or NOMADE_RC_GOOGLE_API_KEY.',
      );
    }

    if (_configuredApiKey == apiKey &&
        _configuredAppUserId == normalizedUserId) {
      return;
    }

    if (_configuredApiKey == null) {
      final configuration = PurchasesConfiguration(apiKey)
        ..appUserID = normalizedUserId;
      await Purchases.configure(configuration);
    } else if (_configuredAppUserId != normalizedUserId) {
      await Purchases.logIn(normalizedUserId);
    }

    _configuredApiKey = apiKey;
    _configuredAppUserId = normalizedUserId;
  }

  static Future<Offering?> getCurrentOffering() async {
    final offerings = await Purchases.getOfferings();
    return offerings.current;
  }

  static Future<PurchaseResult> purchasePackage(Package package) {
    return Purchases.purchase(PurchaseParams.package(package));
  }

  static Future<CustomerInfo> restorePurchases() {
    return Purchases.restorePurchases();
  }

  static Future<void> logOut() async {
    if (!isSupportedOnCurrentPlatform || _configuredApiKey == null) {
      _configuredApiKey = null;
      _configuredAppUserId = null;
      return;
    }
    try {
      await Purchases.logOut();
    } catch (_) {
      // Best-effort cleanup only; logout must not block app sign-out.
    } finally {
      _configuredApiKey = null;
      _configuredAppUserId = null;
    }
  }
}
