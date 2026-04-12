import Flutter
import UIKit
import UserNotifications

#if canImport(ActivityKit)
import ActivityKit
#endif

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let nativeNotificationsBridge = NativeNotificationsBridgeController()
  private let runtimeStatusBridge = RuntimeStatusBridgeController()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let launched = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    nativeNotificationsBridge.bootstrap(application: application)
    return launched
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
    nativeNotificationsBridge.didRegisterForRemoteNotifications(with: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
    nativeNotificationsBridge.didFailToRegisterForRemoteNotifications(error: error)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    nativeNotificationsBridge.installChannel(pluginRegistry: engineBridge.pluginRegistry)
    runtimeStatusBridge.installChannel(pluginRegistry: engineBridge.pluginRegistry)
  }
}

private final class NativeNotificationsBridgeController {
  private let channelName = "nomade/native_notifications"
  private let deviceIdDefaultsKey = "nomade.native_notifications.device_id"
  private let pushProviderInfoKey = "NomadePushProvider"

  private var pushToken: String?
  private var pushTokenError: String?
  private var didBootstrap = false

  func bootstrap(application: UIApplication) {
    guard !didBootstrap else { return }
    didBootstrap = true
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) {
      [weak self] _, error in
      if let error {
        self?.pushTokenError = "authorization_failed:\(error.localizedDescription)"
      }
      DispatchQueue.main.async {
        application.registerForRemoteNotifications()
      }
    }
  }

  func installChannel(pluginRegistry: FlutterPluginRegistry) {
    guard let registrar = pluginRegistry.registrar(forPlugin: "NomadeNativeNotificationsBridge") else {
#if DEBUG
      NSLog("[nomade/native_notifications] unable to acquire plugin registrar")
#endif
      return
    }
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      guard let self else {
        result(FlutterError(code: "native_bridge_unavailable", message: nil, details: nil))
        return
      }
      if call.method == "getPushRegistration" {
        self.handleGetPushRegistration(result: result)
        return
      }
      result(FlutterMethodNotImplemented)
    }
  }

  func didRegisterForRemoteNotifications(with deviceToken: Data) {
    pushTokenError = nil
    pushToken = deviceToken.map { String(format: "%02x", $0) }.joined()
  }

  func didFailToRegisterForRemoteNotifications(error: Error) {
    pushTokenError = "registration_failed:\(error.localizedDescription)"
  }

  private func handleGetPushRegistration(result: FlutterResult) {
    if let payload = registrationPayload() {
      result(payload)
      return
    }
    DispatchQueue.main.async {
      UIApplication.shared.registerForRemoteNotifications()
    }
#if DEBUG
    if let pushTokenError {
      NSLog("[nomade/native_notifications] push token unavailable: \(pushTokenError)")
    }
#endif
    result(nil)
  }

  private func registrationPayload() -> [String: Any]? {
    guard let token = pushToken, !token.isEmpty else {
      return nil
    }
    let provider = pushProvider()
    if provider == "fcm" && !looksLikeFcmToken(token) {
      pushTokenError = "fcm_token_unavailable_apns_only"
      return nil
    }
    return [
      "provider": provider,
      "platform": "ios",
      "token": token,
      "deviceId": persistentDeviceId()
    ]
  }

  private func persistentDeviceId() -> String {
    let defaults = UserDefaults.standard
    if let existing = defaults.string(forKey: deviceIdDefaultsKey), !existing.isEmpty {
      return existing
    }
    let generated = "ios-\(UUID().uuidString.lowercased())"
    defaults.set(generated, forKey: deviceIdDefaultsKey)
    return generated
  }

  private func pushProvider() -> String {
    guard
      let raw = Bundle.main.object(forInfoDictionaryKey: pushProviderInfoKey) as? String
    else {
      return "fcm"
    }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return trimmed.isEmpty ? "fcm" : trimmed
  }

  private func looksLikeFcmToken(_ token: String) -> Bool {
    return token.contains(":") && token.count >= 32
  }
}

private final class RuntimeStatusBridgeController {
  private let channelName = "nomade/runtime_status"

  func installChannel(pluginRegistry: FlutterPluginRegistry) {
    guard let registrar = pluginRegistry.registrar(forPlugin: "NomadeRuntimeStatusBridge") else {
#if DEBUG
      NSLog("[nomade/runtime_status] unable to acquire plugin registrar")
#endif
      return
    }
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
      switch call.method {
      case "setRunningStatus":
        self.handleSetRunningStatus(call: call, result: result)
      case "clearRunningStatus":
        self.handleClearRunningStatus(call: call, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func handleSetRunningStatus(call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = (call.arguments as? [String: Any]) ?? [:]
    let conversationId = normalizedString(args["conversationId"])
    let turnId = normalizedString(args["turnId"])
    guard !turnId.isEmpty else {
      result(FlutterError(code: "invalid_args", message: "turnId is required", details: nil))
      return
    }
    let title = normalizedString(args["title"]).ifEmpty("Nomade")
    let subtitle = normalizedString(args["subtitle"]).ifEmpty("Running turn")

    guard #available(iOS 16.1, *) else {
      result(nil)
      return
    }

#if canImport(ActivityKit)
    Task {
      do {
        try await NomadeLiveActivityStore.shared.startOrUpdate(
          conversationId: conversationId,
          turnId: turnId,
          title: title,
          subtitle: subtitle
        )
        DispatchQueue.main.async {
          result(nil)
        }
      } catch {
        DispatchQueue.main.async {
          result(
            FlutterError(
              code: "live_activity_request_failed",
              message: error.localizedDescription,
              details: nil
            )
          )
        }
      }
    }
#else
    result(nil)
#endif
  }

  private func handleClearRunningStatus(call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = (call.arguments as? [String: Any]) ?? [:]
    let conversationId = normalizedString(args["conversationId"])
    let turnId = normalizedString(args["turnId"])
    guard !turnId.isEmpty else {
      result(FlutterError(code: "invalid_args", message: "turnId is required", details: nil))
      return
    }

    guard #available(iOS 16.1, *) else {
      result(nil)
      return
    }

#if canImport(ActivityKit)
    Task {
      await NomadeLiveActivityStore.shared.clear(conversationId: conversationId, turnId: turnId)
      DispatchQueue.main.async {
        result(nil)
      }
    }
#else
    result(nil)
#endif
  }

  private func normalizedString(_ value: Any?) -> String {
    guard let raw = value as? String else {
      return ""
    }
    return raw.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

#if canImport(ActivityKit)
@available(iOS 16.1, *)
private struct NomadeLiveActivityAttributes: ActivityAttributes {
  public struct ContentState: Codable, Hashable {
    var title: String
    var subtitle: String
    var conversationId: String
    var turnId: String
  }

  var id: String
}

@available(iOS 16.1, *)
private actor NomadeLiveActivityStore {
  static let shared = NomadeLiveActivityStore()

  func startOrUpdate(
    conversationId: String,
    turnId: String,
    title: String,
    subtitle: String
  ) async throws {
    let key = activityKey(conversationId: conversationId, turnId: turnId)
    let state = NomadeLiveActivityAttributes.ContentState(
      title: title,
      subtitle: subtitle,
      conversationId: conversationId,
      turnId: turnId
    )

    if let existing = findActivity(for: key) {
      if #available(iOS 16.2, *) {
        let content = ActivityContent(state: state, staleDate: nil)
        await existing.update(content)
      } else {
        await existing.update(using: state)
      }
      return
    }

    let attributes = NomadeLiveActivityAttributes(id: key)
    if #available(iOS 16.2, *) {
      let content = ActivityContent(state: state, staleDate: nil)
      _ = try Activity<NomadeLiveActivityAttributes>.request(
        attributes: attributes,
        content: content,
        pushType: nil
      )
    } else {
      _ = try Activity<NomadeLiveActivityAttributes>.request(
        attributes: attributes,
        contentState: state,
        pushType: nil
      )
    }
  }

  func clear(conversationId: String, turnId: String) async {
    let key = activityKey(conversationId: conversationId, turnId: turnId)
    guard let existing = findActivity(for: key) else {
      return
    }
    if #available(iOS 16.2, *) {
      let currentState = existing.content.state
      let content = ActivityContent(state: currentState, staleDate: nil)
      await existing.end(content, dismissalPolicy: .immediate)
    } else {
      await existing.end(using: existing.contentState, dismissalPolicy: .immediate)
    }
  }

  private func findActivity(for key: String) -> Activity<NomadeLiveActivityAttributes>? {
    return Activity<NomadeLiveActivityAttributes>.activities.first { activity in
      activity.attributes.id == key
    }
  }

  private func activityKey(conversationId: String, turnId: String) -> String {
    if conversationId.isEmpty {
      return "conversation:\(turnId)"
    }
    return "\(conversationId):\(turnId)"
  }
}
#endif

private extension String {
  func ifEmpty(_ fallback: String) -> String {
    return isEmpty ? fallback : self
  }
}
