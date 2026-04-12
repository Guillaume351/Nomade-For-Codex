import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

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
  static const bool enabled = bool.fromEnvironment(
    'NOMADE_ENABLE_NATIVE_NOTIFICATIONS',
    defaultValue: false,
  );

  static const MethodChannel _pushChannel =
      MethodChannel('nomade/native_notifications');
  static const MethodChannel _runtimeChannel =
      MethodChannel('nomade/runtime_status');

  static Future<NativePushRegistration?> getPushRegistration() async {
    if (!enabled || kIsWeb) {
      return null;
    }
    try {
      final raw = await _pushChannel.invokeMapMethod<String, dynamic>(
        'getPushRegistration',
      );
      if (raw == null) {
        return null;
      }
      final token = raw['token']?.toString().trim() ?? '';
      if (token.isEmpty) {
        return null;
      }
      final provider = raw['provider']?.toString().trim();
      final platform = raw['platform']?.toString().trim();
      final deviceId = raw['deviceId']?.toString().trim();
      return NativePushRegistration(
        provider: provider != null && provider.isNotEmpty ? provider : 'fcm',
        platform: platform != null && platform.isNotEmpty
            ? platform
            : defaultTargetPlatform.name,
        token: token,
        deviceId: deviceId != null && deviceId.isNotEmpty
            ? deviceId
            : 'mobile-${defaultTargetPlatform.name}',
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
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
      // no-op when native bridge is unavailable
    } on PlatformException {
      // no-op when native bridge errors
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
      // no-op when native bridge is unavailable
    } on PlatformException {
      // no-op when native bridge errors
    }
  }
}
