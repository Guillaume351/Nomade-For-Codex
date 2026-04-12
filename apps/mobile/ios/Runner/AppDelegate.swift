import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let launched = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    if let controller = window?.rootViewController as? FlutterViewController {
      let notificationsChannel = FlutterMethodChannel(
        name: "nomade/native_notifications",
        binaryMessenger: controller.binaryMessenger
      )
      notificationsChannel.setMethodCallHandler { call, result in
        if call.method == "getPushRegistration" {
          result(nil)
          return
        }
        result(FlutterMethodNotImplemented)
      }

      let runtimeChannel = FlutterMethodChannel(
        name: "nomade/runtime_status",
        binaryMessenger: controller.binaryMessenger
      )
      runtimeChannel.setMethodCallHandler { call, result in
        if call.method == "setRunningStatus" || call.method == "clearRunningStatus" {
          result(nil)
          return
        }
        result(FlutterMethodNotImplemented)
      }
    }
    return launched
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
