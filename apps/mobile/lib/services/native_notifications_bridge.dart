import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class NativePushRegistration {
  const NativePushRegistration({
    required this.provider,
    required this.platform,
    required this.token,
    required this.deviceId,
  });

  final String provider;
  final String platform;
  final String token;
  final String deviceId;
}

class NativeNotificationsBridge {
  static bool get enabled =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  static const MethodChannel _runtimeChannel =
      MethodChannel('nomade/runtime_status');
  static Future<void>? _firebaseInitialization;

  static Future<void> _ensureFirebaseInitialized() {
    final existing = _firebaseInitialization;
    if (existing != null) {
      return existing;
    }
    final future = () async {
      if (Firebase.apps.isNotEmpty) {
        return;
      }
      await Firebase.initializeApp();
    }();
    _firebaseInitialization = future;
    return future;
  }

  static Future<NativePushRegistration?> getPushRegistration() async {
    if (!enabled) {
      return null;
    }

    try {
      await _ensureFirebaseInitialized();
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      String? fcmToken;
      for (var attempt = 0; attempt < 4; attempt++) {
        fcmToken = await messaging.getToken();
        if (fcmToken != null && fcmToken.trim().isNotEmpty) {
          break;
        }
        if (attempt < 3) {
          await Future<void>.delayed(
            Duration(milliseconds: 500 * (attempt + 1)),
          );
        }
      }
      final token = fcmToken?.trim() ?? '';
      if (token.isNotEmpty) {
        return NativePushRegistration(
          provider: 'fcm',
          platform: defaultTargetPlatform.name,
          token: token,
          // Leave empty so provider can fall back to secure-storage-backed ID.
          deviceId: '',
        );
      }
    } on FirebaseException {
      return null;
    } on UnsupportedError {
      return null;
    }
    return null;
  }

  static Future<void> setRunningStatus({
    required String conversationId,
    required String turnId,
    String? title,
    String? subtitle,
  }) async {
    if (!enabled || kIsWeb) {
      return;
    }
    try {
      await _runtimeChannel.invokeMethod<void>('setRunningStatus', {
        'conversationId': conversationId,
        'turnId': turnId,
        if (title != null && title.trim().isNotEmpty) 'title': title.trim(),
        if (subtitle != null && subtitle.trim().isNotEmpty)
          'subtitle': subtitle.trim(),
      });
    } on MissingPluginException {
      if (kDebugMode) {
        debugPrint(
          '[nomade/runtime_status] native bridge unavailable for setRunningStatus',
        );
      }
    } on PlatformException catch (error) {
      if (kDebugMode) {
        debugPrint(
          '[nomade/runtime_status] setRunningStatus failed: '
          '${error.code} ${error.message ?? ""}'.trim(),
        );
      }
    }
  }

  static Future<void> clearRunningStatus({
    required String conversationId,
    required String turnId,
  }) async {
    if (!enabled || kIsWeb) {
      return;
    }
    try {
      await _runtimeChannel.invokeMethod<void>('clearRunningStatus', {
        'conversationId': conversationId,
        'turnId': turnId,
      });
    } on MissingPluginException {
      if (kDebugMode) {
        debugPrint(
          '[nomade/runtime_status] native bridge unavailable for clearRunningStatus',
        );
      }
    } on PlatformException catch (error) {
      if (kDebugMode) {
        debugPrint(
          '[nomade/runtime_status] clearRunningStatus failed: '
          '${error.code} ${error.message ?? ""}'.trim(),
        );
      }
    }
  }
}
