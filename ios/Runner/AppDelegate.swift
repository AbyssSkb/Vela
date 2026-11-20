import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let messenger = engineBridge.applicationRegistrar.messenger()
    FlutterMethodChannel(name: "vela/device", binaryMessenger: messenger)
      .setMethodCallHandler { call, result in
        guard call.method == "info" else {
          result(FlutterMethodNotImplemented)
          return
        }
        let device = UIDevice.current
        result(["name": device.name, "type": device.userInterfaceIdiom == .pad ? "tablet" : "mobile"])
      }
    FlutterMethodChannel(name: "vela/files", binaryMessenger: messenger)
      .setMethodCallHandler { call, result in
        guard call.method == "openUrl" else {
          result(FlutterMethodNotImplemented)
          return
        }
        guard let args = call.arguments as? [String: String], let value = args["url"],
          let url = URL(string: value), let scheme = url.scheme?.lowercased(),
          ["http", "https"].contains(scheme), url.host != nil
        else {
          result(FlutterError(code: "url", message: "Invalid web address", details: nil))
          return
        }
        UIApplication.shared.open(url) { opened in
          result(opened ? nil : FlutterError(code: "url", message: "Cannot open URL", details: nil))
        }
      }
  }
}
